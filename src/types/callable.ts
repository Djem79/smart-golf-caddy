// Callable input/output types — client-side mirror of the Zod schemas
// defined server-side in `functions/src/contracts.ts`.
//
// SYNC: keep these in lockstep with the server schemas. The server is
// authoritative — these types just give the client compile-time safety so
// services/* can't accidentally send a payload shape that gets rejected as
// `invalid-argument`. We hand-mirror instead of importing zod into the web
// bundle because zod adds ~50 KB minified and these payloads are small
// enough that the server's safeParse is sufficient validation.

// recordShot
export interface RecordShotInput {
  roundId: string
  holeIndex: number
  clubs: string[]
  targetUid?: string
}
export interface RecordShotResult {
  ok: boolean
}

// updateHoleConfig
export interface UpdateHoleConfigInput {
  roundId: string
  holeIndex: number
  par?: 3 | 4 | 5
  distanceMeters?: number
}
export interface UpdateHoleConfigResult {
  ok: boolean
}

// joinLobbyByCode
export interface JoinLobbyPlayerInfo {
  name?: string
  avatar?: string
  email?: string
  totalScore?: number
  scoreDiff?: number
}
export interface JoinLobbyInput {
  code: string
  playerInfo?: JoinLobbyPlayerInfo
}
export interface JoinLobbyResult {
  roundId: string | null
}

// shareRoundByEmail
export interface ShareInput {
  roundId: string
  toEmail: string
}
export interface ShareResult {
  ok: boolean
}
