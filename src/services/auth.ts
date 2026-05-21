import {
  GoogleAuthProvider,
  signInWithPopup,
  signOut as fbSignOut,
  onAuthStateChanged,
} from 'firebase/auth'
import type { User } from 'firebase/auth'
import { doc, setDoc, getDoc, serverTimestamp } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { AppUser, DEFAULT_BAG } from '../types'

// Re-export the Firebase user type through the service layer so consumers
// (e.g. useAuth) don't import `firebase/auth` directly — keeping services/ the
// only layer that touches firebase/* per the architecture rule.
export type AuthUser = User

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
      // Write the canonical `bag` shape (not legacy `clubs`) so new profiles
      // start on the current schema. getBagFromUser still backfills old docs.
      bag: DEFAULT_BAG,
      createdAt: serverTimestamp(),
    })
  }
}

export async function signOut(): Promise<void> {
  await fbSignOut(auth)
}

// Subscribe to auth-state changes. The sole owner of the firebase/auth
// listener — useAuth consumes this instead of importing firebase directly.
export function subscribeToAuth(callback: (user: AuthUser | null) => void): () => void {
  return onAuthStateChanged(auth, callback)
}

export async function getUserProfile(uid: string): Promise<AppUser | null> {
  const snap = await getDoc(doc(db, 'users', uid))
  if (!snap.exists()) return null
  return { uid, ...snap.data() } as AppUser
}
