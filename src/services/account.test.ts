import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock Firebase BEFORE importing account.ts so the imports resolve in test env.
vi.mock('../firebase', () => ({
  app: {},
}))

// `deleteAccount` delegates to the `deleteAccount` Cloud Function callable.
// Mock the dispatcher so tests can assert the right name + payload were
// sent, without spinning up an emulator — same pattern as rounds.test.ts.
type CallableCall = { name: string; payload: unknown }
const callableCalls: CallableCall[] = []
const callableResponses = new Map<string, unknown>()
let nextRejection: Error | null = null

vi.mock('firebase/functions', () => ({
  getFunctions: vi.fn(() => ({ __functions: true })),
  httpsCallable: (_fns: unknown, name: string) =>
    async (payload: unknown) => {
      callableCalls.push({ name, payload })
      if (nextRejection) {
        const err = nextRejection
        nextRejection = null
        throw err
      }
      const response = callableResponses.get(name)
      return { data: response ?? { ok: true } }
    },
}))

import { deleteAccount } from './account'

beforeEach(() => {
  vi.clearAllMocks()
  callableCalls.length = 0
  callableResponses.clear()
  nextRejection = null
})

describe('deleteAccount', () => {
  it('calls the deleteAccount callable with an empty payload', async () => {
    await deleteAccount()
    expect(callableCalls).toHaveLength(1)
    expect(callableCalls[0].name).toBe('deleteAccount')
    expect(callableCalls[0].payload).toEqual({})
  })

  it('resolves when the callable succeeds', async () => {
    callableResponses.set('deleteAccount', { ok: true })
    await expect(deleteAccount()).resolves.toBeUndefined()
  })

  it('propagates the callable error to the caller instead of swallowing it', async () => {
    nextRejection = new Error('internal')
    await expect(deleteAccount()).rejects.toThrow('internal')
  })
})
