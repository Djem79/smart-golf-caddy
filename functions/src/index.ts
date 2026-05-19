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

    // Guard: only act on the moment status flips to 'finished'.
    if (after.status !== 'finished' || before.status === 'finished') return

    // Idempotency: don't re-send if a previous run already emailed.
    if (after.emailedAt) {
      logger.info('Round already emailed, skipping', { roundId })
      return
    }

    const round: RoundLike = { ...(after as Omit<RoundLike, 'id'>), id: roundId }
    const resend = new Resend(RESEND_API_KEY.value())

    const results: SendResult[] = []
    // Sequential by design — Resend's free tier rate-limits at 2 req/sec.
    for (const uid of round.playerIds ?? []) {
      const r = await sendOneRoundEmail(resend, round, uid)
      results.push(r)
    }

    // Mark as sent so retries from Cloud Functions infrastructure are no-ops.
    await getFirestore()
      .doc(`rounds/${roundId}`)
      .update({
        emailedAt: FieldValue.serverTimestamp(),
        emailResults: results,
      })

    logger.info('Round emails dispatched', { roundId, results })
  },
)

// 2. Manual share: callable function used by RoundResults' Share dialog.
interface ShareInput {
  roundId?: string
  toEmail?: string
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
    if (!toEmail || !/.+@.+\..+/.test(toEmail)) {
      throw new HttpsError('invalid-argument', 'Некорректный email')
    }

    const snap = await getFirestore().doc(`rounds/${roundId}`).get()
    if (!snap.exists) throw new HttpsError('not-found', 'Раунд не найден')

    const data = snap.data() as Omit<RoundLike, 'id'>
    if (!data.playerIds?.includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'Только участники могут делиться раундом')
    }

    const round: RoundLike = { ...data, id: roundId }
    const resend = new Resend(RESEND_API_KEY.value())

    // Build the email from the caller's perspective — they're the one sharing.
    const result = await sendOneRoundEmail(resend, round, request.auth.uid, toEmail)
    if (!result.ok) {
      throw new HttpsError('internal', result.reason ?? 'Не удалось отправить письмо')
    }
    return { ok: true }
  },
)
