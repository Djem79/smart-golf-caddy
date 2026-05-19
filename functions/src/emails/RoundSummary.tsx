import {
  Body,
  Button,
  Column,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Preview,
  Row,
  Section,
  Text,
} from '@react-email/components'
import * as React from 'react'
import {
  categoryLabel,
  formatDiff,
  PILL_COLORS,
  type RoundSummaryPayload,
} from './types'

const FONT_STACK =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif'

const PRIMARY = '#00450D'
const PRIMARY_CONTAINER = '#1B5E20'
const SURFACE = '#FFFFFF'
const PAGE_BG = '#F3F3F4'
const TEXT = '#1A1C1C'
const MUTED = '#41493E'
const BORDER = '#C0C9BB'
const AGGREGATE_BG = '#F4F4F4'

interface Props {
  data: RoundSummaryPayload
}

export function RoundSummary({ data }: Props): React.ReactElement {
  const {
    playerName,
    courseName,
    dateLabel,
    totalHoles,
    holesPlayedByMe,
    totalScore,
    scoreDiff,
    bestHole,
    scorecard,
    topClubs,
    match,
    resultsUrl,
  } = data

  const previewText = `${courseName} · ${totalScore} (${formatDiff(scoreDiff)})`

  // Split into front-9 / back-9 for an 18-hole layout; 9-hole rounds stay single.
  const front = scorecard.slice(0, 9)
  const back = scorecard.length > 9 ? scorecard.slice(9, 18) : []

  return (
    <Html lang="ru">
      <Head />
      <Preview>{previewText}</Preview>
      <Body style={{ backgroundColor: PAGE_BG, margin: 0, padding: 0, fontFamily: FONT_STACK }}>
        <Container
          style={{
            maxWidth: '600px',
            margin: '0 auto',
            backgroundColor: SURFACE,
            border: `1px solid ${BORDER}40`,
          }}
        >
          {/* Brand bar */}
          <Section
            style={{
              backgroundColor: PRIMARY_CONTAINER,
              backgroundImage: `linear-gradient(135deg, ${PRIMARY_CONTAINER} 0%, ${PRIMARY} 100%)`,
              padding: '20px 28px',
            }}
          >
            <Text
              style={{
                color: 'rgba(255,255,255,0.7)',
                fontSize: '11px',
                fontWeight: 600,
                letterSpacing: '0.18em',
                textTransform: 'uppercase',
                margin: 0,
              }}
            >
              Smart Golf Caddy
            </Text>
            <Heading
              as="h1"
              style={{
                color: '#FFFFFF',
                fontSize: '22px',
                fontWeight: 700,
                margin: '4px 0 0',
                letterSpacing: '-0.01em',
              }}
            >
              Итоги раунда
            </Heading>
          </Section>

          {/* Hero */}
          <Section style={{ padding: '32px 28px 24px' }}>
            <Text
              style={{
                color: MUTED,
                fontSize: '11px',
                fontWeight: 600,
                letterSpacing: '0.15em',
                textTransform: 'uppercase',
                margin: 0,
              }}
            >
              {dateLabel} · {totalHoles} лунок
            </Text>
            <Heading
              as="h2"
              style={{
                color: TEXT,
                fontSize: '24px',
                fontWeight: 700,
                margin: '4px 0 24px',
                letterSpacing: '-0.01em',
              }}
            >
              {courseName}
            </Heading>

            <Row>
              <Column>
                <Text
                  style={{
                    color: MUTED,
                    fontSize: '11px',
                    fontWeight: 600,
                    letterSpacing: '0.15em',
                    textTransform: 'uppercase',
                    margin: 0,
                  }}
                >
                  {playerName}
                </Text>
                <Text
                  style={{
                    color: PRIMARY,
                    fontSize: '40px',
                    fontWeight: 700,
                    margin: '4px 0 0',
                    lineHeight: 1,
                    letterSpacing: '-0.02em',
                  }}
                >
                  {formatDiff(scoreDiff)}
                </Text>
                <Text style={{ color: TEXT, fontSize: '14px', margin: '4px 0 0' }}>
                  Удары: <strong>{totalScore || '—'}</strong>
                  {holesPlayedByMe < totalHoles && (
                    <span style={{ color: MUTED }}>
                      {' · '}
                      {holesPlayedByMe}/{totalHoles} лунок
                    </span>
                  )}
                </Text>
              </Column>
            </Row>
          </Section>

          {/* Match-play banner */}
          {match && (
            <Section
              style={{
                padding: '16px 28px',
                backgroundColor: '#F8FBF7',
                borderTop: `1px solid ${BORDER}40`,
                borderBottom: `1px solid ${BORDER}40`,
              }}
            >
              <Text
                style={{
                  color: MUTED,
                  fontSize: '11px',
                  fontWeight: 600,
                  letterSpacing: '0.15em',
                  textTransform: 'uppercase',
                  margin: 0,
                }}
              >
                Match play
              </Text>
              <Text
                style={{
                  color: PRIMARY,
                  fontSize: '28px',
                  fontWeight: 700,
                  margin: '4px 0 0',
                  letterSpacing: '-0.01em',
                }}
              >
                {match.label}
              </Text>
              <Text style={{ color: TEXT, fontSize: '14px', margin: '2px 0 0' }}>
                {match.leaderName ? `Победитель: ${match.leaderName}` : 'Игроки на равных'}
              </Text>
            </Section>
          )}

          {/* Scorecard */}
          <Section style={{ padding: '24px 28px 8px' }}>
            <Heading
              as="h3"
              style={{
                color: TEXT,
                fontSize: '16px',
                fontWeight: 600,
                margin: '0 0 12px',
                letterSpacing: '-0.005em',
              }}
            >
              Карта счёта
            </Heading>
            <Scorecard rows={front} aggregateLabel={back.length > 0 ? 'OUT' : 'TOTAL'} />
            {back.length > 0 && (
              <>
                <div style={{ height: '8px' }} />
                <Scorecard rows={back} aggregateLabel="IN" />
              </>
            )}
          </Section>

          {/* Insight */}
          {bestHole && bestHole.diff != null && bestHole.diff <= 0 && (
            <Section style={{ padding: '0 28px 24px' }}>
              <div
                style={{
                  backgroundColor: '#F8FBF7',
                  border: `1px solid ${BORDER}50`,
                  borderRadius: '8px',
                  padding: '14px 16px',
                }}
              >
                <Text
                  style={{
                    color: MUTED,
                    fontSize: '11px',
                    fontWeight: 600,
                    letterSpacing: '0.15em',
                    textTransform: 'uppercase',
                    margin: 0,
                  }}
                >
                  Лучшая лунка
                </Text>
                <Text style={{ color: TEXT, fontSize: '15px', margin: '4px 0 0' }}>
                  <strong>№{bestHole.hole}</strong>
                  {' · '}
                  {categoryLabel(bestHole.category)} на пар {bestHole.par}
                  {' · '}
                  {bestHole.score} удар{getStrokeSuffix(bestHole.score ?? 0)}
                </Text>
              </div>
            </Section>
          )}

          {/* Top clubs */}
          {topClubs.length > 0 && (
            <Section style={{ padding: '0 28px 24px' }}>
              <Heading
                as="h3"
                style={{
                  color: TEXT,
                  fontSize: '16px',
                  fontWeight: 600,
                  margin: '0 0 10px',
                  letterSpacing: '-0.005em',
                }}
              >
                Любимые клюшки
              </Heading>
              {topClubs.map(club => (
                <Row key={club.club} style={{ marginBottom: '6px' }}>
                  <Column style={{ width: '60%' }}>
                    <Text style={{ color: TEXT, fontSize: '14px', margin: 0, fontWeight: 600 }}>
                      {club.club}
                    </Text>
                  </Column>
                  <Column style={{ width: '40%', textAlign: 'right' }}>
                    <Text style={{ color: MUTED, fontSize: '13px', margin: 0 }}>
                      {club.count} · {club.percent}%
                    </Text>
                  </Column>
                </Row>
              ))}
            </Section>
          )}

          {/* CTA */}
          <Section style={{ padding: '8px 28px 32px' }}>
            <Button
              href={resultsUrl}
              style={{
                backgroundColor: PRIMARY,
                color: '#FFFFFF',
                fontSize: '14px',
                fontWeight: 600,
                letterSpacing: '0.02em',
                padding: '14px 24px',
                borderRadius: '8px',
                textDecoration: 'none',
                display: 'block',
                textAlign: 'center',
              }}
            >
              Открыть полные итоги
            </Button>
          </Section>

          {/* Footer */}
          <Hr style={{ borderColor: BORDER + '40', margin: 0 }} />
          <Section style={{ padding: '20px 28px', textAlign: 'center' }}>
            <Text style={{ color: MUTED, fontSize: '11px', margin: 0 }}>
              Это автоматическое письмо. Smart Golf Caddy · smart-golf-caddy.web.app
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  )
}

