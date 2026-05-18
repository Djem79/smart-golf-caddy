import {
  collection, doc, setDoc, updateDoc,
  onSnapshot, query, where, orderBy, getDocs, serverTimestamp,
  runTransaction, Timestamp,
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
): Promise<string> {
  const ref = doc(collection(db, 'rounds'))
  await setDoc(ref, {
    courseId,
    courseName,
    totalHoles,
    lobbyCode: generateLobbyCode(),
    status: 'active',
    hostId,
    players: { [hostId]: hostInfo },
    holes: buildDefaultHoles(totalHoles),
    startedAt: serverTimestamp(),
    finishedAt: null,
    createdAt: serverTimestamp(),
  })
  return ref.id
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
    where('hostId', '==', userId),
    orderBy('createdAt', 'desc'),
  )
  const snap = await getDocs(q)
  return snap.docs.map(d => normalizeRound(d.id, d.data()))
}
