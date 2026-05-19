import { useEffect, useMemo, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useProfile } from '../hooks/useProfile'
import { subscribeToRound } from '../services/rounds'
import { computePlayerTotals, computeClubUsage, computeMatchPlayStatus } from '../services/scoring'
import { scoreColor, scoreLabel, getBagFromUser, getClubLabel } from '../types'
import type { Round } from '../types'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Avatar } from '../components/ui/Avatar'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { pluralRu } from '../utils/intl'

function findWinner(round: Round): string {
  let best = Infinity
  let bestScore = Infinity
  let winnerId = ''
  for (const uid of Object.keys(round.players)) {
    const { totalScore, scoreDiff } = computePlayerTotals(round, uid)
    if (totalScore === 0) continue // skip players who didn't record any shots
    if (scoreDiff < best || (scoreDiff === best && totalScore < bestScore)) {
      best = scoreDiff
      bestScore = totalScore
      winnerId = uid
    }
  }
  return round.players[winnerId]?.name ?? 'Неизвестно'
}

export function RoundResults() {
  const { roundId } = useParams<{ roundId: string }>()
  const navigate = useNavigate()
  const { profile } = useProfile()
  const [round, setRound] = useState<Round | null>(null)
  // Resolve display names for clubs using the current viewer's bag.
  // Custom clubs owned by other players show as "Клюшка" — acceptable
  // until we snapshot the display name into each shot.
  const viewerBag = useMemo(() => getBagFromUser(profile), [profile])

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  if (!round) {
    return (
      <div className="screen items-center justify-center">
        <p className="text-on-surface-variant text-body-md">Загрузка результатов...</p>
      </div>
    )
  }

  const players = Object.entries(round.players)
  const totalPar = round.holes.reduce((s, h) => s + h.par, 0)

  const isMatchPlay = round.playMode === 'match' && round.playerIds.length === 2
  const matchStatus = isMatchPlay
    ? computeMatchPlayStatus(round, round.playerIds[0], round.playerIds[1])
    : null

  return (
    <div className="screen pb-24">
      <PageHeader title="Итоги раунда" showBack={false} />

      {isMatchPlay && matchStatus ? (
        <div className="bg-gradient-to-br from-primary-container to-primary px-5 py-8 text-center">
          <div className="w-12 h-12 rounded-full bg-on-primary/10 mx-auto flex items-center justify-center text-on-primary mb-3">
            <Trophy size={24} strokeWidth={1.5} />
          </div>
          <p className="text-on-primary/70 text-label-lg uppercase tracking-[0.18em] font-semibold">
            Match play
          </p>
          <p className="font-headline font-bold text-display-lg text-on-primary mt-2 tracking-tight tabular-nums">
            {matchStatus.label}
          </p>
          <p className="text-on-primary text-body-md mt-1 font-medium">
            {matchStatus.leaderUid
              ? round.players[matchStatus.leaderUid]?.name ?? 'Неизвестно'
              : 'Игроки на равных'}
          </p>
          <p className="text-on-primary/70 text-label-md mt-2">
            {round.courseName} · {round.totalHoles}{' '}
            {pluralRu(round.totalHoles, 'лунка', 'лунки', 'лунок')}
          </p>
        </div>
      ) : (
        <div className="bg-gradient-to-br from-primary-container to-primary px-5 py-8 text-center">
          <div className="w-12 h-12 rounded-full bg-on-primary/10 mx-auto flex items-center justify-center text-on-primary mb-3">
            <Trophy size={24} strokeWidth={1.5} />
          </div>
          <p className="text-on-primary/70 text-label-lg uppercase tracking-[0.18em] font-semibold">
            Победитель
          </p>
          <p className="font-headline font-bold text-headline-lg text-on-primary mt-2 tracking-tight">
            {findWinner(round)}
          </p>
          <p className="text-on-primary/70 text-label-md mt-2">
            {round.courseName} · {round.totalHoles}{' '}
            {pluralRu(round.totalHoles, 'лунка', 'лунки', 'лунок')}
          </p>
        </div>
      )}

      <div className="px-5 pt-5 space-y-3">
        {players
          .map(([uid, player]) => ({ uid, player, ...computePlayerTotals(round, uid) }))
          .sort((a, b) =>
            a.scoreDiff !== b.scoreDiff
              ? a.scoreDiff - b.scoreDiff
              : a.totalScore - b.totalScore || a.player.name.localeCompare(b.player.name)
          )
          .map(({ uid, player, totalScore, scoreDiff }) => (
            <Card key={uid}>
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3 min-w-0">
                  <Avatar src={player.avatar} name={player.name} size={40} />
                  <span className="font-semibold text-body-md text-on-surface truncate">{player.name}</span>
                </div>
                <div className="text-right shrink-0">
                  <p className="font-headline font-bold text-title-lg text-on-surface tabular-nums">{totalScore}</p>
                  <p
                    className="text-label-lg tabular-nums"
                    style={{
                      color: scoreColor(scoreDiff) === '#FFFFFF' ? '#717A6D' : scoreColor(scoreDiff),
                    }}
                  >
                    {scoreDiff >= 0 ? '+' : ''}{scoreDiff} ({scoreLabel(scoreDiff)})
                  </p>
                </div>
              </div>
            </Card>
          ))}
      </div>

      <div className="px-5 pt-6">
        <h2 className="font-headline font-semibold text-title-lg text-on-surface mb-3">Клюшки в этом раунде</h2>
        <div className="space-y-3">
          {players.map(([uid, player]) => {
            const usage = computeClubUsage(round, uid)
            if (usage.length === 0) return null
            return (
              <Card key={uid}>
                <p className="font-semibold text-body-md text-on-surface mb-2">{player.name}</p>
                <div className="flex flex-wrap gap-1.5">
                  {usage.map(({ club, count, percent }) => (
                    <span
                      key={club}
                      className="px-2 py-1 rounded-full bg-primary-container/15 text-on-surface text-label-md font-semibold"
                    >
                      {getClubLabel(club, viewerBag)} · {count} ({percent}%)
                    </span>
                  ))}
                </div>
              </Card>
            )
          })}
        </div>
      </div>

      <div className="px-5 pt-6">
        <h2 className="font-headline font-semibold text-title-lg text-on-surface mb-3">Карта счёта</h2>
        <div className="overflow-x-auto rounded-lg border border-outline-variant/30">
          <table className="w-full text-center text-label-md min-w-max">
            <thead>
              <tr className="bg-surface-container">
                <th className="py-2 px-3 text-left text-on-surface-variant font-semibold sticky left-0 bg-surface-container">Игрок</th>
                {round.holes.map(h => (
                  <th key={h.holeNumber} className="py-2 px-2 text-on-surface-variant font-semibold">{h.holeNumber}</th>
                ))}
                <th className="py-2 px-3 text-on-surface font-bold">∑</th>
              </tr>
            </thead>
            <tbody>
              {players.map(([uid, player]) => {
                const { totalScore } = computePlayerTotals(round, uid)
                return (
                  <tr key={uid} className="border-t border-outline-variant/20">
                    <td className="py-2 px-3 text-left font-semibold text-on-surface sticky left-0 bg-surface-container-lowest truncate max-w-[80px]">
                      {player.name}
                    </td>
                    {round.holes.map(hole => {
                      const shots = hole.shots[uid]?.count
                      const delta = shots != null ? shots - hole.par : null
                      return (
                        <td
                          key={hole.holeNumber}
                          className="py-2 px-2 font-semibold text-on-surface"
                          style={{ backgroundColor: delta != null ? scoreColor(delta) : undefined }}
                        >
                          {shots ?? '—'}
                        </td>
                      )
                    })}
                    <td className="py-2 px-3 font-headline font-bold text-on-surface">{totalScore || '—'}</td>
                  </tr>
                )
              })}
              <tr className="border-t-2 border-outline-variant/50 bg-surface-container">
                <td className="py-2 px-3 text-left font-semibold text-on-surface-variant sticky left-0 bg-surface-container">Пар</td>
                {round.holes.map(hole => (
                  <td key={hole.holeNumber} className="py-2 px-2 text-on-surface-variant">{hole.par}</td>
                ))}
                <td className="py-2 px-3 font-bold text-on-surface-variant">{totalPar}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div className="px-5 pt-6 space-y-3">
        <Button onClick={() => navigate('/courses')}>Новый раунд</Button>
        <Button variant="secondary" onClick={() => navigate('/home')}>На главную</Button>
      </div>

      <BottomNav />
    </div>
  )
}
