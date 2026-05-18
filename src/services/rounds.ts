import {
  collection, doc, setDoc, updateDoc, getDoc,
  onSnapshot, query, where, orderBy, getDocs, serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import type { Round, HoleConfig, PlayerInfo } from '../types'
import { DEFAULT_HOLE_PARS } from '../types'

export function generateLobbyCode(): string {
  return Math.random().toString(36).substring(2, 8).toUpperCase()
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
  count: number,
  club: string,
): Promise<void> {
  const ref = doc(db, 'rounds', roundId)
  const snap = await getDoc(ref)
  const data = snap.data() as Omit<Round, 'id'>
  const holes = data.holes.map((h, i) =>
    i === holeIndex
      ? { ...h, shots: { ...h.shots, [userId]: { count, club, updatedAt: new Date() } } }
      : h,
  )
  await updateDoc(ref, { holes })
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
    if (snap.exists()) callback({ id: snap.id, ...snap.data() } as Round)
  })
}

export async function getUserRounds(userId: string): Promise<Round[]> {
  const q = query(
    collection(db, 'rounds'),
    where('hostId', '==', userId),
    orderBy('createdAt', 'desc'),
  )
  const snap = await getDocs(q)
  return snap.docs.map(d => ({ id: d.id, ...d.data() } as Round))
}
