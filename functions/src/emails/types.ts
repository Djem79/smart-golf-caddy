// Minimal copy of types needed for email rendering — kept independent of
// the web app's `src/types/index.ts` to avoid pulling its Firebase deps
// into the Functions bundle.

export type ScoreCategory =
  | 'eagle'
  | 'birdie'
  | 'par'
  | 'bogey'
  | 'double'
  | 'worse'
  | 'empty'

export interface EmailHoleRow {
  hole: number
  par: number
  score: number | null     // null = the player didn't record shots
  diff: number | null
  category: ScoreCategory
}

export interface EmailClubStat {
  club: string
  count: number
  percent: number          // 0-100, rounded
}

export interface MatchPlayInfo {
  label: string            // 'AS', '3 UP', '4&3', etc.
  leaderName: string | null
  closed: boolean
  holesPlayed: number
  holesRemaining: number
}

export interface RoundSummaryPayload {
  playerName: string
  courseName: string
  dateLabel: string        // pre-formatted '19 мая 2026'
  totalHoles: number
  holesPlayedByMe: number
  totalScore: number
  totalPar: number
  scoreDiff: number        // totalScore - totalPar; can be negative
  bestHole: EmailHoleRow | null
  scorecard: EmailHoleRow[]    // length === totalHoles
  topClubs: EmailClubStat[]
  match: MatchPlayInfo | null
  resultsUrl: string       // deep link back to web app
}

// Visual encoding — kept in lock step with `scoreColor` in web app, but
// expressed as inline-safe colours that work in every email client.
export const PILL_COLORS: Record<ScoreCategory, { bg: string; fg: string }> = {
  eagle:  { bg: '#7C3AED', fg: '#FFFFFF' },
  birdie: { bg: '#42A5F5', fg: '#FFFFFF' },
  par:    { bg: '#66BB6A', fg: '#FFFFFF' },
  bogey:  { bg: '#9E9E9E', fg: '#FFFFFF' },
  double: { bg: '#EF5350', fg: '#FFFFFF' },
  worse:  { bg: '#9A1A1A', fg: '#FFFFFF' },
  empty:  { bg: '#EEEEEE', fg: '#41493E' },
}

export function categorize(diff: number | null): ScoreCategory {
  if (diff == null) return 'empty'
  if (diff <= -2) return 'eagle'
  if (diff === -1) return 'birdie'
  if (diff === 0) return 'par'
  if (diff === 1) return 'bogey'
  if (diff === 2) return 'double'
  return 'worse'
}

export function categoryLabel(cat: ScoreCategory): string {
  switch (cat) {
    case 'eagle':  return 'Eagle'
    case 'birdie': return 'Birdie'
    case 'par':    return 'Par'
    case 'bogey':  return 'Bogey'
    case 'double': return 'Double'
    case 'worse':  return 'Хуже'
    case 'empty':  return '—'
  }
}

export function formatDiff(diff: number | null): string {
  if (diff == null) return '—'
  if (diff === 0) return 'E'
  if (diff > 0) return `+${diff}`
  return String(diff)
}
