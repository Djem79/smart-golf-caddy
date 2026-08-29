import { describe, expect, it } from 'vitest'
import { buildPayload, buildSubject, DELETED_PLAYER_MARKER, type RoundLike } from './buildPayload'

// The literal deleteAccount() wrote before DELETED_PLAYER_MARKER existed.
// Real, already-anonymised rounds in Firestore still carry this exact
// string — buildPayload must keep translating it forever, never migrated.
const LEGACY_DELETED_PLAYER_NAME_RU = 'Удалённый игрок'

// Two active, distinctly-named players finish a stroke-play round together.
// Used to prove buildPayload renders EACH recipient independently — the
// key requirement from the T6 spec ("группа может состоять из игроков с
// разными языками — рендер выполняется отдельно на каждого получателя").
function makeStrokeRound(): RoundLike {
  return {
    id: 'round-1',
    courseName: 'Pebble Beach',
    totalHoles: 2,
    playerIds: ['alice', 'carol'],
    playMode: 'stroke',
    players: {
      alice: { name: 'Alice', email: 'alice@example.com' },
      carol: { name: 'Carol', email: 'carol@example.com' },
    },
    holes: [
      {
        holeNumber: 1,
        par: 4,
        shots: {
          // alice: +1 on this hole, carol: +1 too
          alice: { count: 5, clubs: ['Driver', '7i', '7i', 'PW', 'PT'] },
          carol: { count: 5, clubs: ['Driver', '7i', '7i', 'PW', 'PT'] },
        },
      },
      {
        holeNumber: 2,
        par: 3,
        shots: {
          // alice: even, carol: +1 → alice totals +1, carol totals +2
          alice: { count: 3, clubs: ['7i', 'PW', 'PT'] },
          carol: { count: 4, clubs: ['7i', 'PW', 'PW', 'PT'] },
        },
      },
    ],
    finishedAt: new Date('2026-05-19T12:00:00Z'),
  }
}

// A match-play round where the departed player (bob) has already been
// anonymised by deleteAccount() — his stored name is whichever marker the
// caller supplies, and he's the match leader, so his name flows into
// match.leaderName. `deletedName` defaults to the current
// DELETED_PLAYER_MARKER (new anonymisations) but tests also pass the old
// LEGACY_DELETED_PLAYER_NAME_RU literal to prove rounds anonymised before
// the marker existed still render correctly — that data is never migrated.
function makeMatchRoundWithDeletedLeader(deletedName: string = DELETED_PLAYER_MARKER): RoundLike {
  return {
    id: 'round-2',
    courseName: 'Augusta National',
    totalHoles: 2,
    playerIds: ['alice', 'bob'],
    playMode: 'match',
    players: {
      alice: { name: 'Alice', email: 'alice@example.com' },
      bob: { name: deletedName },
    },
    holes: [
      {
        holeNumber: 1,
        par: 4,
        shots: {
          alice: { count: 5, clubs: ['Driver', '7i', '7i', 'PW', 'PT'] },
          bob: { count: 3, clubs: ['Driver', 'PW', 'PT'] },
        },
      },
      {
        holeNumber: 2,
        par: 3,
        shots: {
          alice: { count: 4, clubs: ['7i', 'PW', 'PW', 'PT'] },
          bob: { count: 3, clubs: ['7i', 'PW', 'PT'] },
        },
      },
    ],
    finishedAt: new Date('2026-05-19T12:00:00Z'),
  }
}

describe('buildPayload — per-recipient locale', () => {
  it('renders two recipients of the same round independently, each in their own locale', () => {
    const round = makeStrokeRound()

    const aliceRu = buildPayload(round, 'alice', undefined, 'ru')
    const carolEn = buildPayload(round, 'carol', undefined, 'en')

    expect(aliceRu.playerName).toBe('Alice')
    expect(carolEn.playerName).toBe('Carol')
    // Same underlying date, formatted per-recipient — proves the render
    // isn't shared/cached across recipients in the same round.
    expect(aliceRu.dateLabel).toMatch(/мая/)
    expect(carolEn.dateLabel).toMatch(/May/)
    expect(aliceRu.dateLabel).not.toBe(carolEn.dateLabel)
  })

  it('formats the same date differently per locale for the same recipient', () => {
    const round = makeStrokeRound()
    const ru = buildPayload(round, 'alice', undefined, 'ru')
    const en = buildPayload(round, 'alice', undefined, 'en')
    expect(ru.dateLabel).toBe('19 мая 2026')
    expect(en.dateLabel).toBe('19 May 2026')
  })

  it('falls back to the localized generic player name when a name is entirely missing', () => {
    const round = makeStrokeRound()
    round.players.alice = { email: 'alice@example.com' } as unknown as { name: string; email?: string }
    expect(buildPayload(round, 'alice', undefined, 'ru').playerName).toBe('Игрок')
    expect(buildPayload(round, 'alice', undefined, 'en').playerName).toBe('Player')
  })
})

