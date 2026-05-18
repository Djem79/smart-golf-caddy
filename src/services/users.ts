import { doc, setDoc, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import type { AppUser, BagClub, DistanceUnit } from '../types'

export async function updateBag(uid: string, bag: BagClub[]): Promise<void> {
  await setDoc(doc(db, 'users', uid), { bag }, { merge: true })
}

export async function updateUnits(uid: string, units: DistanceUnit): Promise<void> {
  await setDoc(doc(db, 'users', uid), { units }, { merge: true })
}

export function subscribeToProfile(
  uid: string,
  callback: (profile: AppUser | null) => void,
): () => void {
  return onSnapshot(doc(db, 'users', uid), (snap) => {
    if (!snap.exists()) {
      callback(null)
      return
    }
    callback({ uid, ...snap.data() } as AppUser)
  })
}
