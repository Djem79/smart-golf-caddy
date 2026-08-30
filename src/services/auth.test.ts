import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock Firebase BEFORE importing auth.ts (pattern from rounds.test.ts).
vi.mock('../firebase', () => ({
  auth: { __auth: true },
  db: { __db: true },
}))

// --- firebase/auth stub ------------------------------------------------
//
// Records provider construction + every popup/link/revoke call so tests can
// assert the exact sequence auth.ts drives, without a browser popup.
type ProviderRecord = { id: string; scopes: string[]; params: Record<string, string> }
// vi.hoisted: auth.ts constructs its GoogleAuthProvider at module load, and
// static imports are hoisted above plain `const`s — without this the mock
// constructor would hit these arrays in their temporal dead zone.
const { providers, calls } = vi.hoisted(() => ({
  providers: [] as { id: string; scopes: string[]; params: Record<string, string> }[],
  calls: [] as { fn: string; args: unknown[] }[],
}))

let popupImpl: (provider: ProviderRecord) => Promise<unknown> = async () => ({ user: fakeUser() })
let reauthImpl: () => Promise<unknown> = async () => ({})
let credentialFromResultImpl: (r: unknown) => { accessToken?: string } | null = () => ({ accessToken: 'apple-access' })
let credentialFromErrorImpl: (e: unknown) => unknown = () => ({ __pending: true })
let linkImpl: () => Promise<unknown> = async () => ({})

function fakeUser(over: Partial<{ uid: string; displayName: string | null; photoURL: string | null; providerData: { providerId: string }[] }> = {}) {
  return {
    uid: 'u1',
    displayName: 'Test User',
    photoURL: null,
    providerData: [{ providerId: 'google.com' }],
    ...over,
  }
}

vi.mock('firebase/auth', () => {
  class GoogleAuthProvider {
    record: ProviderRecord = { id: 'google.com', scopes: [], params: {} }
    constructor() { providers.push(this.record) }
  }
  class OAuthProvider {
    record: ProviderRecord
    constructor(id: string) {
      this.record = { id, scopes: [], params: {} }
      providers.push(this.record)
    }
    addScope(s: string) { this.record.scopes.push(s) }
    setCustomParameters(p: Record<string, string>) { this.record.params = { ...this.record.params, ...p } }
    static credentialFromResult(r: unknown) { return credentialFromResultImpl(r) }
    static credentialFromError(e: unknown) { return credentialFromErrorImpl(e) }
  }
  return {
    GoogleAuthProvider,
    OAuthProvider,
    signInWithPopup: vi.fn(async (_auth: unknown, provider: { record: ProviderRecord }) => {
      calls.push({ fn: 'signInWithPopup', args: [provider.record.id] })
      return popupImpl(provider.record)
    }),
    reauthenticateWithPopup: vi.fn(async (user: unknown, provider: { record: ProviderRecord }) => {
      calls.push({ fn: 'reauthenticateWithPopup', args: [user, provider.record.id] })
      return reauthImpl()
    }),
    linkWithCredential: vi.fn(async (user: unknown, cred: unknown) => {
      calls.push({ fn: 'linkWithCredential', args: [user, cred] })
      return linkImpl()
    }),
    revokeAccessToken: vi.fn(async (_auth: unknown, token: string) => {
      calls.push({ fn: 'revokeAccessToken', args: [token] })
    }),
    signOut: vi.fn(async () => {}),
    onAuthStateChanged: vi.fn(() => () => {}),
  }
})

// --- firebase/firestore stub ------------------------------------------
const profileExists = { value: false }
const setDocCalls: unknown[] = []
vi.mock('firebase/firestore', () => ({
  doc: vi.fn((_db: unknown, col: string, id: string) => ({ path: `${col}/${id}` })),
  getDoc: vi.fn(async () => ({ exists: () => profileExists.value })),
  setDoc: vi.fn(async (_ref: unknown, data: unknown) => { setDocCalls.push(data) }),
  serverTimestamp: vi.fn(() => 'SERVER_TS'),
}))

import {
  signInWithGoogle,
  signInWithApple,
  hasPendingAppleLink,
  isAppleLinked,
  revokeAppleAccess,
  isPopupCancelled,
  authErrorCode,
} from './auth'

function firebaseError(code: string): Error & { code: string } {
  return Object.assign(new Error(code), { code })
}

beforeEach(() => {
  vi.clearAllMocks()
  providers.length = 0
  calls.length = 0
  setDocCalls.length = 0
  profileExists.value = false
  popupImpl = async () => ({ user: fakeUser() })
  reauthImpl = async () => ({})
  credentialFromResultImpl = () => ({ accessToken: 'apple-access' })
  credentialFromErrorImpl = () => ({ __pending: true })
  linkImpl = async () => ({})
})

