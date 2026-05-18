export interface AppUser {
  uid: string
  name: string
  avatar: string
  handicap: number
  clubs: string[]
}

export interface HoleShots {
  count: number
  club: string
  updatedAt: Date
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