function getStrokeSuffix(n: number): string {
  // Russian plural for "удар"
  const mod10 = n % 10
  const mod100 = n % 100
  if (mod10 === 1 && mod100 !== 11) return ''
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'а'
  return 'ов'
}

interface ScorecardProps {
  rows: import('./types').EmailHoleRow[]
  aggregateLabel: 'OUT' | 'IN' | 'TOTAL'
}

function Scorecard({ rows, aggregateLabel }: ScorecardProps): React.ReactElement {
  const sumScore = rows.reduce((s, r) => s + (r.score ?? 0), 0)
  const sumPar = rows.reduce((s, r) => s + r.par, 0)
  const totalDiff = sumScore - sumPar
  const hasAnyScore = rows.some(r => r.score != null)

  // Inline table for max email-client compatibility
  return (
    <table
      role="presentation"
      cellPadding={0}
      cellSpacing={0}
      border={0}
      width="100%"
      style={{ borderCollapse: 'separate', borderSpacing: 0, fontSize: '12px' }}
    >
      <thead>
        <tr style={{ backgroundColor: '#363636' }}>
          <th style={thHeader('left')}>Hole</th>
          {rows.map(r => (
            <th key={r.hole} style={thHeader('center')}>
              {r.hole}
            </th>
          ))}
          <th style={thHeader('center')}>{aggregateLabel}</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td style={cell('left', MUTED)}>Par</td>
          {rows.map(r => (
            <td key={r.hole} style={cell('center', MUTED)}>
              {r.par}
            </td>
          ))}
          <td style={cellAggregate('center', MUTED)}>{sumPar}</td>
        </tr>
        <tr>
          <td style={cell('left', TEXT, true)}>Удары</td>
          {rows.map(r => {
            const pill = PILL_COLORS[r.category]
            return (
              <td key={r.hole} style={{ ...cell('center', TEXT), padding: '4px 2px' }}>
                {r.score == null ? (
                  <span style={{ color: MUTED }}>—</span>
                ) : (
                  <span
                    style={{
                      display: 'inline-block',
                      minWidth: '24px',
                      padding: '4px 6px',
                      borderRadius: '12px',
                      backgroundColor: pill.bg,
                      color: pill.fg,
                      fontWeight: 700,
                      fontSize: '12px',
                      lineHeight: '14px',
                    }}
                  >
                    {r.score}
                  </span>
                )}
              </td>
            )
          })}
          <td style={cellAggregate('center', TEXT, true)}>{hasAnyScore ? sumScore : '—'}</td>
        </tr>
        <tr>
          <td style={cell('left', MUTED)}>±Par</td>
          {rows.map(r => (
            <td key={r.hole} style={cell('center', MUTED)}>
              {formatDiff(r.diff)}
            </td>
          ))}
          <td style={cellAggregate('center', diffColor(totalDiff), true)}>
            {hasAnyScore ? formatDiff(totalDiff) : '—'}
          </td>
        </tr>
      </tbody>
    </table>
  )
}

