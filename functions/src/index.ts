import { initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'
import { onDocumentUpdated } from 'firebase-functions/v2/firestore'
import { onCall, HttpsError } from 'firebase-functions/v2/https'
import { defineSecret } from 'firebase-functions/params'
import { logger } from 'firebase-functions'
import { render } from '@react-email/render'
import { Resend } from 'resend'
import * as React from 'react'

import { RoundSummary } from './emails/RoundSummary'
import { buildPayload, type BagClubLite, type RoundLike } from './emails/buildPayload'

initializeApp()

// Fallback: pull email straight from Firebase Auth when the round document
// has no email recorded (e.g. legacy rounds created before PlayerInfo got
// the field).
async function resolveEmail(round: RoundLike, uid: string): Promise<string> {
  const recorded = round.players[uid]?.email
  if (recorded) return recorded
  try {
    const record = await getAuth().getUser(uid)
    return record.email ?? ''
  } catch (e) {
    logger.warn('Auth lookup failed for user', { uid, error: e instanceof Error ? e.message : 'unknown' })
    return ''
  }
}

// Pull the user's bag from users/{uid}.bag so that custom club ids resolve
// to their human-readable customName in the email. Falls back to undefined
// when the doc or field is missing — payload builder then treats unknown
// ids as 'Клюшка' / the raw id.
async function resolveBag(uid: string): Promise<BagClubLite[] | undefined> {
  try {
    const snap = await getFirestore().doc(`users/${uid}`).get()
    if (!snap.exists) return undefined
    const data = snap.data() as { bag?: BagClubLite[] } | undefined
    return Array.isArray(data?.bag) ? data.bag : undefined
  } catch (e) {
    logger.warn('Bag lookup failed for user', { uid, error: e instanceof Error ? e.message : 'unknown' })
    return undefined
  }
}

const RESEND_API_KEY = defineSecret('RESEND_API_KEY')

// Default sender. Works only in Resend's dev mode (mails go to the account
// owner). For real rollout, swap to a verified domain via env override.
const DEFAULT_FROM = 'Smart Golf Caddy <onboarding@resend.dev>'
const APP_BASE_URL = 'https://smart-golf-caddy.web.app'

interface SendResult {
  uid: string
  email: string
  ok: boolean
  reason?: string
}

async function sendOneRoundEmail(
  resend: Resend,
  round: RoundLike,
  uid: string,
  toOverride?: string,
): Promise<SendResult> {
  const recipient = toOverride ?? (await resolveEmail(round, uid))
  if (!recipient) {
    return { uid, email: '', ok: false, reason: 'no email available (player + auth both empty)' }
  }

  const bag = await resolveBag(uid)
  const payload = buildPayload(round, uid, bag, APP_BASE_URL)
  const element = React.createElement(RoundSummary, { data: payload })
  const html = await render(element)
  const text = await render(element, { plainText: true })

  const subject = `${round.courseName} — ${payload.totalScore || '—'} ${
    payload.scoreDiff === 0 ? '(E)' : payload.scoreDiff > 0 ? `(+${payload.scoreDiff})` : `(${payload.scoreDiff})`
  }`

  const from = process.env.MAIL_FROM || DEFAULT_FROM

  try {
    const { error } = await resend.emails.send({
      from,
      to: recipient,
      subject,
      html,
      text,
    })
    if (error) {
      logger.warn('Resend rejected email', { uid, email: recipient, error })
      return { uid, email: recipient, ok: false, reason: error.message }
    }
    return { uid, email: recipient, ok: true }
  } catch (e: unknown) {
    const reason = e instanceof Error ? e.message : 'unknown error'
    logger.error('Resend threw', { uid, email: recipient, reason })
    return { uid, email: recipient, ok: false, reason }
  }
}

// Redact an email for storage: 'john.doe@gmail.com' → 'jo***@gmail.com'.
// Used in emailResults so participants reading the round doc can debug
// delivery without exposing other players' addresses.
function redactEmail(email: string): string {
  const [local, domain] = email.split('@')
  if (!domain) return '***'
  const visible = local.length <= 2 ? local : local.slice(0, 2)
  return `${visible}***@${domain}`
}

// Cloud Functions Firestore triggers are at-least-once: the same event can
// fire twice on transient infra failures. To avoid duplicate sends we use a
// short-lived `emailingStartedAt` lease — any second invocation arriving
// within 5 minutes of the first will see the lease and exit. After 5 min
// the lease is considered stale (in case the first invocation crashed
// mid-send) and a retry is permitted to fill in any uids missing from
// `emailedTo`.
const SEND_LEASE_MS = 5 * 60 * 1000

// 1. Auto-trigger: fires when a round transitions to 'finished'.
export const onRoundFinished = onDocumentUpdated(
  {
    document: 'rounds/{roundId}',
    region: 'us-central1',
    secrets: [RESEND_API_KEY],
  },
  async event => {
    const before = event.data?.before.data()
    const after = event.data?.after.data()
    const roundId = event.params.roundId

    if (!before || !after) return

    // Only act when status JUST flipped to 'finished'.
    if (after.status !== 'finished' || before.status === 'finished') return

    const ref = getFirestore().doc(`rounds/${roundId}`)

    // Atomic lease: read fresh, check completion+lease, write lease, all in
    // one transaction. The pre-write event snapshot is stale by the time
    // we get here — the lease must be checked against current Firestore state.
    const proceed = await getFirestore().runTransaction(async tx => {
      const snap = await tx.get(ref)
      if (!snap.exists) return { go: false, alreadyDone: new Set<string>() }
      const data = snap.data() as
        | {
            playerIds?: string[]
            emailedAt?: { toMillis?: () => number } | null
            emailingStartedAt?: { toMillis?: () => number } | null
            emailedTo?: Record<string, boolean>
          }
        | undefined

      const alreadyDone = new Set<string>(
        Object.entries(data?.emailedTo ?? {})
          .filter(([, ok]) => ok === true)
          .map(([uid]) => uid),
      )

      // All recipients already covered → no work.
      const playerIds = data?.playerIds ?? []
      if (data?.emailedAt) return { go: false, alreadyDone }
      if (playerIds.every(uid => alreadyDone.has(uid))) {
        return { go: false, alreadyDone }
      }

      // Honour an in-flight lease (another invocation is sending right now).
      const startedAtMs = data?.emailingStartedAt?.toMillis?.() ?? 0
      if (startedAtMs && Date.now() - startedAtMs < SEND_LEASE_MS) {
        logger.info('Another invocation holds the send lease, skipping', {
          roundId,
          ageMs: Date.now() - startedAtMs,
        })
        return { go: false, alreadyDone }
      }

      tx.update(ref, { emailingStartedAt: FieldValue.serverTimestamp() })
      return { go: true, alreadyDone }
    })

    if (!proceed.go) return

    const round: RoundLike = { ...(after as Omit<RoundLike, 'id'>), id: roundId }
    const resend = new Resend(RESEND_API_KEY.value())

    const results: SendResult[] = []
    const emailedTo: Record<string, boolean> = {}
    // Sequential by design — Resend's free tier rate-limits at 2 req/sec.
    for (const uid of round.playerIds ?? []) {
      if (proceed.alreadyDone.has(uid)) {
        // Already sent in a previous (possibly partial) run.
        emailedTo[uid] = true
        continue
      }
      // Cap auto-emails per recipient/day. If exceeded, skip without marking
      // emailedTo so a later re-trigger can still deliver (and allOk stays
      // false, so emailedAt isn't stamped).
      const withinAutoQuota = await bumpDailyQuota(uid, 'auto', AUTO_EMAIL_DAILY_LIMIT)
      if (!withinAutoQuota) {
        results.push({ uid, email: '', ok: false, reason: 'daily auto-email cap reached' })
        continue
      }
      const r = await sendOneRoundEmail(resend, round, uid)
      results.push({ ...r, email: r.email ? redactEmail(r.email) : '' })
      if (r.ok) emailedTo[uid] = true
    }

    const allOk = (round.playerIds ?? []).every(uid => emailedTo[uid])
    const patch: Record<string, unknown> = {
      emailedTo: { ...(proceed.alreadyDone.size > 0
        ? Object.fromEntries(Array.from(proceed.alreadyDone).map(uid => [uid, true]))
        : {}), ...emailedTo },
      emailResults: FieldValue.arrayUnion(...results),
      emailingStartedAt: FieldValue.delete(),
    }
    // Only stamp emailedAt when EVERY recipient is covered. Partial failures
    // leave it null so a later trigger (e.g. status re-flip via debug tool)
    // can retry only the missing uids.
    if (allOk) patch.emailedAt = FieldValue.serverTimestamp()

    await ref.update(patch)
    logger.info('Round emails dispatched', { roundId, results, allOk })
  },
)

// 2. Record-shot — server-authoritative write. Closes the cross-player
//    griefing vector (a participant could previously rewrite another
//    player's shots via the holes-array rewrite path). Also uses dot-path
//    updates which scale better than rewriting the full holes array.
interface RecordShotInput {
  roundId?: string
  holeIndex?: number
  clubs?: string[]
  // Whose slot to write. Optional — defaults to the caller. The host may
  // pass another participant's uid to keep score for the whole group
  // (single-device play / filling in for a player who couldn't join). Any
  // non-host caller may only write their own slot.
  targetUid?: string
}

export const recordShot = onCall(
  { region: 'us-central1', enforceAppCheck: false },
  async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Требуется вход')
    const { roundId, holeIndex, clubs, targetUid } = (request.data ?? {}) as RecordShotInput
    if (!roundId) throw new HttpsError('invalid-argument', 'roundId обязателен')
    if (typeof holeIndex !== 'number' || holeIndex < 0 || holeIndex > 17) {
      throw new HttpsError('invalid-argument', 'Некорректный holeIndex')
    }
    if (!Array.isArray(clubs) || clubs.length > 30) {
      throw new HttpsError('invalid-argument', 'Некорректный список клюшек')
    }
    for (const c of clubs) {
      if (typeof c !== 'string' || c.length === 0 || c.length > 50) {
        throw new HttpsError('invalid-argument', 'Некорректный id клюшки')
      }
    }
    if (targetUid != null && (typeof targetUid !== 'string' || targetUid.length === 0 || targetUid.length > 128)) {
      throw new HttpsError('invalid-argument', 'Некорректный targetUid')
    }

    const callerUid = request.auth.uid
    // Default to writing the caller's own slot when no explicit target given.
    const target = targetUid && targetUid.length > 0 ? targetUid : callerUid
    const ref = getFirestore().doc(`rounds/${roundId}`)
    await getFirestore().runTransaction(async tx => {
      const snap = await tx.get(ref)
      if (!snap.exists) throw new HttpsError('not-found', 'Раунд не найден')
      const data = snap.data() as Omit<RoundLike, 'id'> & {
        status: string
        hostId: string
        playerIds: string[]
        holes: { holeNumber: number; par: number; shots: Record<string, unknown> }[]
      }
      if (data.status !== 'active') {
        throw new HttpsError('failed-precondition', 'Раунд неактивен')
      }
      if (!data.playerIds?.includes(callerUid)) {
        throw new HttpsError('permission-denied', 'Только участники могут записывать удары')
      }
      // Writing for another player is host-only — closes the cross-player
      // griefing vector while still letting the host keep score for everyone.
      if (target !== callerUid && data.hostId !== callerUid) {
        throw new HttpsError('permission-denied', 'Только хост может записывать удары за других игроков')
      }
      if (!data.playerIds?.includes(target)) {
        throw new HttpsError('invalid-argument', 'Игрок не участвует в раунде')
      }
      if (holeIndex >= data.holes.length) {
        throw new HttpsError('invalid-argument', 'Лунка вне диапазона')
      }
      // Rewrite only the targeted hole's `shots[target]` slot; everything else
      // in the holes array is preserved untouched. We can't use a true dot-path
      // because Firestore doesn't support `holes.${i}` syntax on array fields,
      // but we explicitly read-then-write the same array shape so the diff is
      // bounded to a single nested record.
      const holes = data.holes.map((h, i) =>
        i === holeIndex
          ? {
              ...h,
              shots: {
                ...(h.shots ?? {}),
                [target]: {
                  count: clubs.length,
                  clubs,
                  club: clubs[clubs.length - 1] ?? '',
                  updatedAt: new Date(),
                },
              },
            }
          : h,
      )
      tx.update(ref, { holes })
    })

    return { ok: true }
  },
)

