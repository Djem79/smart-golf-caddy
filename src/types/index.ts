export type DistanceUnit = 'm' | 'yd'

export type ClubCategory = 'wood' | 'iron' | 'wedge' | 'putter'

export interface BagClub {
  id: string                 // canonical key: 'Driver', '7i', 'Putter', or 'custom-<rand>'
  customName?: string        // user's model name, e.g., 'Stealth 2 HD'
  distanceMeters: number     // always stored in metres (UI converts to yards if needed)
  enabled: boolean           // is the club in the active bag right now
  category?: ClubCategory    // group it belongs to (defaults are inferred from id)
  custom?: boolean           // true for user-added clubs (removable)
}

export interface AppUser {
  uid: string
  name: string
  avatar: string
  handicap: number
  bag?: BagClub[]            // new canonical bag
  units?: DistanceUnit       // user's distance preference
  clubs?: string[]           // legacy: list of enabled club ids (pre-bag rollout)
}

export interface HoleShots {
  count: number       // equals clubs.length for new writes
  clubs: string[]     // ordered list, one entry per stroke
  club?: string       // legacy: present in older rounds (last-used club)
  updatedAt: Date
}

// Canonical clubs[] for both new and legacy data
export function getHoleClubs(shots: HoleShots | undefined): string[] {
  if (!shots) return []
  if (Array.isArray(shots.clubs) && shots.clubs.length > 0) return shots.clubs
  if (shots.club) return new Array<string>(shots.count).fill(shots.club)
  return new Array<string>(shots.count).fill('Неизвестно')
}

export interface HoleConfig {
  holeNumber: number
  par: 3 | 4 | 5
  distanceMeters: number
  shots: Record<string, HoleShots>
}

export interface PlayerInfo {
  name: string
  avatar: string
  totalScore: number
  scoreDiff: number
}

export type RoundStatus = 'lobby' | 'active' | 'finished'

export interface Round {
  id: string
  courseId: string
  courseName: string
  totalHoles: 9 | 18
  lobbyCode: string
  status: RoundStatus
  hostId: string
  players: Record<string, PlayerInfo>
  playerIds: string[]            // denormalized for Firestore array-contains queries
  holes: HoleConfig[]
  startedAt: Date | null         // null while a group round is in lobby state
  finishedAt: Date | null
  createdAt: Date
}

export interface CourseResult {
  placeId: string
  name: string
  distanceKm: number
  vicinity: string
  rating?: number
  userRatingsTotal?: number
  photoUrl?: string             // fully-formed URL usable directly as <img src>
  location: { lat: number; lng: number }
}

export const DEFAULT_CLUBS: string[] = [
  'Driver', '3W', '5W',
  '4i', '5i', '6i', '7i', '8i', '9i',
  'PW', 'GW', 'SW', 'LW',
  'Putter',
]

export const CLUB_ABBREV: Record<string, string> = {
  Driver: 'DRV', '3W': '3W', '5W': '5W',
  '4i': '4i', '5i': '5i', '6i': '6i', '7i': '7i', '8i': '8i', '9i': '9i',
  PW: 'PW', GW: 'GW', SW: 'SW', LW: 'LW', Putter: 'PT',
}

export const DEFAULT_HOLE_PARS: Record<9 | 18, (3 | 4 | 5)[]> = {
  9:  [4, 3, 5, 4, 4, 3, 5, 4, 4],
  18: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4],
}

