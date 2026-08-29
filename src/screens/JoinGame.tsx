import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Ticket } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { joinRoundByCode } from '../services/rounds'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { useT } from '../i18n'

export function JoinGame() {
  const { code: paramCode } = useParams<{ code?: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { t } = useT()
  const [code, setCode] = useState((paramCode ?? '').toUpperCase().slice(0, 6))
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Latch so the deep-link auto-join fires exactly once per code, even if the
  // auth `user` object identity changes (token refresh re-emits onAuthStateChanged).
  // The `!loading` guard alone can't prevent re-entry — `loading` isn't in the
  // effect deps, so the closure reads a stale value.
  const attemptedCodeRef = useRef<string | null>(null)

  // If a deep-link param is present, attempt auto-join once the user is known.
  useEffect(() => {
    if (paramCode && user && attemptedCodeRef.current !== paramCode) {
      attemptedCodeRef.current = paramCode
      handleJoin(paramCode)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paramCode, user])

  async function handleJoin(rawCode: string) {
    if (!user) return
    const cleaned = rawCode.trim().toUpperCase()
    if (cleaned.length !== 6) {
      setError(t.joinGame.codeLengthError)
      return
    }
    setLoading(true)
    setError(null)
    try {
      const roundId = await joinRoundByCode(cleaned, user.uid, {
        name: user.displayName ?? t.home.fallbackName,
        avatar: user.photoURL ?? '',
        totalScore: 0,
        scoreDiff: 0,
        email: user.email ?? '',
      })
      if (!roundId) {
        setError(t.joinGame.lobbyNotFound)
        return
      }
      navigate(`/round/${roundId}/lobby`, { replace: true })
    } catch {
      setError(t.joinGame.joinError)
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
      <PageHeader title={t.joinGame.title} />

      <div className="flex-1 px-5 pt-10 space-y-7">
        <div className="text-center space-y-3">
          <div className="w-16 h-16 rounded-2xl bg-primary-container/15 border border-primary-container/20 flex items-center justify-center mx-auto text-primary">
            <Ticket size={28} strokeWidth={1.5} />
          </div>
          <h2 className="font-headline font-bold text-headline-md text-on-surface tracking-tight">
            {t.joinGame.heading}
          </h2>
          <p className="text-body-md text-on-surface-variant max-w-[280px] mx-auto">
            {t.joinGame.subtitle}
          </p>
        </div>

        <div>
          <input
            type="text"
            inputMode="text"
            autoComplete="off"
            autoCapitalize="characters"
            aria-label={t.joinGame.codeLabel}
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
          {loading ? t.joinGame.connecting : t.joinGame.join}
        </Button>

        <Button variant="secondary" onClick={() => navigate('/home')}>
          {t.common.cancel}
        </Button>
      </div>

      <BottomNav />
    </div>
  )
}
