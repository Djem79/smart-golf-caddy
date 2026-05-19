import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Ticket } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { joinRoundByCode } from '../services/rounds'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

export function JoinGame() {
  const { code: paramCode } = useParams<{ code?: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [code, setCode] = useState((paramCode ?? '').toUpperCase().slice(0, 6))
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // If a deep-link param is present, attempt auto-join once the user is known.
  useEffect(() => {
    if (paramCode && user && !loading) {
      handleJoin(paramCode)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paramCode, user])

  async function handleJoin(rawCode: string) {
    if (!user) return
    const cleaned = rawCode.trim().toUpperCase()
    if (cleaned.length !== 6) {
      setError('Код должен содержать 6 символов')
      return
    }
    setLoading(true)
    setError(null)
    try {
      const roundId = await joinRoundByCode(cleaned, user.uid, {
        name: user.displayName ?? 'Голфер',
        avatar: user.photoURL ?? '',
        totalScore: 0,
        scoreDiff: 0,
      })
      if (!roundId) {
        setError('Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое.')
        return
      }
      navigate(`/round/${roundId}/lobby`, { replace: true })
    } catch {
      setError('Не удалось присоединиться. Проверьте интернет и попробуйте снова.')
    } finally {
      setLoading(false)
    }
  }

  function onCodeChange(value: string) {
    // Keep only uppercase alphanumerics, cap at 6
    const cleaned = value.replace(/[^A-Za-z0-9]/g, '').toUpperCase().slice(0, 6)
    setCode(cleaned)
    if (error) setError(null)
  }

  return (
    <div className="screen pb-20">
      <PageHeader title="Присоединиться к игре" />

      <div className="flex-1 px-5 pt-10 space-y-7">
        <div className="text-center space-y-3">
          <div className="w-16 h-16 rounded-2xl bg-primary-container/15 border border-primary-container/20 flex items-center justify-center mx-auto text-primary">
            <Ticket size={28} strokeWidth={1.5} />
          </div>
          <h2 className="font-headline font-bold text-headline-md text-on-surface tracking-tight">
            Введите код лобби
          </h2>
          <p className="text-body-md text-on-surface-variant max-w-[280px] mx-auto">
            Хост в своём приложении видит 6-значный код или QR
          </p>
        </div>

        <div>
          <input
            type="text"
            inputMode="text"
            autoComplete="off"
            autoCapitalize="characters"
            placeholder="ABCDEF"
            value={code}
            onChange={e => onCodeChange(e.target.value)}
            maxLength={6}
            className="w-full h-20 px-4 text-center font-headline font-bold text-display-lg tracking-[0.5em] uppercase bg-surface-container-lowest border-2 border-outline-variant rounded-lg focus:border-primary"
          />
        </div>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}

        <Button onClick={() => handleJoin(code)} disabled={loading || code.length !== 6}>
          {loading ? 'Подключаемся...' : 'Присоединиться'}
        </Button>

        <Button variant="secondary" onClick={() => navigate('/home')}>
          Отмена
        </Button>
      </div>

      <BottomNav />
    </div>
  )
}