// Update hole config (par and/or distance) — host-only. Used to correct
// the hardcoded DEFAULT_HOLE_PARS template + distance multipliers against
// the real course layout. At least one field must be present.
interface UpdateHoleConfigInput {
  roundId?: string
  holeIndex?: number
  par?: number
  distanceMeters?: number
}

export const updateHoleConfig = onCall(
  { region: 'us-central1', enforceAppCheck: false },
  async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Требуется вход')
    const { roundId, holeIndex, par, distanceMeters } =
      (request.data ?? {}) as UpdateHoleConfigInput
    if (!roundId) throw new HttpsError('invalid-argument', 'roundId обязателен')
    if (typeof holeIndex !== 'number' || holeIndex < 0 || holeIndex > 17) {
      throw new HttpsError('invalid-argument', 'Некорректный holeIndex')
    }
    if (par != null && par !== 3 && par !== 4 && par !== 5) {
      throw new HttpsError('invalid-argument', 'Par должен быть 3, 4 или 5')
    }
    if (distanceMeters != null) {
      if (
        typeof distanceMeters !== 'number' ||
        !Number.isFinite(distanceMeters) ||
        distanceMeters < 50 ||
        distanceMeters > 700
      ) {
        throw new HttpsError('invalid-argument', 'Дистанция должна быть 50–700 метров')
      }
    }
    if (par == null && distanceMeters == null) {
      throw new HttpsError('invalid-argument', 'Нечего обновлять')
    }

    const uid = request.auth.uid
    const ref = getFirestore().doc(`rounds/${roundId}`)
    await getFirestore().runTransaction(async tx => {
      const snap = await tx.get(ref)
      if (!snap.exists) throw new HttpsError('not-found', 'Раунд не найден')
      const data = snap.data() as {
        hostId?: string
        holes?: { par: number; distanceMeters: number }[]
      }
      if (data.hostId !== uid) {
        throw new HttpsError('permission-denied', 'Только хост может менять конфигурацию лунки')
      }
      const holes = (data.holes ?? []).slice()
      if (holeIndex >= holes.length) {
        throw new HttpsError('invalid-argument', 'Лунка вне диапазона')
      }
      const next = { ...holes[holeIndex] }
      if (par != null) next.par = par
      if (distanceMeters != null) next.distanceMeters = Math.round(distanceMeters)
      holes[holeIndex] = next
      tx.update(ref, { holes })
    })

    return { ok: true }
  },
)