// Default bag — average distances per club for a recreational golfer
export const DEFAULT_BAG: BagClub[] = [
  { id: 'Driver', distanceMeters: 230, enabled: true,  category: 'wood'   },
  { id: '3W',     distanceMeters: 210, enabled: true,  category: 'wood'   },
  { id: '5W',     distanceMeters: 195, enabled: false, category: 'wood'   },
  { id: '4i',     distanceMeters: 175, enabled: false, category: 'iron'   },
  { id: '5i',     distanceMeters: 165, enabled: true,  category: 'iron'   },
  { id: '6i',     distanceMeters: 150, enabled: true,  category: 'iron'   },
  { id: '7i',     distanceMeters: 140, enabled: true,  category: 'iron'   },
  { id: '8i',     distanceMeters: 125, enabled: true,  category: 'iron'   },
  { id: '9i',     distanceMeters: 110, enabled: true,  category: 'iron'   },
  { id: 'PW',     distanceMeters: 95,  enabled: true,  category: 'wedge'  },
  { id: 'GW',     distanceMeters: 80,  enabled: false, category: 'wedge'  },
  { id: 'SW',     distanceMeters: 70,  enabled: true,  category: 'wedge'  },
  { id: 'LW',     distanceMeters: 55,  enabled: false, category: 'wedge'  },
  { id: 'Putter', distanceMeters: 0,   enabled: true,  category: 'putter' },
]

export const CLUB_GROUPS: Array<{ category: ClubCategory; label: string; defaultIds: string[] }> = [
  { category: 'wood',   label: 'Драйвер и вуды', defaultIds: ['Driver', '3W', '5W'] },
  { category: 'iron',   label: 'Айроны',         defaultIds: ['4i', '5i', '6i', '7i', '8i', '9i'] },
  { category: 'wedge',  label: 'Вейджи',         defaultIds: ['PW', 'GW', 'SW', 'LW'] },
  { category: 'putter', label: 'Паттер',         defaultIds: ['Putter'] },
]

// Resolve a club's category — explicit field wins, otherwise infer from id
export function getClubCategory(club: BagClub): ClubCategory {
  if (club.category) return club.category
  for (const group of CLUB_GROUPS) {
    if (group.defaultIds.includes(club.id)) return group.category
  }
  return 'iron' // safe default for unknown ids
}

// Normalize a user document into the canonical bag shape:
// - Prefer the new `bag` field (backfill missing category from id)
// - Fall back to legacy `clubs: string[]` by enabling only those ids in DEFAULT_BAG
// - Otherwise return the full DEFAULT_BAG
export function getBagFromUser(user: { bag?: BagClub[]; clubs?: string[] } | null | undefined): BagClub[] {
  if (user?.bag && user.bag.length > 0) {
    return user.bag.map(c => c.category ? c : { ...c, category: getClubCategory(c) })
  }
  if (user?.clubs && user.clubs.length > 0) {
    const enabled = new Set(user.clubs)
    return DEFAULT_BAG.map(c => ({ ...c, enabled: enabled.has(c.id) }))
  }
  return DEFAULT_BAG
}

export function enabledBagClubs(bag: BagClub[]): BagClub[] {
  return bag.filter(c => c.enabled)
}

// Resolve a club id to a short, user-facing label.
// - Default clubs: their canonical abbreviation (e.g. 'Driver' -> 'DRV', '7i' -> '7i').
// - Custom clubs: the customName from the bag.
// - Custom clubs missing from the bag (deleted, or another player's in group play): 'Клюшка'.
// - Unknown non-custom ids: returned unchanged (defensive fallback).
export function getClubLabel(clubId: string, bag: BagClub[]): string {
  if (CLUB_ABBREV[clubId]) return CLUB_ABBREV[clubId]
  const club = bag.find(c => c.id === clubId)
  if (club?.customName && club.customName.trim().length > 0) return club.customName
  if (clubId.startsWith('custom-')) return 'Клюшка'
  return clubId
}

export function metersToYards(m: number): number {
  return Math.round(m * 1.0936)
}

export function yardsToMeters(y: number): number {
  return Math.round(y / 1.0936)
}

export function scoreColor(delta: number): string {
  if (delta <= -2) return '#FFD700'
  if (delta === -1) return '#4CAF50'
  if (delta === 0)  return '#FFFFFF'
  if (delta === 1)  return '#FF9800'
  return '#F44336'
}

export function scoreLabel(delta: number): string {
  if (delta <= -2) return 'Eagle'
  if (delta === -1) return 'Birdie'
  if (delta === 0)  return 'Par'
  if (delta === 1)  return 'Bogey'
  if (delta === 2)  return 'Double'
  return `+${delta}`
}
