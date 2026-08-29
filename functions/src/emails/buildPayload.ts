import { format } from 'date-fns'
import { ru as ruDateFnsLocale, enUS as enDateFnsLocale } from 'date-fns/locale'
import {
  categorize,
  type EmailClubStat,
  type EmailHoleRow,
  type MatchPlayInfo,
  type RoundSummaryPayload,
} from './types'
import { getDictionary, type Dictionary, type Locale } from '../i18n'

// Minimal shape we need from the Firestore Round document. Kept loose
// because Functions read raw maps and we don't want a hard schema coupling.
export interface RoundLike {
  id: string
  courseName: string
  totalHoles: number
  playerIds: string[]
  playMode?: 'stroke' | 'match'
  players: Record<string, { name: string; email?: string }>
  holes: { holeNumber: number; par: number; shots: Record<string, { count: number; clubs?: string[]; club?: string }> }[]
  finishedAt?: { toDate?: () => Date } | Date | null
  createdAt?: { toDate?: () => Date } | Date | null
}

export interface BagClubLite {
  id: string
  customName?: string
}

// Canonical short abbreviations for built-in clubs — kept in sync with
// src/types/index.ts CLUB_ABBREV in the web app. Duplicated here so the
// Functions bundle doesn't pull the whole web types module.
const CLUB_ABBREV: Record<string, string> = {
  Driver: 'DRV',
  '3W': '3W', '5W': '5W', Hybrid: 'HY',
  '3i': '3i', '4i': '4i', '5i': '5i', '6i': '6i', '7i': '7i', '8i': '8i', '9i': '9i',
  PW: 'PW', GW: 'GW', SW: 'SW', LW: 'LW',
  '50°': '50°', '54°': '54°', '58°': '58°', '60°': '60°',
  Putter: 'PT',
}

// SYNC: PENALTY_ID в src/types/index.ts и Clubs.penaltyId в iOS
// (ios/SmartGolfCaddy/Models/Club.swift). Псевдо-клюшка «Штраф» — обычный
// элемент clubs[] (счёт +1), исключается из статистики клюшек так же, как
// «Неизвестно».
const PENALTY_ID = 'Штраф'

// The exact sentinel deleteAccount() (functions/src/index.ts) writes into
// players.{uid}.name when anonymising a departed group-round participant.
// Locale-neutral by design (mirrors PENALTY_ID/UNKNOWN_CLUB in
// src/types/index.ts): the stored value must render correctly for every
// viewer regardless of their language, so it can't itself be the Russian
// (or any other) display string. SYNC: DELETED_PLAYER_MARKER in
// src/types/index.ts and Players.deletedMarker in iOS
// (ios/SmartGolfCaddy/Models/Round.swift) — the literal must match exactly
// in all three places. Exported and imported back into index.ts so the
// string lives in exactly one place instead of being duplicated across the
// write site and this read site (the same discipline CLAUDE.md already
// calls for on CLUB_ABBREV).
export const DELETED_PLAYER_MARKER = '__deleted_player__'

// Pre-marker value: every deleteAccount() run before this change wrote this
// Russian literal instead of DELETED_PLAYER_MARKER. Those rounds belong to
// other players and are never migrated (see functions/src/index.ts), so
// this stays recognized here (and in the web/iOS display code) indefinitely.
const LEGACY_DELETED_PLAYER_NAME_RU = 'Удалённый игрок'

// Swaps the deleted-player marker (new or legacy) for its localized form;
// passes any other name through unchanged (including `undefined`, so
// callers can still apply their own fallback — see playerName/leaderName
// below).
function localizeDeletedName(name: string | undefined, t: Dictionary): string | undefined {
  return name === DELETED_PLAYER_MARKER || name === LEGACY_DELETED_PLAYER_NAME_RU
    ? t.deletedPlayerName
    : name
}

function resolveClubLabel(clubId: string, bag: BagClubLite[] | undefined, t: Dictionary): string {
  if (CLUB_ABBREV[clubId]) return CLUB_ABBREV[clubId]
  if (bag) {
    const found = bag.find(c => c.id === clubId)
    if (found?.customName && found.customName.trim().length > 0) return found.customName.trim()
  }
  if (clubId.startsWith('custom-')) return t.clubFallback
  return clubId
}

function dateFnsLocaleFor(locale: Locale) {
  return locale === 'ru' ? ruDateFnsLocale : enDateFnsLocale
}

function toDate(v: unknown): Date {
  if (!v) return new Date()
  if (v instanceof Date) return v
  if (typeof v === 'object' && v !== null && 'toDate' in v && typeof (v as { toDate: unknown }).toDate === 'function') {
    return (v as { toDate: () => Date }).toDate()
  }
  return new Date()
}

function getShots(shotsField: { count: number; clubs?: string[]; club?: string } | undefined): string[] {
  if (!shotsField) return []
  if (Array.isArray(shotsField.clubs) && shotsField.clubs.length > 0) return shotsField.clubs
  if (shotsField.club) return new Array<string>(shotsField.count).fill(shotsField.club)
  return new Array<string>(shotsField.count).fill('Неизвестно')
}

