import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock Firebase BEFORE importing users.ts — same pattern as rounds.test.ts.
vi.mock('../firebase', () => ({
  db: {},
  app: {},
}))

const setDocMock = vi.fn()
const docMock = vi.fn((...args) => ({ __doc: args }))

vi.mock('firebase/firestore', () => ({
  doc: (...args: unknown[]) => docMock(...args),
  setDoc: (...args: unknown[]) => setDocMock(...args),
  onSnapshot: vi.fn(),
}))

import { updateBag, updateUnits, updateLocale } from './users'

beforeEach(() => {
  vi.clearAllMocks()
})

describe('updateLocale', () => {
  it('writes { locale } to users/{uid} with merge: true', async () => {
    await updateLocale('u1', 'en')

    expect(docMock).toHaveBeenCalledWith({}, 'users', 'u1')
    expect(setDocMock).toHaveBeenCalledWith(
      { __doc: [{}, 'users', 'u1'] },
      { locale: 'en' },
      { merge: true },
    )
  })

  it('writes the other locale too', async () => {
    await updateLocale('u1', 'ru')
    expect(setDocMock).toHaveBeenCalledWith(expect.anything(), { locale: 'ru' }, { merge: true })
  })
})

// Sanity check that the existing sibling writers still merge the way the
// project rule (`setDoc(..., { merge: true })`) requires — not new coverage
// for T3, just guards `updateLocale` was added consistently.
describe('updateUnits / updateBag', () => {
  it('updateUnits merges { units }', async () => {
    await updateUnits('u1', 'yd')
    expect(setDocMock).toHaveBeenCalledWith(expect.anything(), { units: 'yd' }, { merge: true })
  })

  it('updateBag merges { bag }', async () => {
    await updateBag('u1', [])
    expect(setDocMock).toHaveBeenCalledWith(expect.anything(), { bag: [] }, { merge: true })
  })
})
