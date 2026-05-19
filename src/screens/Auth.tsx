import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { signInWithGoogle } from '../services/auth'

// Official 4-colour Google "G" mark — drop-in SVG, no external font.
function GoogleGLogo({ className = '' }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 48 48"
      aria-hidden="true"
      className={className}
    >
      <path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/>
      <path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/>
      <path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/>
      <path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/>
    </svg>
  )
}

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
    } catch (e: unknown) {
      // Firebase Auth errors have a `code` field with a stable identifier.
      // Map the ones users can actually act on to clear Russian copy.
      const code = (e && typeof e === 'object' && 'code' in e) ? String((e as { code: unknown }).code) : ''
      const detail = (e && typeof e === 'object' && 'message' in e) ? String((e as { message: unknown }).message) : ''

      if (code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request') {
        // User aborted on their own — not really an error
        setError(null)
      } else if (code === 'auth/popup-blocked') {
        setError('Браузер заблокировал всплывающее окно. Разрешите всплывающие окна для этого сайта.')
      } else if (code === 'auth/unauthorized-domain') {
        setError('Этот домен не разрешён в Firebase Authentication. Добавьте его в Firebase Console → Authentication → Settings → Authorized domains.')
      } else if (code === 'auth/operation-not-allowed') {
        setError('Вход через Google не включён в Firebase Console (Authentication → Sign-in method).')
      } else if (code === 'auth/network-request-failed') {
        setError('Нет связи с серверами Firebase. Проверьте интернет.')
      } else {
        setError(`Ошибка входа${code ? ` (${code})` : ''}. ${detail || 'Попробуйте ещё раз.'}`)
      }
      console.error('[Auth] signInWithGoogle failed:', e)
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
        <button
          type="button"
          onClick={handleGoogleSignIn}
          disabled={loading}
          className="w-full min-h-touch bg-surface-container-lowest border border-outline-variant rounded flex items-center justify-center gap-3 px-6 font-headline font-semibold text-label-lg text-on-surface active:scale-[0.98] transition-transform disabled:opacity-40"
        >
          <GoogleGLogo className="w-5 h-5 shrink-0" />
          {loading ? 'Вход...' : 'Войти через Google'}
        </button>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>
    </div>
  )
}
