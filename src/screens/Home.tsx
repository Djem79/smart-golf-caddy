import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronRight, Plus, Users, Zap, Play } from 'lucide-react'
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
  const [activeRound, setActiveRound] = useState<Round | null>(null)
  const [loadError, setLoadError] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (!user) return
    let cancelled = false
    // eslint-disable-next-line react-hooks/set-state-in-effect -- clears stale error before refetching; the async result-handlers set the next value via .then/.catch
    setLoadError(false)
    // Pull a small window — Home only renders the 3 most-recent finished
    // rounds, so reading more than ~10 would be wasted. Bumping a bit above 3
    // because the page filters to `status === 'finished'` (the user may have
    // a live round in flight that we want to skip).
    getUserRounds(user.uid, 10)
      .then(rounds => {
        if (cancelled) return
        setRecentRounds(rounds.filter(r => r.status === 'finished').slice(0, 3))
        // Surface an unfinished round so a paused/reopened game can be resumed
        // instead of looking "reset". Rounds come back newest-first, so the
        // first in-progress one is the most recent.
        setActiveRound(rounds.find(r => r.status === 'active' || r.status === 'lobby') ?? null)
      })
      .catch(() => {
        if (cancelled) return
        setLoadError(true)
      })
    return () => { cancelled = true }
  }, [user, reloadKey])

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

  // Where "Продолжить" lands: a lobby round → its lobby; an active round →
  // the first hole the user hasn't recorded yet (where they left off), or the
  // last hole if every hole already has a shot.
  function resumeTarget(round: Round): string {
    if (round.status === 'lobby') return `/round/${round.id}/lobby`
    let hole = 1
    if (user) {
      const idx = round.holes.findIndex(h => (h.shots[user.uid]?.count ?? 0) === 0)
      hole = idx === -1 ? round.totalHoles : idx + 1
    }
    return `/round/${round.id}/hole/${hole}`
  }

  function resumeSubtitle(round: Round): string {
    if (round.status === 'lobby') return 'Вернуться в лобби'
    const played = user
      ? round.holes.filter(h => (h.shots[user.uid]?.count ?? 0) > 0).length
      : 0
    return `Пройдено ${played} из ${round.totalHoles}`
  }

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

      {activeRound && (
        <div className="px-5 pt-6">
          <button
            type="button"
            onClick={() => navigate(resumeTarget(activeRound))}
            className="w-full text-left bg-primary-container/15 border border-primary/40 rounded-lg px-4 py-4 flex items-center gap-3 active:scale-[0.995] transition-transform shadow-card"
          >
            <div className="w-10 h-10 rounded-full bg-primary text-on-primary flex items-center justify-center shrink-0">
              <Play size={20} strokeWidth={2} />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-label-md text-primary font-semibold uppercase tracking-wider">
                {activeRound.status === 'lobby' ? 'Лобби открыто' : 'Продолжить раунд'}
              </p>
              <p className="font-semibold text-body-md text-on-surface truncate">
                {activeRound.courseName}
              </p>
              <p className="text-label-md text-on-surface-variant mt-0.5">
                {resumeSubtitle(activeRound)}
              </p>
            </div>
            <ChevronRight size={20} strokeWidth={2} className="text-primary shrink-0" />
          </button>
        </div>
      )}

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

      {loadError && (
        <div className="px-5 mt-6">
          <div className="bg-error-container/40 border border-error/30 rounded-lg px-4 py-3 flex items-center justify-between gap-3">
            <p className="text-label-lg text-on-surface">Не удалось загрузить раунды</p>
            <button
              type="button"
              onClick={() => setReloadKey(k => k + 1)}
              className="text-label-lg font-semibold text-primary underline-offset-4 hover:underline shrink-0"
            >
              Повторить
            </button>
          </div>
        </div>
      )}

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
