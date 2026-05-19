import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { subscribeToRound } from '../services/rounds'
import { computeLeaderboard, computeMatchPlayStatus } from '../services/scoring'
import type { Round } from '../types'
import { scoreColor } from '../types'
import { PageHeader } from '../components/layout/PageHeader'

export function Leaderboard() {
  const { roundId } = useParams<{ roundId: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [round, setRound] = useState<Round | null>(null)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  if (!round || !roundId) {
    return (
      <div className="screen items-center justify-center">
        <p className="text-on-surface-variant text-body-md">Загрузка...</p>
      </div>
    )
  }

  const entries = computeLeaderboard(round)
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
      <PageHeader title="Турнирная таблица" />

      <div className="bg-primary-container px-5 py-3">
        <p className="text-on-primary/80 text-label-md uppercase tracking-wider">{round.courseName}</p>
        <p className="text-on-primary font-headline font-bold text-title-lg">
          {round.status === 'lobby' ? 'Лобби (ещё не начали)'
          : round.status === 'finished' ? 'Раунд завершён'
          : `${round.totalHoles} лунок`}
        </p>
        {isMatchPlay && (
          <p className="text-on-primary/80 text-label-md mt-1">
            Match play · 1 v 1
          </p>
        )}
      </div>

      {/* Match-play headline — replaces the stroke-play list view for 2-player matches */}
      {isMatchPlay && matchStatus && (
        <div className="px-5 pt-4">
          <div className="bg-surface-container-lowest border border-outline-variant/30 rounded-lg p-5 text-center">
            <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Match status</p>
            <p className="font-headline font-bold text-display-lg text-primary mt-1">{matchStatus.label}</p>
            <p className="text-label-md text-on-surface-variant mt-1">
              {matchStatus.leaderUid
                ? `Ведёт: ${round.players[matchStatus.leaderUid]?.name ?? 'Неизвестно'}`
                : 'Игроки на равных'}
            </p>
            {matchStatus.closed && (
              <p className="text-label-md text-primary font-semibold mt-2">Матч решён ✓</p>
            )}
            <p className="text-label-md text-on-surface-variant mt-1">
              Сыграно: {matchStatus.holesPlayed} · Осталось: {matchStatus.holesRemaining}
            </p>
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-2">
        {/* Column headers */}
        <div className="grid grid-cols-[28px_1fr_auto_56px_56px] gap-3 px-3 text-label-md text-on-surface-variant uppercase tracking-wider font-semibold">
          <span>#</span>
          <span>Игрок</span>
          <span className="text-right">Удары</span>
          <span className="text-center">Thru</span>
          <span className="text-right">К пару</span>
        </div>

        {entries.map((entry, idx) => {
          const isMe = entry.uid === user?.uid
          const color = entry.thru > 0 ? scoreColor(entry.scoreDiff) : '#FFFFFF'
          return (
            <div
              key={entry.uid}
              className={`grid grid-cols-[28px_1fr_auto_56px_56px] gap-3 items-center p-3 rounded-lg border ${
                isMe ? 'border-primary bg-primary-container/10' : 'border-outline-variant/30 bg-surface-container-lowest'
              }`}
            >
              <span className="font-headline font-bold text-title-lg text-on-surface">
                {idx + 1}
              </span>
              <div className="flex items-center gap-2 min-w-0">
                {entry.avatar
                  ? <img src={entry.avatar} alt={entry.name} className="w-8 h-8 rounded-full shrink-0" />
                  : <div className="w-8 h-8 rounded-full bg-surface-container flex items-center justify-center text-label-md shrink-0">⛳</div>
                }
                <span className="font-semibold text-body-md text-on-surface truncate">
                  {isMe ? `${entry.name} (вы)` : entry.name}
                </span>
              </div>
              <span className="font-headline font-bold text-title-lg text-on-surface text-right">
                {entry.thru > 0 ? entry.totalScore : '—'}
              </span>
              <span className="text-label-lg text-on-surface-variant text-center">
                {entry.thru}/{totalHoles}
              </span>
              <span
                className="font-headline font-bold text-title-lg text-right rounded px-1.5 py-0.5"
                style={{
                  backgroundColor: entry.thru > 0 && entry.scoreDiff !== 0 ? color : 'transparent',
                  color: entry.thru > 0 && entry.scoreDiff > 0 ? '#FFFFFF' : '#1A1C1C',
                }}
              >
                {formatDiff(entry.scoreDiff, entry.thru)}
              </span>
            </div>
          )
        })}

        {entries.length === 0 && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            Игроков пока нет
          </p>
        )}
      </div>

      <div className="px-5 pb-6">
        {round.status === 'active' && (
          <button
            type="button"
            onClick={() => navigate(`/round/${roundId}/hole/1`)}
            className="w-full min-h-touch bg-primary text-on-primary font-headline font-semibold text-label-lg rounded active:scale-[0.98] transition-transform"
          >
            ← Назад к лунке
          </button>
        )}
        {round.status === 'finished' && (
          <button
            type="button"
            onClick={() => navigate(`/round/${roundId}/results`)}
            className="w-full min-h-touch bg-primary text-on-primary font-headline font-semibold text-label-lg rounded active:scale-[0.98] transition-transform"
          >
            Итоги раунда →
          </button>
        )}
      </div>
    </div>
  )
}