describe('buildPayload — deleted-player name', () => {
  it('translates the deleted-player marker in match.leaderName for a Russian recipient', () => {
    const round = makeMatchRoundWithDeletedLeader()
    const payload = buildPayload(round, 'alice', undefined, 'ru')
    expect(payload.match?.leaderName).toBe('Удалённый игрок')
  })

  it('translates the SAME stored marker into English for an English recipient', () => {
    const round = makeMatchRoundWithDeletedLeader()
    const payload = buildPayload(round, 'alice', undefined, 'en')
    expect(payload.match?.leaderName).toBe('Removed player')
  })

  it('translates the legacy Russian literal in match.leaderName for a Russian recipient — proves rounds anonymised before the marker existed still render correctly', () => {
    const round = makeMatchRoundWithDeletedLeader(LEGACY_DELETED_PLAYER_NAME_RU)
    const payload = buildPayload(round, 'alice', undefined, 'ru')
    expect(payload.match?.leaderName).toBe('Удалённый игрок')
  })

  it('translates the legacy Russian literal into English for an English recipient — old/existing anonymised data is never migrated, so this must keep working indefinitely', () => {
    const round = makeMatchRoundWithDeletedLeader(LEGACY_DELETED_PLAYER_NAME_RU)
    const payload = buildPayload(round, 'alice', undefined, 'en')
    expect(payload.match?.leaderName).toBe('Removed player')
  })

  it('leaves an ordinary (non-deleted) name untouched in both locales', () => {
    const round = makeMatchRoundWithDeletedLeader()
    // Flip the round so alice — a normal, non-deleted player — is the leader.
    round.holes[0].shots.alice = { count: 3, clubs: ['Driver', 'PW', 'PT'] }
    round.holes[0].shots.bob = { count: 5, clubs: ['Driver', '7i', '7i', 'PW', 'PT'] }
    round.holes[1].shots.alice = { count: 3, clubs: ['7i', 'PW', 'PT'] }
    round.holes[1].shots.bob = { count: 4, clubs: ['7i', 'PW', 'PW', 'PT'] }
    const ru = buildPayload(round, 'bob', undefined, 'ru')
    const en = buildPayload(round, 'bob', undefined, 'en')
    expect(ru.match?.leaderName).toBe('Alice')
    expect(en.match?.leaderName).toBe('Alice')
  })
})

describe('buildSubject', () => {
  it('localizes the subject prefix per locale while keeping course/score data identical', () => {
    const round = makeStrokeRound()
    const payload = buildPayload(round, 'alice', undefined, 'ru')
    const ruSubject = buildSubject(payload, 'ru')
    const enSubject = buildSubject(payload, 'en')
    expect(ruSubject).toBe('Итоги раунда: Pebble Beach — 8 (+1)')
    expect(enSubject).toBe('Round summary: Pebble Beach — 8 (+1)')
  })

  it('uses the even-par "(E)" notation unlocalized in both languages', () => {
    const round = makeStrokeRound()
    // alice: hole1 par4/score4 (=par), hole2 par3/score3 (=par) → diff 0
    round.holes[0].shots.alice = { count: 4, clubs: ['Driver', '7i', 'PW', 'PT'] }
    round.holes[1].shots.alice = { count: 3, clubs: ['7i', 'PW', 'PT'] }
    const payload = buildPayload(round, 'alice', undefined, 'ru')
    expect(buildSubject(payload, 'ru')).toContain('(E)')
    expect(buildSubject(payload, 'en')).toContain('(E)')
  })
})
