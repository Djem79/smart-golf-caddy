import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { BottomNav } from '../components/layout/BottomNav'
import { computePlayerTotals } from './RoundResults'
import { format } from 'date-fns'
import { ru } from 'date-fns/locale'

export function Home() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [recentRounds, setRecentRounds] = useState<Round[]>([])

  useEffect(() => {
    if (!user) return
    getUserRounds(user.uid).then(rounds =>
      setRecentRounds(rounds.filter(r => r.status === 'finished').slice(0, 3)),
    ).catch(() => {})
  }, [user])

  function formatDate(round: Round) {
    return format(round.createdAt, 'd MMM yyyy', { locale: ru })
  }

  function scoreSummary(round: Round, uid: string) {
    if (!round.players[uid]) return ''
    const { totalScore, scoreDiff } = computePlayerTotals(round, uid)
    const sign = scoreDiff >= 0 ? '+' : ''
    return `${totalScore} (${sign}${scoreDiff})`
  }

  return (
    <div className="screen pb-20">
      <div className="px-5 pt-8 pb-6 bg-primary-container">
        <p className="text-on-primary/80 text-label-lg font-semibold">Добро пожаловать</p>
        <h1 className="font-headline font-bold text-headline-md text-on-primary mt-1">
          {user?.displayName?.split(' ')[0] ?? 'Голфер'} ⛳
        </h1>
      </div>

      <div className="px-5 pt-6 space-y-3">
        <Button onClick={() => navigate('/courses')}>
          Начать новый раунд
        </Button>
        <Button variant="secondary" onClick={() => navigate('/round/setup')}>
          Быстрый старт без выбора поля
        </Button>
        <Button variant="secondary" onClick={() => navigate('/join')}>
          🎟️  Присоединиться к игре
        </Button>

        {recentRounds.length > 0 && (
          <div>
            <h2 className="font-headline font-semibold text-title-lg text-on-surface mb-3">
              Последние раунды
            </h2>
            <div className="space-y-3">
              {recentRounds.map(round => (
                <Card key={round.id} onClick={() => navigate(`/round/${round.id}/results`)}>
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-body-md text-on-surface">{round.courseName}</p>
                      <p className="text-label-lg text-on-surface-variant mt-0.5">
                        {formatDate(round)} · {round.totalHoles} лунок
                      </p>
                    </div>
                    {user && (
                      <span className="font-headline font-bold text-title-lg text-primary">
                        {scoreSummary(round, user.uid)}
                      </span>
                    )}
                  </div>
                </Card>
              ))}
            </div>
          </div>
        )}
      </div>

      <BottomNav />
    </div>
  )
}
