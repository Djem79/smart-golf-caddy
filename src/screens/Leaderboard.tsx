import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { ChevronLeft, Trophy, Check, TrendingDown, TrendingUp, Minus } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { subscribeToRound } from '../services/rounds'
import { computeLeaderboard, computeMatchPlayStatus } from '../services/scoring'
import type { Round } from '../types'
import { scoreColor, scoreOnColor, scoreDirection, getPlayerDisplayName } from '../types'
import { useT, plural } from '../i18n'
import { Avatar } from '../components/ui/Avatar'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function Leaderboard() {
  const { roundId } = useParams<{ roundId: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { t, locale } = useT()
  const [round, setRound] = useState<Round | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound, () => {
      setLoadError(t.leaderboard.loadError)
    })
  }, [roundId, t])

  if (!round || !roundId) {
    return (
      <div className="screen items-center justify-center px-8 text-center gap-4">
        {loadError ? (
          <>
            <p className="text-error text-body-md">{loadError}</p>
            <Button variant="secondary" onClick={() => navigate('/home', { replace: true })}>
              {t.common.goHome}
            </Button>
          </>
        ) : (
          <p className="text-on-surface-variant text-body-md">{t.common.loading}</p>
        )}
      </div>
    )
  }

  const entries = computeLeaderboard(round).map(entry => ({
    ...entry,
    name: getPlayerDisplayName(entry.name, t.common.deletedPlayerName),
  }))
  const totalHoles = round.totalHoles
  const isMatchPlay = round.playMode === 'match' && round.playerIds.length === 2
  const matchStatus = isMatchPlay
    ? computeMatchPlayStatus(round, round.playerIds[0], round.playerIds[1])
    : null

  // Format score diff like a real scoreboard: 'E' for even, '+5' / '−2' otherwise
  function formatDiff(d: number, thru: number): string {
    if (thru === 0) return '—'
    if (d === 0) return 'E'
    if (d > 0) return `+${d}`
    return String(d) // already includes minus sign
  }

  return (
    <div className="screen pb-6">
      <PageHeader title={t.leaderboard.title} />

      <div className="bg-gradient-to-br from-primary-container to-primary px-5 py-4 flex items-center gap-3">
        <div className="w-10 h-10 rounded-md bg-on-primary/10 flex items-center justify-center text-on-primary shrink-0">
          <Trophy size={20} strokeWidth={1.75} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-on-primary/70 text-label-md uppercase tracking-[0.15em] font-semibold truncate">
            {round.courseName}
          </p>
          <p className="text-on-primary font-headline font-bold text-title-lg tracking-tight">
            {round.status === 'lobby' ? t.leaderboard.lobbyNotStarted
            : round.status === 'finished' ? t.leaderboard.roundFinished
            : `${round.totalHoles} ${plural(round.totalHoles, locale, t.common.holesWord)}`}
            {isMatchPlay && <span className="text-on-primary/80 font-normal">{t.leaderboard.match1v1}</span>}
          </p>
        </div>
      </div>

      {/* Match-play headline — replaces the stroke-play list view for 2-player matches */}
      {isMatchPlay && matchStatus && (
        <div className="px-5 pt-4">
          <div className="bg-surface-container-lowest border border-outline-variant/30 rounded-lg p-5 text-center shadow-card">
            <p className="text-label-md text-on-surface-variant uppercase tracking-[0.15em] font-semibold">
              {t.leaderboard.matchStatus}
            </p>
            <p className="font-headline font-bold text-display-lg text-primary mt-1 tabular-nums tracking-tight">
              {matchStatus.label}
            </p>
            <p className="text-label-lg text-on-surface mt-1">
              {matchStatus.leaderUid
                ? t.leaderboard.leading(
                    getPlayerDisplayName(
                      round.players[matchStatus.leaderUid]?.name ?? t.common.clubLabels.unknown,
                      t.common.deletedPlayerName,
                    ),
                  )
                : t.common.playersEven}
            </p>
            {matchStatus.closed && (
              <p className="text-label-md text-primary font-semibold mt-2 inline-flex items-center gap-1.5">
                <Check size={14} strokeWidth={2.5} />
                {t.leaderboard.matchDecided}
              </p>
            )}
            <p className="text-label-md text-on-surface-variant mt-2">
              {t.leaderboard.playedRemaining(matchStatus.holesPlayed, matchStatus.holesRemaining)}
            </p>
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-2">
        {/* Column headers — three columns: rank, player+score, diff. Thru is now under the name. */}
        <div className="grid grid-cols-[28px_minmax(0,1fr)_64px] gap-3 px-3 text-label-md text-on-surface-variant uppercase tracking-wider font-semibold">
          <span>#</span>
          <span>{t.common.player}</span>
          <span className="text-right">{t.leaderboard.columnToPar}</span>
        </div>

        {entries.map((entry, idx) => {
          const isMe = entry.uid === user?.uid
          const direction = scoreDirection(entry.scoreDiff)
          const color = entry.thru > 0 ? scoreColor(entry.scoreDiff) : 'transparent'
          // Foreground chosen by background luminance (scoreOnColor) so every
          // filled pill meets WCAG AA. Par/empty render on transparent bg with
          // a border, so they use dark text regardless.
          const pillText =
            entry.thru === 0 || entry.scoreDiff === 0 ? '#1A1C1C' : scoreOnColor(entry.scoreDiff)
          const DirIcon = direction === 'under' ? TrendingDown : direction === 'over' ? TrendingUp : Minus
          return (
            <div
              key={entry.uid}
              className={`grid grid-cols-[28px_minmax(0,1fr)_64px] gap-3 items-center p-3 rounded-lg border ${
                isMe ? 'border-primary bg-primary-container/10' : 'border-outline-variant/30 bg-surface-container-lowest'
              }`}
            >
              <span className="font-headline font-bold text-title-lg text-on-surface tabular-nums">
                {idx + 1}
              </span>
              <div className="flex items-center gap-2.5 min-w-0">
                <Avatar src={entry.avatar} name={entry.name} size={32} />
                <div className="min-w-0 flex-1">
                  <p className="font-semibold text-body-md text-on-surface truncate">
                    {isMe ? `${entry.name} (${t.leaderboard.you})` : entry.name}
                  </p>
                  <p className="text-label-md text-on-surface-variant tabular-nums">
                    {entry.thru > 0 ? entry.totalScore : '—'} {t.leaderboard.strokesShort}{' '}
                    <span className="opacity-70">· {entry.thru}/{totalHoles}</span>
                  </p>
                </div>
              </div>
              <span
                className="font-headline font-bold text-title-lg text-center rounded-md px-1.5 py-1 inline-flex items-center justify-center gap-1 tabular-nums"
                style={{
                  backgroundColor: entry.thru > 0 && entry.scoreDiff !== 0 ? color : 'transparent',
                  color: pillText,
                  border:
                    entry.thru > 0 && entry.scoreDiff === 0
                      ? '1px solid #C0C9BB'
                      : 'none',
                }}
              >
                {entry.thru > 0 && (
                  <DirIcon size={12} strokeWidth={2.5} aria-hidden />
                )}
                {formatDiff(entry.scoreDiff, entry.thru)}
              </span>
            </div>
          )
        })}

        {entries.length === 0 && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            {t.leaderboard.noPlayers}
          </p>
        )}
      </div>

      <div className="px-5 pb-6">
        {round.status === 'active' && (
          <Button icon={ChevronLeft} onClick={() => navigate(`/round/${roundId}/hole/1`)}>
            {t.leaderboard.backToHole}
          </Button>
        )}
        {round.status === 'finished' && (
          <Button onClick={() => navigate(`/round/${roundId}/results`)}>
            {t.leaderboard.roundResults}
          </Button>
        )}
      </div>
    </div>
  )
}