function thHeader(align: 'left' | 'center'): React.CSSProperties {
  return {
    color: '#FFFFFF',
    fontWeight: 700,
    fontSize: '11px',
    padding: '8px 6px',
    textAlign: align,
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
  }
}

function cell(align: 'left' | 'center', color: string, bold = false): React.CSSProperties {
  return {
    color,
    padding: '8px 6px',
    textAlign: align,
    fontWeight: bold ? 700 : 500,
    borderBottom: `1px solid ${BORDER}40`,
    backgroundColor: SURFACE,
  }
}

function cellAggregate(
  align: 'left' | 'center',
  color: string,
  bold = false,
): React.CSSProperties {
  return {
    ...cell(align, color, bold),
    backgroundColor: AGGREGATE_BG,
  }
}

function diffColor(diff: number): string {
  if (diff < 0) return '#42A5F5'
  if (diff === 0) return '#66BB6A'
  if (diff <= 2) return '#9E9E9E'
  return '#EF5350'
}

// Default export so react-email's dev preview can pick it up with a sample payload.
export default function PreviewExample(): React.ReactElement {
  const sample: RoundSummaryPayload = {
    playerName: 'Джамбулат',
    courseName: 'Pirogovo Golf Course',
    dateLabel: '19 мая 2026',
    totalHoles: 18,
    holesPlayedByMe: 18,
    totalScore: 78,
    totalPar: 72,
    scoreDiff: 6,
    bestHole: {
      hole: 3,
      par: 4,
      score: 3,
      diff: -1,
      category: 'birdie',
    },
    scorecard: Array.from({ length: 18 }, (_, i) => {
      const par = ([4, 3, 4, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 4] as const)[i]
      const score = par + ([0, 1, -1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0] as const)[i]
      const diff = score - par
      return {
        hole: i + 1,
        par,
        score,
        diff,
        category: diff <= -2 ? 'eagle' : diff === -1 ? 'birdie' : diff === 0 ? 'par' : diff === 1 ? 'bogey' : diff === 2 ? 'double' : 'worse',
      }
    }),
    topClubs: [
      { club: 'Driver', count: 12, percent: 28 },
      { club: '7-айрон', count: 9, percent: 21 },
      { club: 'Putter', count: 18, percent: 41 },
    ],
    match: null,
    resultsUrl: 'https://smart-golf-caddy.web.app/round/preview/results',
  }
  return <RoundSummary data={sample} />
}
