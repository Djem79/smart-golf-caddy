import { GoogleAuthProvider, signInWithPopup, signOut as fbSignOut } from 'firebase/auth'
import { doc, setDoc, getDoc, serverTimestamp } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { AppUser, DEFAULT_CLUBS } from '../types'

const googleProvider = new GoogleAuthProvider()

export async function signInWithGoogle(): Promise<void> {
  const { user } = await signInWithPopup(auth, googleProvider)
  const ref = doc(db, 'users', user.uid)
  const snap = await getDoc(ref)
  if (!snap.exists()) {
    await setDoc(ref, {
      name: user.displayName ?? 'Golfer',
      avatar: user.photoURL ?? '',
      handicap: 0,
      clubs: DEFAULT_CLUBS,
      createdAt: serverTimestamp(),
    })
  }
}

export async function signOut(): Promise<void> {
  await fbSignOut(auth)
}

export async function getUserProfile(uid: string): Promise<AppUser | null> {
  const snap = await getDoc(doc(db, 'users', uid))
  if (!snap.exists()) return null
  return { uid, ...snap.data() } as AppUser
}
