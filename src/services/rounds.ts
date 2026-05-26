import {
  collection, doc, setDoc, updateDoc,
  onSnapshot, query, where, orderBy, limit, getDocs, serverTimestamp,
  Timestamp, arrayRemove,
} from 'firebase/firestore'
import { getFunctions, httpsCallable } from 'firebase/functions'
import { app, db } from '../firebase'
import type { Round, HoleConfig, PlayerInfo, TeeColor, PlayMode } from '../types'
import { DEFAULT_HOLE_PARS, TEE_MULTIPLIERS } from '../types'
import type {
  RecordShotInput,
  RecordShotResult,
  JoinLobbyInput,
  JoinLobbyResult,
  UpdateHoleConfigInput,
  UpdateHoleConfigResult,
} from '../types/callable'

const fns = getFunctions(app, 'us-central1')
const recordShotCallable = httpsCallable<RecordShotInput, RecordShotResult>(fns, 'recordShot')
const joinLobbyCallable = httpsCallable<JoinLobbyInput, JoinLobbyResult>(fns, 'joinLobbyByCode')
const updateHoleConfigCallable = httpsCallable<UpdateHoleConfigInput, UpdateHoleConfigResult>(
  fns,
  'updateHoleConfig',
)

const LOBBY_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // no 0/O/1/I for readability

function toDate(v: unknown): Date | null {
  if (v == null) return null
  if (v instanceof Timestamp) return v.toDate()
  if (v instanceof Date) return v
  if (typeof v === 'object' && v !== null && 'seconds' in v) {
    return new Date((v as { seconds: number }).seconds * 1000)
  }
  return null
}

function normalizeRound(id: string, data: Record<string, unknown>): Round {
  return {
    ...data,
    id,
    // `startedAt` is null for group rounds in lobby state; preserve that.
    // `createdAt` is set via serverTimestamp at create, so should always exist —
    // fall back to now only as last-resort defense.
    startedAt: toDate(data.startedAt),
    finishedAt: toDate(data.finishedAt),
    createdAt: toDate(data.createdAt) ?? new Date(),
  } as Round
}
export function generateLobbyCode(): string {
  let code = ''
  for (let i = 0; i < 6; i++) {
    code += LOBBY_CHARS[Math.floor(Math.random() * LOBBY_CHARS.length)]
  }
  return code
}

export function buildDefaultHoles(totalHoles: 9 | 18, tee: TeeColor = 'men'): HoleConfig[] {
  const mult = TEE_MULTIPLIERS[tee] ?? 1.0
  return DEFAULT_HOLE_PARS[totalHoles].map((par, i) => {
    const base = par === 3 ? 150 : par === 5 ? 480 : 360
    return {
      holeNumber: i + 1,
      par,
      distanceMeters: Math.round(base * mult),
      shots: {},
    }
  })
}

export async function createRound(
  hostId: string,
  hostInfo: PlayerInfo,
  courseId: string,
  courseName: string,
  totalHoles: 9 | 18,
  mode: 'solo' | 'group' = 'solo',
  tee: TeeColor = 'men',
  playMode: PlayMode = 'stroke',
): Promise<string> {
  // Match play only makes sense with at least 2 players — solo rounds always
  // fall back to stroke play even if the caller requested match.
  const effectivePlayMode: PlayMode = mode === 'group' ? playMode : 'stroke'

  const ref = doc(collection(db, 'rounds'))
  await setDoc(ref, {
    courseId,
    courseName,
    totalHoles,
    lobbyCode: generateLobbyCode(),
    status: mode === 'group' ? 'lobby' : 'active',
    hostId,
    players: { [hostId]: hostInfo },
    playerIds: [hostId],
    tee,
    playMode: effectivePlayMode,
    holes: buildDefaultHoles(totalHoles, tee),
    startedAt: mode === 'group' ? null : serverTimestamp(),
    finishedAt: null,
    createdAt: serverTimestamp(),
  })
  return ref.id
}

// Join an open lobby by 6-char code. Goes through a callable function so
// the client never needs `get` access to a lobby it hasn't joined — closes
// the lobby-PII leak (lobbyCode + players + emails) from the audit.
// `userId` is kept in the signature for callsite stability but must match
// the calling user's auth uid (the callable infers from request.auth).
export async function joinRoundByCode(
  code: string,
  _userId: string,
  playerInfo: PlayerInfo,
): Promise<string | null> {
  const trimmed = code.trim().toUpperCase()
  if (trimmed.length === 0) return null
  const res = await joinLobbyCallable({ code: trimmed, playerInfo })
  return res.data.roundId
}

export async function leaveLobby(roundId: string, userId: string): Promise<void> {
  // Note: deleting a nested map key requires `FieldValue.delete()`. We just
  // remove from playerIds and leave the player info as a tombstone. For MVP
  // this is OK; the lobby UI filters by playerIds for membership.
  await updateDoc(doc(db, 'rounds', roundId), {
    playerIds: arrayRemove(userId),
  })
}

export async function startRound(roundId: string): Promise<void> {
  await updateDoc(doc(db, 'rounds', roundId), {
    status: 'active',
    startedAt: serverTimestamp(),
  })
}

// Records a player's shots through a server-authoritative callable.
// Clients are no longer permitted to write `holes` directly (rules block it)
// because client transactions could rewrite ANY player's shots. `userId` is
// the slot being scored: it must equal the caller's auth uid, OR the caller
// must be the round host (host keeps score for the whole group). The callable
// enforces this server-side and rejects otherwise with permission-denied.
export async function recordShot(
  roundId: string,
  holeIndex: number,
  userId: string,
  clubs: string[],
): Promise<void> {
  await recordShotCallable({ roundId, holeIndex, clubs, targetUid: userId })
}

export async function finishRound(roundId: string): Promise<void> {
  await updateDoc(doc(db, 'rounds', roundId), {
    status: 'finished',
    finishedAt: serverTimestamp(),
  })
}

export function subscribeToRound(
  roundId: string,
  callback: (round: Round) => void,
  onError?: (err: Error) => void,
): () => void {
  // The error callback is essential: without it a permission/network failure
  // on the listener is swallowed and the screen spins forever. Surfacing it
  // lets the UI show a retry instead of an endless "Загрузка...".
  return onSnapshot(
    doc(db, 'rounds', roundId),
    (snap) => {
      if (snap.exists()) callback(normalizeRound(snap.id, snap.data()))
    },
    (err) => onError?.(err),
  )
}

// Host-only: change the par and/or distance for a single hole. At least
// one field must be provided. Server-side enforces the host check, value
// ranges, and preserves shots.
export async function updateHoleConfig(
  roundId: string,
  holeIndex: number,
  patch: { par?: 3 | 4 | 5; distanceMeters?: number },
): Promise<void> {
  await updateHoleConfigCallable({ roundId, holeIndex, ...patch })
}

// Fetches the user's rounds, newest first. Capped to `limitTo` (default 50)
// so the read cost doesn't grow unbounded with play history — History/Profile
// only need recent activity for stats and the timeline.
export async function getUserRounds(userId: string, limitTo = 50): Promise<Round[]> {
  const q = query(
    collection(db, 'rounds'),
    where('playerIds', 'array-contains', userId),
    orderBy('createdAt', 'desc'),
    limit(limitTo),
  )
  const snap = await getDocs(q)
  return snap.docs.map(d => normalizeRound(d.id, d.data()))
}