// 3. Join lobby by code — server-authoritative lookup so we can keep
//    rounds/{id} reads strictly participant-only. Client passes the 6-char
//    lobby code + their own PlayerInfo; function finds the round and adds
//    them to playerIds + players[uid].
interface JoinLobbyInput {
  code?: string
  playerInfo?: {
    name?: string
    avatar?: string
    email?: string
    totalScore?: number
    scoreDiff?: number
  }
}

export const joinLobbyByCode = onCall(
  { region: 'us-central1', enforceAppCheck: false },
  async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Требуется вход')
    const { code, playerInfo } = (request.data ?? {}) as JoinLobbyInput
    const trimmed = (code ?? '').trim().toUpperCase()
    if (trimmed.length !== 6) {
      throw new HttpsError('invalid-argument', 'Код должен содержать 6 символов')
    }
    const info = playerInfo ?? {}
    const cleanInfo = {
      name: typeof info.name === 'string' ? info.name.slice(0, 64) : 'Голфер',
      avatar: typeof info.avatar === 'string' ? info.avatar.slice(0, 512) : '',
      email: typeof info.email === 'string' ? info.email.slice(0, 254) : '',
      totalScore: 0,
      scoreDiff: 0,
    }

    const uid = request.auth.uid

    // Rate-limit join attempts (hits AND misses) per user/day so an attacker
    // can't enumerate lobby codes — each guessed hit would otherwise auto-join
    // them into a stranger's round.
    const withinJoinQuota = await bumpDailyQuota(uid, 'join', JOIN_DAILY_LIMIT)
    if (!withinJoinQuota) {
      throw new HttpsError(
        'resource-exhausted',
        'Слишком много попыток подключения. Попробуйте позже.',
      )
    }

    const db = getFirestore()
    const matches = await db
      .collection('rounds')
      .where('lobbyCode', '==', trimmed)
      .where('status', '==', 'lobby')
      .limit(1)
      .get()

    if (matches.empty) return { roundId: null as string | null }

    const docRef = matches.docs[0].ref
    const docSnap = matches.docs[0]
    const data = docSnap.data() as { playerIds?: string[] }
    const already = (data.playerIds ?? []).includes(uid)

    if (!already) {
      await docRef.update({
        [`players.${uid}`]: cleanInfo,
        playerIds: FieldValue.arrayUnion(uid),
      })
    }
    return { roundId: docSnap.id }
  },
)

