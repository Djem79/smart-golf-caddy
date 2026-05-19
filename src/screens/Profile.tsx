import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { signOut } from '../services/auth'
import { getUserRounds } from '../services/rounds'
import { computeClubUsage, computePlayerStats, computeHandicap } from '../services/scoring'
import { getBagFromUser, getClubLabel, scoreColor } from '../types'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { Avatar } from '../components/ui/Avatar'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { pluralRu } from '../utils/intl'

export function Profile() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { profile } = useProfile()
  const [signingOut, setSigningOut] = useState(false)
  const [rounds, setRounds] = useState<Round[]>([])

  const bag = useMemo(() => getBagFromUser(profile), [profile])

  useEffect(() => {
    if (!user) return
    let cancelled = false
    getUserRounds(user.uid)
      .then(all => { if (!cancelled) setRounds(all) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [user])

  const stats = useMemo(
    () => user ? computePlayerStats(rounds, user.uid) : null,
    [rounds, user],
  )

  const handicap = useMemo(
    () => user ? computeHandicap(rounds, user.uid) : null,
    [rounds, user],
  )

  const clubStats = useMemo(
    () => user ? computeClubUsage(rounds, user.uid).slice(0, 5) : [],
    [rounds, user],
  )

  async function handleSignOut() {
    setSigningOut(true)
    try {
      await signOut()
      navigate('/auth', { replace: true })
    } catch {
      setSigningOut(false)
    }
  }

  const maxClubCount = clubStats[0]?.count ?? 0
  const totalHoles = stats?.totalHolesPlayed ?? 0
  const pct = (n: number) => totalHoles > 0 ? Math.round((n / totalHoles) * 100) : 0

  return (
    <div className="screen pb-20">
      <PageHeader title="Профиль" showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-5 overflow-y-auto">
        <Card>
          <div className="flex items-center gap-4">
            <Avatar src={user?.photoURL} name={user?.displayName} size={64} />
            <div className="min-w-0 flex-1">
              <p className="font-headline font-bold text-title-lg text-on-surface truncate tracking-tight">
                {user?.displayName ?? 'Голфер'}
              </p>
              <p className="text-label-lg text-on-surface-variant truncate">{user?.email ?? ''}</p>
            </div>
          </div>
        </Card>

        {/* Stats summary: rounds / avg / best / all-time best (only matters if played) */}
        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Статистика</h3>
          {stats && stats.roundsPlayed > 0 ? (
            <div className="grid grid-cols-2 gap-4 mt-3">
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Раундов</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.roundsPlayed}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Ср. удары</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.avgShots.toFixed(stats.avgShots % 1 === 0 ? 0 : 1)}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Лучший счёт</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.bestScore}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Best vs Par</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">
                  {stats.bestScoreDiff != null
                    ? (stats.bestScoreDiff > 0 ? `+${stats.bestScoreDiff}` : stats.bestScoreDiff)
                    : '—'}
                </p>
              </div>
            </div>
          ) : (
            <p className="text-label-lg text-on-surface-variant mt-2">
              Сыграйте первый раунд, чтобы увидеть статистику.
            </p>
          )}
        </Card>

        {/* Hole result distribution — only render when there are holes to summarize */}
        {stats && stats.totalHolesPlayed > 0 && (
          <Card>
            <h3 className="font-headline font-semibold text-title-lg text-on-surface">Распределение по лункам</h3>
            <p className="text-label-md text-on-surface-variant mt-1">
              За все {stats.totalHolesPlayed} {pluralRu(stats.totalHolesPlayed, 'сыгранную лунку', 'сыгранных лунки', 'сыгранных лунок')}
            </p>
            {/* Stacked bar */}
            <div className="flex h-3 w-full rounded-full overflow-hidden mt-3 bg-surface-container">
              {([
                ['eagle',  stats.holeStats.eagle,  scoreColor(-2)],
                ['birdie', stats.holeStats.birdie, scoreColor(-1)],
                ['par',    stats.holeStats.par,    scoreColor(0)],
                ['bogey',  stats.holeStats.bogey,  scoreColor(1)],
                ['double', stats.holeStats.double, scoreColor(2)],
                ['worse',  stats.holeStats.worse,  scoreColor(3)],
              ] as const).map(([key, count, color]) => count > 0 && (
                <div
                  key={key}
                  style={{ width: `${pct(count)}%`, backgroundColor: color }}
                  className="h-full"
                  title={`${key}: ${count}`}
                />
              ))}
            </div>
            {/* Legend */}
            <div className="grid grid-cols-3 gap-y-2 gap-x-3 mt-3">
              {([
                { key: 'eagle',  label: 'Eagle+',  count: stats.holeStats.eagle,  color: scoreColor(-2) },
                { key: 'birdie', label: 'Birdie',  count: stats.holeStats.birdie, color: scoreColor(-1) },
                { key: 'par',    label: 'Par',     count: stats.holeStats.par,    color: scoreColor(0) },
                { key: 'bogey',  label: 'Bogey',   count: stats.holeStats.bogey,  color: scoreColor(1) },
                { key: 'double', label: 'Double',  count: stats.holeStats.double, color: scoreColor(2) },
                { key: 'worse',  label: 'Хуже',    count: stats.holeStats.worse,  color: scoreColor(3) },
              ]).map(item => (
                <div key={item.key} className="flex items-center gap-2 min-w-0">
                  <span
                    className="w-3 h-3 rounded-sm shrink-0 border border-outline-variant/30"
                    style={{ backgroundColor: item.color }}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="text-label-md text-on-surface font-semibold truncate">{item.label}</p>
                    <p className="text-label-md text-on-surface-variant">
                      {item.count} · {pct(item.count)}%
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Гандикап</h3>
          {handicap ? (
            <>
              <p className="font-headline font-bold text-display-lg text-primary mt-2">
                {handicap.index >= 0 ? handicap.index.toFixed(1) : `+${Math.abs(handicap.index).toFixed(1)}`}
              </p>
              <p className="text-label-md text-on-surface-variant">
                {handicap.bestUsed === 8
                  ? `по лучшим 8 из ${handicap.basedOnRounds} раундов · WHS-метод (без course rating / slope)`
                  : `по ${handicap.basedOnRounds} ${pluralRu(handicap.basedOnRounds, 'раунду', 'раундам', 'раундам')}, среднее × 0.96`
                }
              </p>
            </>
          ) : (
            <p className="text-label-lg text-on-surface-variant mt-1">
              Сыграйте минимум 3 раунда — рассчитаем по WHS (best 8 из последних 20 × 0.96).
            </p>
          )}
        </Card>

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Любимые клюшки</h3>
          {clubStats.length === 0 ? (
            <p className="text-label-lg text-on-surface-variant mt-2">
              Статистика появится после первых ударов.
            </p>
          ) : (
            <div className="space-y-2.5 mt-3">
              {clubStats.map(({ club, count, percent }) => (
                <div key={club}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-semibold text-body-md text-on-surface">{getClubLabel(club, bag)}</span>
                    <span className="text-label-md text-on-surface-variant">
                      {count} {pluralRu(count, 'удар', 'удара', 'ударов')} · {percent}%
                    </span>
                  </div>
                  <div className="h-2 bg-surface-container rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary rounded-full"
                      style={{ width: `${(count / maxClubCount) * 100}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card onClick={() => navigate('/bag')}>
          <div className="flex items-center justify-between">
            <div>
              <h3 className="font-headline font-semibold text-title-lg text-on-surface tracking-tight">Моя сумка</h3>
              <p className="text-label-lg text-on-surface-variant mt-1">
                Состав клюшек, дистанции, единицы измерения
              </p>
            </div>
            <ChevronRight size={20} strokeWidth={1.75} className="text-on-surface-variant ml-3 shrink-0" />
          </div>
        </Card>

        <Button variant="secondary" onClick={handleSignOut} disabled={signingOut}>
          {signingOut ? 'Выходим...' : 'Выйти из аккаунта'}
        </Button>
      </div>

      <BottomNav />
    </div>
  )
}
