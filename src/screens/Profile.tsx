import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { signOut } from '../services/auth'
import { getUserRounds } from '../services/rounds'
import { computeClubUsage } from '../services/scoring'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

export function Profile() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [signingOut, setSigningOut] = useState(false)
  const [rounds, setRounds] = useState<Round[]>([])

  useEffect(() => {
    if (!user) return
    let cancelled = false
    getUserRounds(user.uid)
      .then(all => { if (!cancelled) setRounds(all) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [user])

  const finishedRounds = useMemo(
    () => rounds.filter(r => r.status === 'finished'),
    [rounds],
  )

  const clubStats = useMemo(
    () => user ? computeClubUsage(rounds, user.uid).slice(0, 5) : [],
    [rounds, user],
  )

  const totalShots = useMemo(
    () => clubStats.reduce((s, c) => s + c.count, 0),
    [clubStats],
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

  const maxCount = clubStats[0]?.count ?? 0

  return (
    <div className="screen pb-20">
      <PageHeader title="Профиль" showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-5 overflow-y-auto">
        <Card>
          <div className="flex items-center gap-4">
            {user?.photoURL
              ? <img src={user.photoURL} alt={user.displayName ?? 'Avatar'} className="w-16 h-16 rounded-full" />
              : <div className="w-16 h-16 rounded-full bg-surface-container flex items-center justify-center text-headline-md">⛳</div>
            }
            <div className="min-w-0 flex-1">
              <p className="font-headline font-bold text-title-lg text-on-surface truncate">
                {user?.displayName ?? 'Голфер'}
              </p>
              <p className="text-label-lg text-on-surface-variant truncate">{user?.email ?? ''}</p>
            </div>
          </div>
        </Card>

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Сводка</h3>
          <div className="grid grid-cols-2 gap-3 mt-3">
            <div>
              <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Раундов сыграно</p>
              <p className="font-headline font-bold text-headline-md text-primary mt-1">{finishedRounds.length}</p>
            </div>
            <div>
              <p className="text-label-md text-on-surface-variant uppercase tracking-wider">Всего ударов</p>
              <p className="font-headline font-bold text-headline-md text-primary mt-1">{totalShots}</p>
            </div>
          </div>
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
                    <span className="font-semibold text-body-md text-on-surface">{club}</span>
                    <span className="text-label-md text-on-surface-variant">
                      {count} {count === 1 ? 'удар' : 'ударов'} · {percent}%
                    </span>
                  </div>
                  <div className="h-2 bg-surface-container rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary rounded-full"
                      style={{ width: `${(count / maxCount) * 100}%` }}
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
              <h3 className="font-headline font-semibold text-title-lg text-on-surface">Моя сумка</h3>
              <p className="text-label-lg text-on-surface-variant mt-1">
                Состав клюшек, дистанции, единицы измерения
              </p>
            </div>
            <span className="text-primary text-headline-md ml-3 shrink-0">→</span>
          </div>
        </Card>

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Гандикап</h3>
          <p className="text-label-lg text-on-surface-variant mt-1">
            Будет рассчитан после нескольких раундов (Plan 2).
          </p>
        </Card>

        <Button variant="secondary" onClick={handleSignOut} disabled={signingOut}>
          {signingOut ? 'Выходим...' : 'Выйти из аккаунта'}
        </Button>
      </div>

      <BottomNav />
    </div>
  )
}