// 4. Manual share: callable function used by RoundResults' Share dialog.
interface ShareInput {
  roundId?: string
  toEmail?: string
}

// Strict email format: single addr-spec, no header-injection chars, no
// whitespace, requires one '@' and a dot in the domain. Deliberately tighter
// than RFC — Resend itself does extra validation, but we reject obvious
// junk early so spammers get a fast 400 instead of a queued send.
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/

const SHARE_DAILY_LIMIT = 10
// Cap join-by-code attempts per user/day — bounds lobby-code enumeration via
// the (auto-joining) joinLobbyByCode callable. A real user joins few lobbies.
const JOIN_DAILY_LIMIT = 30
// Cap auto-summary emails a single user can receive per day — bounds Resend
// volume if rounds are finished/re-finished in bulk. Manual share has its own
// SHARE_DAILY_LIMIT.
const AUTO_EMAIL_DAILY_LIMIT = 30

function today(): string {
  return new Date().toISOString().slice(0, 10) // 'YYYY-MM-DD'
}

type QuotaKind = 'share' | 'join' | 'auto'

// Per-user, per-kind daily quota in `userQuota/{uid}`. The doc is Admin-SDK
// only (rules block ALL client access), so a malicious client can't reset its
// own counter. Each kind is a `{ day, count }` sub-map so share/join/auto
// don't share a budget. Returns false when today's limit for `kind` is hit.
async function bumpDailyQuota(uid: string, kind: QuotaKind, limit: number): Promise<boolean> {
  const ref = getFirestore().doc(`userQuota/${uid}`)
  return getFirestore().runTransaction(async tx => {
    const snap = await tx.get(ref)
    const data = (snap.exists ? snap.data() : null) as
      | Record<string, { day?: string; count?: number } | undefined>
      | null
    const entry = data?.[kind]
    const day = today()
    const count = entry?.day === day ? entry.count ?? 0 : 0
    if (count >= limit) return false
    tx.set(ref, { [kind]: { day, count: count + 1 } }, { merge: true })
    return true
  })
}

