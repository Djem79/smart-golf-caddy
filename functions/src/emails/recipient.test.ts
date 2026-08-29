import { describe, expect, it } from 'vitest'
import { findRecipientUid } from './recipient'

const round = {
  players: {
    alice: { name: 'Alice', email: 'alice@example.com' },
    bob: { name: 'Bob', email: 'Bob@Example.com' },
  },
}

describe('findRecipientUid', () => {
  it('resolves to the caller when the target address is the caller\'s own auth email', () => {
    expect(findRecipientUid(round, 'alice', 'alice@example.com', 'alice@example.com')).toBe('alice')
  })

  it('resolves to a different participant when forwarding to their recorded email', () => {
    // alice (the caller/content owner) shares HER round summary to bob's inbox
    expect(findRecipientUid(round, 'alice', 'alice@example.com', 'bob@example.com')).toBe('bob')
  })

  it('is case-insensitive on both sides of the comparison', () => {
    expect(findRecipientUid(round, 'alice', 'ALICE@example.com', 'alice@EXAMPLE.com')).toBe('alice')
    expect(findRecipientUid(round, 'alice', 'alice@example.com', 'BOB@EXAMPLE.COM')).toBe('bob')
  })

  it('returns undefined when the address matches no known participant or the caller', () => {
    expect(findRecipientUid(round, 'alice', 'alice@example.com', 'stranger@example.com')).toBeUndefined()
  })
})
