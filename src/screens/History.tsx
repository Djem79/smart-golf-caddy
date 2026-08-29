import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Flag } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import type { Round } from '../types'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { computePlayerTotals } from '../services/scoring'
import { useT, plural, getDateFnsLocale } from '../i18n'
import { format } from 'date-fns'

export function History() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { t, locale } = useT()
  const [rounds, setRounds] = useState<Round[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (!user) return
    let cancelled = false
    // eslint-disable-next-line react-hooks/set-state-in-effect -- prime loading + clear stale error before refetching; result-handlers below transition them through .then/.catch/.finally
    setLoading(true)
    setLoadError(false)
    getUserRounds(user.uid)
      .then(all => { if (!cancelled) setRounds(all.filter(r => r.status === 'finished')) })
      .catch(() => { if (!cancelled) setLoadError(true) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [user, reloadKey])

  function formatDate(round: Round) {
    return format(round.createdAt, 'd MMMM yyyy', { locale: getDateFnsLocale(locale) })
  }

  return (
    <div className="screen pb-20">
      <PageHeader title={t.history.title} showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-3 overflow-y-auto">
        {loadError && (
          <div className="bg-error-container/40 border border-error/30 rounded-lg px-4 py-3 flex items-center justify-between gap-3">
            <p className="text-label-lg text-on-surface">{t.history.loadError}</p>
            <button
              type="button"
              onClick={() => setReloadKey(k => k + 1)}
              className="text-label-lg font-semibold text-primary underline-offset-4 hover:underline shrink-0"
            >
              {t.common.retry}
            </button>
          </div>
        )}
        {loading && !loadError && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">{t.common.loading}</p>
        )}
        {!loading && !loadError && rounds.length === 0 && (
          <div className="text-center pt-16 space-y-3">
            <div className="w-14 h-14 rounded-full bg-surface-container flex items-center justify-center mx-auto text-on-surface-variant">
              <Flag size={26} strokeWidth={1.5} />
            </div>
            <p className="text-on-surface-variant text-body-md">{t.history.empty}</p>
          </div>
        )}
        {rounds.map(round => {
          const { totalScore, scoreDiff } = user
            ? computePlayerTotals(round, user.uid)
            : { totalScore: 0, scoreDiff: 0 }
          const sign = scoreDiff >= 0 ? '+' : ''
          const playerCount = Object.keys(round.players).length
          return (
            <Card key={round.id} onClick={() => navigate(`/round/${round.id}/results`)}>
              <div className="flex items-center justify-between">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-body-md text-on-surface truncate">{round.courseName}</p>
                  <p className="text-label-lg text-on-surface-variant mt-0.5">
                    {formatDate(round)} · {round.totalHoles} {plural(round.totalHoles, locale, t.common.holesWord)} · {playerCount} {plural(playerCount, locale, t.common.playersWord)}
                  </p>
                </div>
                <div className="ml-3 text-right shrink-0">
                  <p className="font-headline font-bold text-title-lg text-primary tabular-nums">{totalScore}</p>
                  <p className="text-label-md text-on-surface-variant tabular-nums">{sign}{scoreDiff}</p>
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