export const shareRoundByEmail = onCall(
  {
    region: 'us-central1',
    secrets: [RESEND_API_KEY],
    enforceAppCheck: false,
  },
  async request => {
    const { roundId, toEmail } = (request.data ?? {}) as ShareInput
    if (!request.auth) throw new HttpsError('unauthenticated', 'Требуется вход')
    if (!roundId) throw new HttpsError('invalid-argument', 'roundId обязателен')

    const cleanEmail = (toEmail ?? '').trim().toLowerCase()
    if (!EMAIL_RE.test(cleanEmail) || cleanEmail.length > 254) {
      throw new HttpsError('invalid-argument', 'Некорректный email')
    }

    const snap = await getFirestore().doc(`rounds/${roundId}`).get()
    if (!snap.exists) throw new HttpsError('not-found', 'Раунд не найден')

    const data = snap.data() as Omit<RoundLike, 'id'>
    if (!data.playerIds?.includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'Только участники могут делиться раундом')
    }

    // Recipient allow-list: the caller's own auth email, or any participant's
    // recorded email. Closes the open-relay vector — share is meant for "send
    // me my receipt" or "forward to the guy who missed the auto-email",
    // not for blasting arbitrary addresses.
    const callerEmail = (request.auth.token.email ?? '').toLowerCase()
    const participantEmails = new Set<string>(
      Object.values(data.players ?? {})
        .map(p => (p?.email ?? '').toLowerCase())
        .filter(Boolean),
    )
    if (callerEmail) participantEmails.add(callerEmail)
    if (!participantEmails.has(cleanEmail)) {
      throw new HttpsError(
        'permission-denied',
        'Можно отправить только себе или другому участнику раунда',
      )
    }

    // Daily per-user quota — transactional, runs before send so a 429 from
    // Resend doesn't burn quota.
    const withinShareQuota = await bumpDailyQuota(request.auth.uid, 'share', SHARE_DAILY_LIMIT)
    if (!withinShareQuota) {
      throw new HttpsError(
        'resource-exhausted',
        `Дневной лимит на отправку (${SHARE_DAILY_LIMIT}) исчерпан. Попробуйте завтра.`,
      )
    }

    const round: RoundLike = { ...data, id: roundId }
    const resend = new Resend(RESEND_API_KEY.value())

    const result = await sendOneRoundEmail(resend, round, request.auth.uid, cleanEmail)
    if (!result.ok) {
      throw new HttpsError('internal', result.reason ?? 'Не удалось отправить письмо')
    }
    return { ok: true }
  },
)
