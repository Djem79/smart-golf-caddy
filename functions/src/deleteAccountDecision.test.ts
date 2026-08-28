import { describe, expect, it } from 'vitest'
import { decideRoundDeletion } from './deleteAccountDecision'

describe('decideRoundDeletion', () => {
  it('deletes a solo round outright', () => {
    const decision = decideRoundDeletion({ playerIds: ['u1'], hostId: 'u1', uid: 'u1' })
    expect(decision).toEqual({ action: 'delete' })
  })

  it('anonymises a group round and hands the host role to the first remaining player when the deleted user was host', () => {
    const decision = decideRoundDeletion({
      playerIds: ['u1', 'u2', 'u3'],
      hostId: 'u1',
      uid: 'u1',
    })
    expect(decision).toEqual({ action: 'anonymize', newHostId: 'u2' })
  })

  it('anonymises without touching hostId when the deleted user is a regular (non-host) player', () => {
    const decision = decideRoundDeletion({
      playerIds: ['u1', 'u2'],
      hostId: 'u1',
      uid: 'u2',
    })
    expect(decision).toEqual({ action: 'anonymize' })
    expect(decision).not.toHaveProperty('newHostId')
  })

  it('hands the host role to the sole other player when the deleted host leaves a 2-player round', () => {
    const decision = decideRoundDeletion({
      playerIds: ['u1', 'u2'],
      hostId: 'u1',
      uid: 'u1',
    })
    expect(decision).toEqual({ action: 'anonymize', newHostId: 'u2' })
  })

  it('ignores duplicate uid entries when picking the next host', () => {
    const decision = decideRoundDeletion({
      playerIds: ['u1', 'u1', 'u2'],
      hostId: 'u1',
      uid: 'u1',
    })
    expect(decision).toEqual({ action: 'anonymize', newHostId: 'u2' })
  })

  it('deletes a round whose playerIds are only duplicate entries of the deleted uid', () => {
    const decision = decideRoundDeletion({
      playerIds: ['u1', 'u1'],
      hostId: 'u1',
      uid: 'u1',
    })
    expect(decision).toEqual({ action: 'delete' })
  })
})
