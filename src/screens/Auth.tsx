import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { signInWithGoogle } from '../services/auth'
import { Button } from '../components/ui/Button'

export function Auth() {
  const navigate = useNavigate()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleGoogleSignIn() {
    setLoading(true)
    setError(null)
    try {
      await signInWithGoogle()
      navigate('/home')
    } catch {
      setError('Ошибка входа. Попробуйте ещё раз.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="screen items-center justify-center px-5 gap-8">
      <div className="text-center space-y-3">
        <div className="text-6xl">⛳</div>
        <h1 className="font-headline font-bold text-headline-lg text-primary">Smart Golf Caddy</h1>
        <p className="text-body-md text-on-surface-variant">Ваш цифровой кэдди на поле</p>
      </div>

      <div className="w-full space-y-3">
        <Button onClick={handleGoogleSignIn} disabled={loading}>
          {loading ? 'Вход...' : '🔵  Войти через Google'}
        </Button>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>
    </div>
  )
}