describe('signInWithApple', () => {
  it('opens the apple.com popup requesting email + name scopes, localized', async () => {
    await signInWithApple('ru')
    const apple = providers.find(p => p.id === 'apple.com')
    expect(apple).toBeDefined()
    expect(apple!.scopes).toEqual(['email', 'name'])
    expect(apple!.params).toEqual({ locale: 'ru' })
    expect(calls.map(c => c.fn)).toEqual(['signInWithPopup'])
  })

  it('creates the profile on first sign-in with the canonical bag shape', async () => {
    popupImpl = async () => ({ user: fakeUser({ displayName: 'Иван Иванов', photoURL: null }) })
    await signInWithApple('ru')
    expect(setDocCalls).toHaveLength(1)
    const data = setDocCalls[0] as Record<string, unknown>
    expect(data.name).toBe('Иван Иванов')
    expect(data.avatar).toBe('')
    expect(data.handicap).toBe(0)
    expect(Array.isArray(data.bag)).toBe(true)
    expect(data).not.toHaveProperty('clubs')
  })

  it('does NOT touch an existing profile — Apple sends the name only once, a repeat sign-in has none', async () => {
    profileExists.value = true
    popupImpl = async () => ({ user: fakeUser({ displayName: null }) })
    await signInWithApple('en')
    expect(setDocCalls).toHaveLength(0)
  })

  it('falls back to "Golfer" when Apple did not share a name and the profile is new', async () => {
    popupImpl = async () => ({ user: fakeUser({ displayName: null }) })
    await signInWithApple('en')
    expect((setDocCalls[0] as { name: string }).name).toBe('Golfer')
  })

  it('on account-exists-with-different-credential: keeps the pending Apple credential and rethrows', async () => {
    const err = firebaseError('auth/account-exists-with-different-credential')
    popupImpl = async () => { throw err }
    credentialFromErrorImpl = e => (e === err ? { __pending: 'apple-cred' } : null)

    await expect(signInWithApple('ru')).rejects.toBe(err)
    expect(hasPendingAppleLink()).toBe(true)
    expect(setDocCalls).toHaveLength(0)
  })

  it('other errors are rethrown without leaving a pending credential', async () => {
    popupImpl = async () => { throw firebaseError('auth/popup-closed-by-user') }
    await expect(signInWithApple('ru')).rejects.toMatchObject({ code: 'auth/popup-closed-by-user' })
    expect(hasPendingAppleLink()).toBe(false)
  })
})

describe('signInWithGoogle + pending Apple link', () => {
  it('links the pending Apple credential to the Google account after sign-in, then clears it', async () => {
    const err = firebaseError('auth/account-exists-with-different-credential')
    popupImpl = async () => { throw err }
    credentialFromErrorImpl = () => ({ __pending: 'apple-cred' })
    await signInWithApple('ru').catch(() => {})
    expect(hasPendingAppleLink()).toBe(true)

    const googleUser = fakeUser({ uid: 'g1' })
    popupImpl = async () => ({ user: googleUser })
    await signInWithGoogle()

    const link = calls.find(c => c.fn === 'linkWithCredential')
    expect(link).toBeDefined()
    expect(link!.args[0]).toBe(googleUser)
    expect(link!.args[1]).toEqual({ __pending: 'apple-cred' })
    expect(hasPendingAppleLink()).toBe(false)
  })

  it('a failed link does not fail the Google sign-in and still clears the pending credential', async () => {
    popupImpl = async () => { throw firebaseError('auth/account-exists-with-different-credential') }
    await signInWithApple('ru').catch(() => {})
    linkImpl = async () => { throw firebaseError('auth/credential-already-in-use') }
    popupImpl = async () => ({ user: fakeUser() })
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})

    await expect(signInWithGoogle()).resolves.toBeUndefined()
    expect(hasPendingAppleLink()).toBe(false)
    warn.mockRestore()
  })

  it('without a pending credential, Google sign-in never calls link', async () => {
    await signInWithGoogle()
    expect(calls.map(c => c.fn)).toEqual(['signInWithPopup'])
  })
})

describe('isAppleLinked', () => {
  it('is true only when apple.com is among providerData', () => {
    expect(isAppleLinked(fakeUser({ providerData: [{ providerId: 'google.com' }] }) as never)).toBe(false)
    expect(isAppleLinked(fakeUser({ providerData: [{ providerId: 'google.com' }, { providerId: 'apple.com' }] }) as never)).toBe(true)
    expect(isAppleLinked(fakeUser({ providerData: [] }) as never)).toBe(false)
  })
})

describe('revokeAppleAccess (TN3194 — required before account deletion)', () => {
  it('re-authenticates with Apple, then revokes the fresh access token', async () => {
    const user = fakeUser({ providerData: [{ providerId: 'apple.com' }] })
    await revokeAppleAccess(user as never)
    expect(calls.map(c => c.fn)).toEqual(['reauthenticateWithPopup', 'revokeAccessToken'])
    expect(calls[0].args[1]).toBe('apple.com')
    expect(calls[1].args[0]).toBe('apple-access')
  })

  it('throws (and does not call revoke) when the re-auth result carries no access token', async () => {
    credentialFromResultImpl = () => null
    await expect(revokeAppleAccess(fakeUser() as never)).rejects.toThrow()
    expect(calls.map(c => c.fn)).toEqual(['reauthenticateWithPopup'])
  })

  it('propagates a cancelled re-auth popup untouched so the caller can treat it as "not an error"', async () => {
    reauthImpl = async () => { throw firebaseError('auth/popup-closed-by-user') }
    await expect(revokeAppleAccess(fakeUser() as never)).rejects.toMatchObject({ code: 'auth/popup-closed-by-user' })
    expect(calls.map(c => c.fn)).toEqual(['reauthenticateWithPopup'])
  })
})

describe('error helpers', () => {
  it('authErrorCode reads Firebase `code`, empty for anything else', () => {
    expect(authErrorCode(firebaseError('auth/x'))).toBe('auth/x')
    expect(authErrorCode(new Error('plain'))).toBe('')
    expect(authErrorCode(null)).toBe('')
  })

  it('isPopupCancelled recognises the three user-abort codes only', () => {
    expect(isPopupCancelled(firebaseError('auth/popup-closed-by-user'))).toBe(true)
    expect(isPopupCancelled(firebaseError('auth/cancelled-popup-request'))).toBe(true)
    expect(isPopupCancelled(firebaseError('auth/user-cancelled'))).toBe(true)
    expect(isPopupCancelled(firebaseError('auth/popup-blocked'))).toBe(false)
    expect(isPopupCancelled(new Error('x'))).toBe(false)
  })
})
