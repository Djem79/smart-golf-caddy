import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// Mock the rounds module so we don't pull in firebase, and can drive the
// callable's success/failure per test.
const recordShotMock = vi.fn<(r: string, h: number, u: string, c: string[]) => Promise<void>>()
vi.mock('./rounds', () => ({
  recordShot: (r: string, h: number, u: string, c: string[]) => recordShotMock(r, h, u, c),
}))

import {
  enqueueShot,
  getPendingShot,
  pendingCountForRound,
  recordShotQueued,
  flushQueue,
} from './shotQueue'

function setOnline(value: boolean) {
  Object.defineProperty(navigator, 'onLine', { value, configurable: true })
}

beforeEach(() => {
  localStorage.clear()
  recordShotMock.mockReset()
  recordShotMock.mockResolvedValue(undefined)
  setOnline(true)
})

afterEach(() => {
  setOnline(true)
})

describe('queue basics', () => {
  it('enqueues and reads back a pending shot', () => {
    enqueueShot({ roundId: 'r1', holeIndex: 3, targetUid: 'u1', clubs: ['Driver'] })
    expect(getPendingShot('r1', 3, 'u1')?.clubs).toEqual(['Driver'])
    expect(pendingCountForRound('r1')).toBe(1)
  })

  it('replaces the same slot (last-write-wins), not append', () => {
    enqueueShot({ roundId: 'r1', holeIndex: 3, targetUid: 'u1', clubs: ['Driver'] })
    enqueueShot({ roundId: 'r1', holeIndex: 3, targetUid: 'u1', clubs: ['Driver', '7i'] })
    expect(getPendingShot('r1', 3, 'u1')?.clubs).toEqual(['Driver', '7i'])
    expect(pendingCountForRound('r1')).toBe(1)
  })
})

describe('recordShotQueued', () => {
  it('sends and clears the queue when online and successful', async () => {
    const res = await recordShotQueued('r1', 0, 'u1', ['Driver'])
    expect(res.synced).toBe(true)
    expect(recordShotMock).toHaveBeenCalledWith('r1', 0, 'u1', ['Driver'])
    expect(getPendingShot('r1', 0, 'u1')).toBeUndefined()
  })

  it('keeps the shot queued and does not call the callable when offline', async () => {
    setOnline(false)
    const res = await recordShotQueued('r1', 0, 'u1', ['Driver'])
    expect(res.synced).toBe(false)
    expect(recordShotMock).not.toHaveBeenCalled()
    expect(getPendingShot('r1', 0, 'u1')?.clubs).toEqual(['Driver'])
  })

  it('keeps the shot queued on a transient error', async () => {
    recordShotMock.mockRejectedValueOnce(Object.assign(new Error('down'), { code: 'unavailable' }))
    const res = await recordShotQueued('r1', 0, 'u1', ['Driver'])
    expect(res.synced).toBe(false)
    expect(getPendingShot('r1', 0, 'u1')?.clubs).toEqual(['Driver'])
  })

  it('throws and drops the shot on a permanent rejection', async () => {
    recordShotMock.mockRejectedValueOnce(
      Object.assign(new Error('nope'), { code: 'functions/permission-denied' }),
    )
    await expect(recordShotQueued('r1', 0, 'u1', ['Driver'])).rejects.toThrow()
    expect(getPendingShot('r1', 0, 'u1')).toBeUndefined()
  })
})

describe('flushQueue', () => {
  it('flushes every queued shot when back online', async () => {
    setOnline(false)
    await recordShotQueued('r1', 0, 'u1', ['Driver'])
    await recordShotQueued('r1', 1, 'u1', ['3W'])
    expect(pendingCountForRound('r1')).toBe(2)

    setOnline(true)
    const { remaining } = await flushQueue()
    expect(remaining).toBe(0)
    expect(recordShotMock).toHaveBeenCalledTimes(2)
  })

  it('stops on a transient failure and leaves the rest queued', async () => {
    enqueueShot({ roundId: 'r1', holeIndex: 0, targetUid: 'u1', clubs: ['Driver'] })
    enqueueShot({ roundId: 'r1', holeIndex: 1, targetUid: 'u1', clubs: ['3W'] })
    recordShotMock
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(Object.assign(new Error('down'), { code: 'unavailable' }))
    const { remaining } = await flushQueue()
    expect(remaining).toBe(1)
  })
})
