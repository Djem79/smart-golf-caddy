import { describe, expect, it } from 'vitest'
import { render } from '@react-email/render'
import * as React from 'react'
import { RoundSummary } from './RoundSummary'
import type { RoundSummaryPayload } from './types'

// Minimal but complete payload — every field RoundSummary reads.
function makePayload(overrides: Partial<RoundSummaryPayload> = {}): RoundSummaryPayload {
  return {
    playerName: 'Alice',
    courseName: 'Pebble Beach',
    dateLabel: '19 мая 2026',
    totalHoles: 9,
    holesPlayedByMe: 9,
    totalScore: 40,
    totalPar: 36,
    scoreDiff: 4,
    bestHole: { hole: 3, par: 4, score: 3, diff: -1, category: 'birdie' },
    scorecard: Array.from({ length: 9 }, (_, i) => ({
      hole: i + 1,
      par: 4,
      score: 4,
      diff: 0,
      category: 'par' as const,
    })),
    topClubs: [{ club: 'Driver', count: 5, percent: 50 }],
    match: null,
    resultsUrl: 'https://smart-golf-caddy.web.app/round/r1/results',
    ...overrides,
  }
}

// react-email's static-markup renderer inserts `<!-- -->` hydration-boundary
// comments between adjacent JSX expression children (e.g. `{n} {word}`
// renders as `1<!-- --> <!-- -->лунка`, not `1 лунка`). Stripped here so
// plain substring assertions can read the text the way an inbox would
// actually display it.
function stripHydrationComments(html: string): string {
  return html.replace(/<!--\s*-->/g, '')
}

async function renderHtml(payload: RoundSummaryPayload, locale: 'ru' | 'en'): Promise<string> {
  const html = await render(React.createElement(RoundSummary, { data: payload, locale }))
  return stripHydrationComments(html)
}

describe('RoundSummary — locale', () => {
  it('renders the Russian heading, hero labels, and lang attribute by default content', async () => {
    const html = await renderHtml(makePayload(), 'ru')
    expect(html).toContain('Итоги раунда')
    expect(html).toContain('Удары')
    expect(html).toContain('lang="ru"')
  })

  it('renders the English equivalents for the same payload', async () => {
    const html = await renderHtml(makePayload(), 'en')
    expect(html).toContain('Round summary')
    expect(html).toContain('Strokes')
    expect(html).toContain('lang="en"')
    expect(html).not.toContain('Итоги раунда')
  })

  it('shows the localized match-play winner line', async () => {
    const payload = makePayload({
      match: { label: '2 UP', leaderName: 'Alice', closed: false, holesPlayed: 7, holesRemaining: 2 },
    })
    const ru = await renderHtml(payload, 'ru')
    const en = await renderHtml(payload, 'en')
    expect(ru).toContain('Победитель: Alice')
    expect(en).toContain('Winner: Alice')
  })

  it('shows the localized "players are even" line when there is no leader', async () => {
    const payload = makePayload({
      match: { label: 'AS', leaderName: null, closed: false, holesPlayed: 5, holesRemaining: 4 },
    })
    const ru = await renderHtml(payload, 'ru')
    const en = await renderHtml(payload, 'en')
    expect(ru).toContain('Игроки на равных')
    expect(en).toContain('Players are even')
  })
})

describe('RoundSummary — pluralization', () => {
  it('picks the correct Russian holes form for 1 / 2 / 5 holes', async () => {
    const one = await renderHtml(makePayload({ totalHoles: 1, holesPlayedByMe: 1, scorecard: [] }), 'ru')
    const two = await renderHtml(makePayload({ totalHoles: 2, holesPlayedByMe: 2, scorecard: [] }), 'ru')
    const five = await renderHtml(makePayload({ totalHoles: 5, holesPlayedByMe: 5, scorecard: [] }), 'ru')
    expect(one).toContain('1 лунка')
    expect(two).toContain('2 лунки')
    expect(five).toContain('5 лунок')
  })

  it('picks the correct English holes form for 1 vs 2+ holes', async () => {
    const one = await renderHtml(makePayload({ totalHoles: 1, holesPlayedByMe: 1, scorecard: [] }), 'en')
    const two = await renderHtml(makePayload({ totalHoles: 2, holesPlayedByMe: 2, scorecard: [] }), 'en')
    expect(one).toContain('1 hole')
    expect(one).not.toContain('1 holes')
    expect(two).toContain('2 holes')
  })

  it('pluralizes the best-hole stroke count in Russian (1/2/5 forms)', async () => {
    const base = makePayload()
    const one = await renderHtml({ ...base, bestHole: { hole: 1, par: 4, score: 1, diff: -3, category: 'eagle' } }, 'ru')
    const two = await renderHtml({ ...base, bestHole: { hole: 1, par: 4, score: 2, diff: -2, category: 'eagle' } }, 'ru')
    const five = await renderHtml({ ...base, bestHole: { hole: 1, par: 6, score: 5, diff: -1, category: 'birdie' } }, 'ru')
    expect(one).toContain('1 удар<')
    expect(two).toContain('2 удара')
    expect(five).toContain('5 ударов')
  })

  it('pluralizes the best-hole stroke count in English (1 vs 2+)', async () => {
    const base = makePayload()
    const one = await renderHtml({ ...base, bestHole: { hole: 1, par: 4, score: 1, diff: -3, category: 'eagle' } }, 'en')
    const two = await renderHtml({ ...base, bestHole: { hole: 1, par: 4, score: 2, diff: -2, category: 'eagle' } }, 'en')
    expect(one).toContain('1 stroke<')
    expect(two).toContain('2 strokes')
  })
})
