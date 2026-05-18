import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { signOut } from '../services/auth'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

export function Profile() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [signingOut, setSigningOut] = useState(false)

  async function handleSignOut() {
    setSigningOut(true)
    try {
      await signOut()
      navigate('/auth', { replace: true })
    } catch {
      setSigningOut(false)
    }
  }

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
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Гандикап</h3>
          <p className="text-label-lg text-on-surface-variant mt-1">
            Будет рассчитан после завершения нескольких раундов (Plan 2).
          </p>
        </Card>

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">Сумка клюшек</h3>
          <p className="text-label-lg text-on-surface-variant mt-1">
            Сейчас используется стандартный набор из 14 клюшек. Настройка появится в Plan 2.
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
