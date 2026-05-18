export type DistanceUnit = 'm' | 'yd'

export interface BagClub {
  id: string                 // canonical key: 'Driver', '7i', 'Putter', etc.
  customName?: string        // user's model name, e.g., 'Stealth 2 HD'
  distanceMeters: number     // always stored in metres (UI converts to yards if needed)
  enabled: boolean           // is the club in the active bag right now
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
  holes: HoleConfig[]
  startedAt: Date
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
  photoReference?: string
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
  { id: 'Driver', distanceMeters: 230, enabled: true  },
  { id: '3W',     distanceMeters: 210, enabled: true  },
  { id: '5W',     distanceMeters: 195, enabled: false },
  { id: '4i',     distanceMeters: 175, enabled: false },
  { id: '5i',     distanceMeters: 165, enabled: true  },
  { id: '6i',     distanceMeters: 150, enabled: true  },
  { id: '7i',     distanceMeters: 140, enabled: true  },
  { id: '8i',     distanceMeters: 125, enabled: true  },
  { id: '9i',     distanceMeters: 110, enabled: true  },
  { id: 'PW',     distanceMeters: 95,  enabled: true  },
  { id: 'GW',     distanceMeters: 80,  enabled: false },
  { id: 'SW',     distanceMeters: 70,  enabled: true  },
  { id: 'LW',     distanceMeters: 55,  enabled: false },
  { id: 'Putter', distanceMeters: 0,   enabled: true  },
]

export const CLUB_GROUPS: Array<{ label: string; ids: string[] }> = [
  { label: 'Драйвер и вуды', ids: ['Driver', '3W', '5W'] },
  { label: 'Айроны',         ids: ['4i', '5i', '6i', '7i', '8i', '9i'] },
  { label: 'Вейджи',         ids: ['PW', 'GW', 'SW', 'LW'] },
  { label: 'Паттер',         ids: ['Putter'] },
]

// Normalize a user document into the canonical bag shape:
// - Prefer the new `bag` field
// - Fall back to legacy `clubs: string[]` by enabling only those ids in DEFAULT_BAG
// - Otherwise return the full DEFAULT_BAG
export function getBagFromUser(user: { bag?: BagClub[]; clubs?: string[] } | null | undefined): BagClub[] {
  if (user?.bag && user.bag.length > 0) return user.bag
  if (user?.clubs && user.clubs.length > 0) {
    const enabled = new Set(user.clubs)
    return DEFAULT_BAG.map(c => ({ ...c, enabled: enabled.has(c.id) }))
  }
  return DEFAULT_BAG
}

export function enabledBagClubs(bag: BagClub[]): BagClub[] {
  return bag.filter(c => c.enabled)
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
