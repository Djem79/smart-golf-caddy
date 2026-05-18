import {
  collection, doc, setDoc, updateDoc,
  onSnapshot, query, where, orderBy, getDocs, serverTimestamp,
  runTransaction, Timestamp, arrayUnion, arrayRemove,
} from 'firebase/firestore'
import { db } from '../firebase'
import type { Round, HoleConfig, PlayerInfo } from '../types'
import { DEFAULT_HOLE_PARS } from '../types'

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
    startedAt: toDate(data.startedAt) ?? new Date(),
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

export function buildDefaultHoles(totalHoles: 9 | 18): HoleConfig[] {
  return DEFAULT_HOLE_PARS[totalHoles].map((par, i) => ({
    holeNumber: i + 1,
    par,
    distanceMeters: par === 3 ? 150 : par === 5 ? 480 : 360,
    shots: {},
  }))
}

export async function createRound(
  hostId: string,
  hostInfo: PlayerInfo,
  courseId: string,
  courseName: string,
  totalHoles: 9 | 18,
  mode: 'solo' | 'group' = 'solo',
): Promise<string> {
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
    holes: buildDefaultHoles(totalHoles),
    startedAt: mode === 'group' ? null : serverTimestamp(),
    finishedAt: null,
    createdAt: serverTimestamp(),
  })
  return ref.id
}

// Find an open lobby by code and add the joining user to its players map.
// Returns the round id if successful; null if no matching lobby was found.
export async function joinRoundByCode(
  code: string,
  userId: string,
  playerInfo: PlayerInfo,
): Promise<string | null> {
  const trimmed = code.trim().toUpperCase()
  if (trimmed.length === 0) return null

  const q = query(
    collection(db, 'rounds'),
    where('lobbyCode', '==', trimmed),
    where('status', '==', 'lobby'),
  )
  const snap = await getDocs(q)
  if (snap.empty) return null

  const docSnap = snap.docs[0]
  await updateDoc(doc(db, 'rounds', docSnap.id), {
    [`players.${userId}`]: playerInfo,
    playerIds: arrayUnion(userId),
  })
  return docSnap.id
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

export async function recordShot(
  roundId: string,
  holeIndex: number,
  userId: string,
  clubs: string[],
): Promise<void> {
  const ref = doc(db, 'rounds', roundId)
  await runTransaction(db, async (tx) => {
    const snap = await tx.get(ref)
    if (!snap.exists()) throw new Error('Round not found')
    const data = snap.data() as Omit<Round, 'id'>
    const holes = data.holes.map((h, i) =>
      i === holeIndex
        ? {
            ...h,
            shots: {
              ...h.shots,
              [userId]: {
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
): () => void {
  return onSnapshot(doc(db, 'rounds', roundId), (snap) => {
    if (snap.exists()) callback(normalizeRound(snap.id, snap.data()))
  })
}

export async function getUserRounds(userId: string): Promise<Round[]> {
  const q = query(
    collection(db, 'rounds'),
    where('playerIds', 'array-contains', userId),
    orderBy('createdAt', 'desc'),
  )
  const snap = await getDocs(q)
  return snap.docs.map(d => normalizeRound(d.id, d.data()))
}
