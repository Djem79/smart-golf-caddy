import {
  GoogleAuthProvider,
  OAuthProvider,
  signInWithPopup,
  signOut as fbSignOut,
  onAuthStateChanged,
  linkWithCredential,
  reauthenticateWithPopup,
  revokeAccessToken,
} from 'firebase/auth'
import type { User, AuthCredential } from 'firebase/auth'
import type { FirebaseError } from 'firebase/app'
import { doc, setDoc, getDoc, serverTimestamp } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { AppUser, DEFAULT_BAG } from '../types'

// Re-export the Firebase user type through the service layer so consumers
// (e.g. useAuth) don't import `firebase/auth` directly — keeping services/ the
// only layer that touches firebase/* per the architecture rule.
export type AuthUser = User

export const APPLE_PROVIDER_ID = 'apple.com'

const googleProvider = new GoogleAuthProvider()

// Sign in with Apple (App Store 4.8 — mandatory privacy-preserving
// alternative once Google Sign-In is offered). Mirrors
// ios/SmartGolfCaddy/Services/AuthService.swift; the web SDK handles the
// nonce itself inside signInWithPopup, so unlike iOS there is no manual
// SHA-256 dance here. `locale` localizes Apple's consent screen — passed in
// by the caller because services/ must not depend on the i18n layer.
function makeAppleProvider(locale?: string): OAuthProvider {
  const provider = new OAuthProvider(APPLE_PROVIDER_ID)
  provider.addScope('email')
  provider.addScope('name')
  if (locale) provider.setCustomParameters({ locale })
  return provider
}

// Creates users/{uid} exactly once. Apple shares the display name ONLY on
// the very first authorization — a repeat sign-in yields displayName=null —
// so "write once, never overwrite" is what keeps the saved name from being
// clobbered by an empty value later. Same rule already covered Google.
async function ensureProfile(user: User): Promise<void> {
  const ref = doc(db, 'users', user.uid)
  const snap = await getDoc(ref)
  if (snap.exists()) return
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

// --- Account linking -------------------------------------------------------
//
// Firebase runs "one account per email". If the Apple email is already
// registered via Google, signInWithPopup rejects with
// `auth/account-exists-with-different-credential` and hands back the Apple
// credential it could not use. Firebase's documented recovery: have the
// user sign in with the EXISTING provider, then link the pending credential
// to that account. Kept in module scope (not persisted) — it is only valid
// for the current page session, and a reload simply asks the user to try
// again. Silently merging by email is deliberately NOT done: Apple requires
// explicit consent before its account is tied to other data, and the
// message shown on the Auth screen is that consent.
let pendingAppleCredential: AuthCredential | null = null

export function hasPendingAppleLink(): boolean {
  return pendingAppleCredential !== null
}

async function linkPendingApple(user: User): Promise<void> {
  const credential = pendingAppleCredential
  if (!credential) return
  pendingAppleCredential = null
  try {
    await linkWithCredential(user, credential)
  } catch (e) {
    // Non-fatal: the user is signed in either way. Linking can legitimately
    // fail (credential expired, already linked elsewhere) — they can retry
    // Apple sign-in later, which raises the same error and a fresh credential.
    console.warn('[Auth] linking pending Apple credential failed:', e)
  }
}

export async function signInWithGoogle(): Promise<void> {
  const { user } = await signInWithPopup(auth, googleProvider)
  await ensureProfile(user)
  await linkPendingApple(user)
}

export async function signInWithApple(locale?: string): Promise<void> {
  // A new attempt supersedes whatever an earlier one left behind: either
  // this one succeeds (nothing to link) or it raises a fresh credential.
  pendingAppleCredential = null
  let user: User
  try {
    ;({ user } = await signInWithPopup(auth, makeAppleProvider(locale)))
  } catch (e) {
    if (authErrorCode(e) === 'auth/account-exists-with-different-credential') {
      pendingAppleCredential = OAuthProvider.credentialFromError(e as FirebaseError)
    }
    throw e
  }
  await ensureProfile(user)
}

// --- Token revocation (Apple TN3194) ---------------------------------------
//
// Apple requires apps to revoke the Sign in with Apple token when the user
// deletes their account. Firebase does the actual `appleid.apple.com/auth/
// revoke` call on its backend (using the Apple key configured in the
// console's "OAuth code flow configuration") — the client only needs a
// FRESH Apple access token, which is why this re-authenticates first. The
// token from the original sign-in is long gone by deletion time. Caller
// (Profile) runs this BEFORE the `deleteAccount` callable, and only for
// users whose account is actually linked to Apple.
export function isAppleLinked(user: User): boolean {
  return user.providerData.some(p => p.providerId === APPLE_PROVIDER_ID)
}

export async function revokeAppleAccess(user: User): Promise<void> {
  const result = await reauthenticateWithPopup(user, makeAppleProvider())
  const token = OAuthProvider.credentialFromResult(result)?.accessToken
  if (!token) throw new Error('Apple re-authentication returned no access token')
  await revokeAccessToken(auth, token)
}

// --- Error helpers ---------------------------------------------------------

// Firebase Auth errors carry a stable `code` (`auth/...`); anything else
// (network layer, our own throws) yields '' so callers fall through to the
// generic branch.
export function authErrorCode(e: unknown): string {
  if (e && typeof e === 'object' && 'code' in e) return String((e as { code: unknown }).code)
  return ''
}

// The user closed/abandoned the provider popup on their own — not an error
// to show. `user-cancelled` is the provider-side "denied consent" variant.
export function isPopupCancelled(e: unknown): boolean {
  const code = authErrorCode(e)
  return (
    code === 'auth/popup-closed-by-user' ||
    code === 'auth/cancelled-popup-request' ||
    code === 'auth/user-cancelled'
  )
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