function buildScorecard(round: RoundLike, uid: string): EmailHoleRow[] {
  return round.holes.map(h => {
    const count = h.shots[uid]?.count ?? 0
    const score = count > 0 ? count : null
    const diff = score != null ? score - h.par : null
    return {
      hole: h.holeNumber,
      par: h.par,
      score,
      diff,
      category: categorize(diff),
    }
  })
}

function bestHole(rows: EmailHoleRow[]): EmailHoleRow | null {
  let best: EmailHoleRow | null = null
  for (const r of rows) {
    if (r.diff == null) continue
    if (best == null || r.diff < best.diff!) best = r
  }
  return best
}

function topClubs(
  round: RoundLike,
  uid: string,
  bag: BagClubLite[] | undefined,
  t: Dictionary,
  limit = 3,
): EmailClubStat[] {
  // Count by canonical/custom id first, then resolve labels at the end so
  // multiple ids that share a label (rare, but possible) don't collide.
  const counts = new Map<string, number>()
  let total = 0
  for (const h of round.holes) {
    for (const c of getShots(h.shots[uid])) {
      if (c === 'Неизвестно' || c === PENALTY_ID) continue
      counts.set(c, (counts.get(c) ?? 0) + 1)
      total += 1
    }
  }
  if (total === 0) return []
  return Array.from(counts.entries())
    .map(([clubId, count]) => ({
      club: resolveClubLabel(clubId, bag, t),
      count,
      percent: Math.round((count / total) * 100),
    }))
    .sort((a, b) => b.count - a.count || a.club.localeCompare(b.club))
    .slice(0, limit)
}

function matchInfo(round: RoundLike, t: Dictionary): MatchPlayInfo | null {
  if (round.playMode !== 'match' || round.playerIds.length !== 2) return null
  const [a, b] = round.playerIds
  let aUp = 0
  let bUp = 0
  let played = 0
  for (const h of round.holes) {
    const aCount = h.shots[a]?.count ?? 0
    const bCount = h.shots[b]?.count ?? 0
    if (aCount === 0 || bCount === 0) continue
    played += 1
    if (aCount < bCount) aUp += 1
    else if (bCount < aCount) bUp += 1
  }
  const delta = Math.abs(aUp - bUp)
  const remaining = round.holes.length - played
  const leaderUid = aUp > bUp ? a : bUp > aUp ? b : null
  const closed = delta > remaining
  let label: string
  if (remaining === 0) {
    label = delta === 0 ? 'AS' : `${delta} UP`
  } else if (closed) {
    label = `${delta}&${remaining}`
  } else if (delta === 0) {
    label = 'AS'
  } else {
    label = `${delta} UP`
  }
  return {
    label,
    leaderName: leaderUid ? localizeDeletedName(round.players[leaderUid]?.name, t) ?? null : null,
    closed,
    holesPlayed: played,
    holesRemaining: remaining,
  }
}

// Renders one recipient's payload in one locale. Called once per recipient
// (never once for the whole round) — a group round can mix locales, so
// buildPayload/RoundSummary are always invoked per-uid with that uid's own
// resolved locale (see resolveUserLocale + the onRoundFinished/
// shareRoundByEmail loops in ../index.ts). `locale` drives both the date
// formatting and every translated string (fallback player name, deleted-
// player name, custom-club fallback).
export function buildPayload(
  round: RoundLike,
  uid: string,
  bag: BagClubLite[] | undefined,
  locale: Locale,
  appBaseUrl = 'https://smart-golf-caddy.web.app',
): RoundSummaryPayload {
  const t = getDictionary(locale)
  const player = round.players[uid]
  const scorecard = buildScorecard(round, uid)
  const holesPlayedByMe = scorecard.filter(r => r.score != null).length
  const totalScore = scorecard.reduce((s, r) => s + (r.score ?? 0), 0)
  const totalPar = scorecard
    .filter(r => r.score != null)
    .reduce((s, r) => s + r.par, 0)

  const dateSource = toDate(round.finishedAt) || toDate(round.createdAt)

  return {
    playerName: localizeDeletedName(player?.name, t) ?? t.playerFallback,
    courseName: round.courseName,
    dateLabel: format(dateSource, 'd MMMM yyyy', { locale: dateFnsLocaleFor(locale) }),
    totalHoles: round.totalHoles,
    holesPlayedByMe,
    totalScore,
    totalPar,
    scoreDiff: totalScore - totalPar,
    bestHole: bestHole(scorecard),
    scorecard,
    topClubs: topClubs(round, uid, bag, t),
    match: matchInfo(round, t),
    resultsUrl: `${appBaseUrl}/round/${round.id}/results`,
  }
}

// Subject line, localized the same way as the body. Split out from the
// caller in ../index.ts purely so it's unit-testable without going through
// Resend/render().
export function buildSubject(payload: RoundSummaryPayload, locale: Locale): string {
  const t = getDictionary(locale)
  const diffLabel =
    payload.scoreDiff === 0 ? '(E)' : payload.scoreDiff > 0 ? `(+${payload.scoreDiff})` : `(${payload.scoreDiff})`
  return `${t.title}: ${payload.courseName} — ${payload.totalScore || '—'} ${diffLabel}`
}
