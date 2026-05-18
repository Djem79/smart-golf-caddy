import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import type { Round } from '../types'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { computePlayerTotals } from './RoundResults'
import { format } from 'date-fns'
import { ru } from 'date-fns/locale'

export function History() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [rounds, setRounds] = useState<Round[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!user) return
    let cancelled = false
    getUserRounds(user.uid)
      .then(all => { if (!cancelled) setRounds(all.filter(r => r.status === 'finished')) })
      .catch(() => {})
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [user])

  function formatDate(round: Round) {
    return format(round.createdAt, 'd MMMM yyyy', { locale: ru })
  }

  return (
    <div className="screen pb-20">
      <PageHeader title="История раундов" showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-3 overflow-y-auto">
        {loading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">Загрузка...</p>
        )}
        {!loading && rounds.length === 0 && (
          <div className="text-center pt-16 space-y-3">
            <p className="text-4xl">⛳</p>
            <p className="text-on-surface-variant text-body-md">Нет завершённых раундов</p>
          </div>
        )}
        {rounds.map(round => {
          const { totalScore, scoreDiff } = user
            ? computePlayerTotals(round, user.uid)
            : { totalScore: 0, scoreDiff: 0 }
          const sign = scoreDiff >= 0 ? '+' : ''
          return (
            <Card key={round.id} onClick={() => navigate(`/round/${round.id}/results`)}>
              <div className="flex items-center justify-between">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-body-md text-on-surface truncate">{round.courseName}</p>
                  <p className="text-label-lg text-on-surface-variant mt-0.5">
                    {formatDate(round)} · {round.totalHoles} лунок · {Object.keys(round.players).length} игр.
                  </p>
                </div>
                <div className="ml-3 text-right shrink-0">
                  <p className="font-headline font-bold text-title-lg text-primary">{totalScore}</p>
                  <p className="text-label-md text-on-surface-variant">{sign}{scoreDiff}</p>
                </div>
              </div>
            </Card>
          )
        })}
      </div>

      <BottomNav />
    </div>
  )
}
