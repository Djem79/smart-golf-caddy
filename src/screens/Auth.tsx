import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import {
  signInWithGoogle,
  signInWithApple,
  authErrorCode,
  isPopupCancelled,
} from '../services/auth'
import { useT } from '../i18n'
import type { Dictionary } from '../i18n'

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

// Apple logo for the custom Sign in with Apple button (HIG: "Creating a
// custom Sign in with Apple button" — logo + one of Apple's three titles,
// black / white / white-outline only, never recoloured). Drawn inline so
// the button works offline and without Apple's JS SDK, which would also
// require a Service ID that doesn't exist until the paid developer
// account is active.
function AppleLogo({ className = '' }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      aria-hidden="true"
      className={className}
      fill="currentColor"
    >
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
  )
}

// Maps a sign-in failure to user-facing copy. `null` = the user aborted on
// their own (closed the popup) — nothing to show. Shared by both providers:
// every branch here is a Firebase Auth code, not provider-specific.
function describeSignInError(e: unknown, t: Dictionary): string | null {
  if (isPopupCancelled(e)) return null
  const code = authErrorCode(e)
  const detail = (e && typeof e === 'object' && 'message' in e) ? String((e as { message: unknown }).message) : ''
  switch (code) {
    case 'auth/popup-blocked': return t.auth.errors.popupBlocked
    case 'auth/unauthorized-domain': return t.auth.errors.unauthorizedDomain
    case 'auth/operation-not-allowed': return t.auth.errors.operationNotAllowed
    case 'auth/account-exists-with-different-credential': return t.auth.errors.accountExists
    case 'auth/network-request-failed': return t.auth.errors.networkFailed
    default: return `${t.auth.errors.signInFailed(code)} ${detail || t.auth.errors.tryAgain}`
  }
}

type Provider = 'google' | 'apple'

export function Auth() {
  const navigate = useNavigate()
  const location = useLocation()
  const { t, locale } = useT()
  const [loading, setLoading] = useState<Provider | null>(null)
  const [error, setError] = useState<string | null>(null)

  // Where ProtectedRoute bounced the user from (e.g. a /join/:code deep link).
  // Return them there after sign-in; fall back to /home for direct visits.
  const from = (location.state as { from?: string } | null)?.from
  const redirectTo = from && from.startsWith('/') && !from.startsWith('/auth') ? from : '/home'

  // Sign in with Apple включается ТОЛЬКО после активации провайдера
  // (платный Apple Developer + Firebase console — см. SETUP.md, раздел
  // «Sign in with Apple — включение после оплаты»). До этого кнопка не
  // рендерится: иначе каждый тап падал бы с operation-not-allowed прямо
  // в проде. Паттерн тот же, что у App Check и Sentry: фича — no-op без
  // env-переменной.
  const appleEnabled = import.meta.env.VITE_APPLE_SIGNIN_ENABLED === 'true'

  async function handleSignIn(provider: Provider) {
    if (loading) return
    setLoading(provider)
    setError(null)
    try {
      if (provider === 'apple') await signInWithApple(locale)
      else await signInWithGoogle()
      navigate(redirectTo, { replace: true })
    } catch (e: unknown) {
      setError(describeSignInError(e, t))
      console.error(`[Auth] signInWith${provider === 'apple' ? 'Apple' : 'Google'} failed:`, e)
    } finally {
      setLoading(null)
    }
  }

  return (
    <div className="screen items-stretch px-0 bg-gradient-to-b from-primary-container to-primary">
      <div className="flex-1 flex flex-col px-5 pt-16">
        <div className="space-y-3">
          <p className="text-on-primary/70 text-label-lg uppercase tracking-[0.2em] font-semibold">
            Premium golf companion
          </p>
          <h1 className="font-headline font-bold text-display-lg text-on-primary leading-[1.05] tracking-tight">
            Smart<br />Golf Caddy
          </h1>
          <p className="text-on-primary/80 text-body-md max-w-[260px]">
            {t.auth.subtitle}
          </p>
        </div>
      </div>

      {/* App Store 4.8: the Apple button must be at least as prominent as
          any other third-party sign-in and visible without scrolling — both
          buttons share this block, the same width and the same height. */}
      <div className="bg-surface rounded-t-3xl px-5 pt-7 pb-10 space-y-3 shadow-elevated">
        <button
          type="button"
          onClick={() => handleSignIn('google')}
          disabled={loading !== null}
          className="w-full min-h-touch bg-surface-container-lowest border border-outline-variant/60 rounded-md flex items-center justify-center gap-3 px-6 font-headline font-semibold text-label-lg text-on-surface active:scale-[0.985] transition-transform disabled:opacity-40 shadow-card"
        >
          <GoogleGLogo className="w-5 h-5 shrink-0" />
          {loading === 'google' ? t.auth.signingIn : t.auth.signInWithGoogle}
        </button>

        {/* HIG custom-button rules: black fill, white system-font title,
            logo height tied to the title, corner radius may match the app's
            other buttons. Title text comes from the dictionary but is
            Apple's own wording per locale, never a free translation. */}
        {appleEnabled && (
          <button
            type="button"
            onClick={() => handleSignIn('apple')}
            disabled={loading !== null}
            className="w-full min-h-touch bg-black text-white rounded-md flex items-center justify-center gap-2.5 px-6 font-sans font-medium text-[1.0625rem] active:scale-[0.985] transition-transform disabled:opacity-40 shadow-card"
          >
            <AppleLogo className="w-5 h-5 shrink-0 -mt-0.5" />
            {loading === 'apple' ? t.auth.signingIn : t.auth.signInWithApple}
          </button>
        )}

        {error && (
          <p role="alert" className="text-center text-label-lg text-error">{error}</p>
        )}

        <p className="text-center text-label-md text-on-surface-variant pt-2">
          {t.auth.termsNotice}
        </p>
      </div>
    </div>
  )
}
