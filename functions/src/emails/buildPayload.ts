import { format } from 'date-fns'
import { ru } from 'date-fns/locale'
import {
  categorize,
  type EmailClubStat,
  type EmailHoleRow,
  type MatchPlayInfo,
  type RoundSummaryPayload,
} from './types'

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

function resolveClubLabel(clubId: string, bag: BagClubLite[] | undefined): string {
  if (CLUB_ABBREV[clubId]) return CLUB_ABBREV[clubId]
  if (bag) {
    const found = bag.find(c => c.id === clubId)
    if (found?.customName && found.customName.trim().length > 0) return found.customName.trim()
  }
  if (clubId.startsWith('custom-')) return 'Клюшка'
  return clubId
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
  limit = 3,
): EmailClubStat[] {
  // Count by canonical/custom id first, then resolve labels at the end so
  // multiple ids that share a label (rare, but possible) don't collide.
  const counts = new Map<string, number>()
  let total = 0
  for (const h of round.holes) {
    for (const c of getShots(h.shots[uid])) {
      if (c === 'Неизвестно') continue
      counts.set(c, (counts.get(c) ?? 0) + 1)
      total += 1
    }
  }
  if (total === 0) return []
  return Array.from(counts.entries())
    .map(([clubId, count]) => ({
      club: resolveClubLabel(clubId, bag),
      count,
      percent: Math.round((count / total) * 100),
    }))
    .sort((a, b) => b.count - a.count || a.club.localeCompare(b.club))
    .slice(0, limit)
}

function matchInfo(round: RoundLike): MatchPlayInfo | null {
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
    leaderName: leaderUid ? round.players[leaderUid]?.name ?? null : null,
    closed,
    holesPlayed: played,
    holesRemaining: remaining,
  }
}

export function buildPayload(
  round: RoundLike,
  uid: string,
  bag: BagClubLite[] | undefined,
  appBaseUrl = 'https://smart-golf-caddy.web.app',
): RoundSummaryPayload {
  const player = round.players[uid]
  const scorecard = buildScorecard(round, uid)
  const holesPlayedByMe = scorecard.filter(r => r.score != null).length
  const totalScore = scorecard.reduce((s, r) => s + (r.score ?? 0), 0)
  const totalPar = scorecard
    .filter(r => r.score != null)
    .reduce((s, r) => s + r.par, 0)

  const dateSource = toDate(round.finishedAt) || toDate(round.createdAt)

  return {
    playerName: player?.name ?? 'Игрок',
    courseName: round.courseName,
    dateLabel: format(dateSource, 'd MMMM yyyy', { locale: ru }),
    totalHoles: round.totalHoles,
    holesPlayedByMe,
    totalScore,
    totalPar,
    scoreDiff: totalScore - totalPar,
    bestHole: bestHole(scorecard),
    scorecard,
    topClubs: topClubs(round, uid, bag),
    match: matchInfo(round),
    resultsUrl: `${appBaseUrl}/round/${round.id}/results`,
  }
}
