import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronRight, Plus, Users, Zap } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { BottomNav } from '../components/layout/BottomNav'
import { computePlayerTotals } from '../services/scoring'
import { pluralRu } from '../utils/intl'
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

  const firstName = user?.displayName?.split(' ')[0] ?? 'Голфер'

  return (
    <div className="screen pb-24">
      <div className="px-5 pt-10 pb-7 bg-gradient-to-br from-primary-container to-primary">
        <p className="text-on-primary/70 text-label-lg uppercase tracking-[0.18em] font-semibold">
          Добро пожаловать
        </p>
        <h1 className="font-headline font-bold text-headline-lg text-on-primary mt-1 tracking-tight">
          {firstName}
        </h1>
      </div>

      <div className="px-5 pt-6 space-y-3">
        <Button icon={Plus} onClick={() => navigate('/courses')}>
          Начать новый раунд
        </Button>
        <Button variant="secondary" icon={Zap} onClick={() => navigate('/round/setup')}>
          Быстрый старт без выбора поля
        </Button>
        <Button variant="secondary" icon={Users} onClick={() => navigate('/join')}>
          Присоединиться к игре
        </Button>
      </div>

      {recentRounds.length > 0 && (
        <div className="px-5 mt-8">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-headline font-semibold text-title-lg text-on-surface tracking-tight">
              Последние раунды
            </h2>
            <button
              type="button"
              onClick={() => navigate('/history')}
              className="text-label-lg text-primary font-semibold flex items-center gap-0.5"
            >
              Все
              <ChevronRight size={16} strokeWidth={2} />
            </button>
          </div>
          <div className="space-y-2">
            {recentRounds.map(round => (
              <button
                key={round.id}
                type="button"
                onClick={() => navigate(`/round/${round.id}/results`)}
                className="w-full text-left bg-surface-container-lowest border border-outline-variant/25 rounded-lg px-4 py-3.5 active:scale-[0.995] transition-transform shadow-card hover:shadow-card-hover"
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-body-md text-on-surface truncate">
                      {round.courseName}
                    </p>
                    <p className="text-label-md text-on-surface-variant mt-0.5">
                      {formatDate(round)} · {round.totalHoles}{' '}
                      {pluralRu(round.totalHoles, 'лунка', 'лунки', 'лунок')}
                    </p>
                  </div>
                  {user && (
                    <span className="font-headline font-bold text-title-lg text-primary shrink-0 tabular-nums">
                      {scoreSummary(round, user.uid)}
                    </span>
                  )}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      <BottomNav />
    </div>
  )
}
