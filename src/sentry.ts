import * as Sentry from '@sentry/react'

const DSN = import.meta.env.VITE_SENTRY_DSN as string | undefined

/**
 * Initialise Sentry once on app boot. No-op when:
 * - VITE_SENTRY_DSN isn't set (typical for local dev / CI)
 * - The runtime isn't a browser (defensive — we only call this in main.tsx)
 *
 * In production, errors thrown anywhere in React's render tree are captured
 * automatically. Add `Sentry.captureException(e)` in ErrorBoundary's
 * componentDidCatch to forward structured error info alongside the
 * component stack.
 */
export function initSentry(): void {
  if (!DSN) return
  Sentry.init({
    dsn: DSN,
    // Keep volume low for a tiny app — change as the user base grows.
    tracesSampleRate: 0.1,
    // Don't sample replays / session monitoring for MVP; just exceptions.
    integrations: [],
    environment: import.meta.env.MODE,
    release: import.meta.env.VITE_APP_VERSION ?? 'unversioned',
    // Avoid sending the user's local Firestore token / personal data:
    // by default Sentry doesn't include cookies or PII, but be explicit.
    sendDefaultPii: false,
  })
}

export function captureError(error: unknown, context?: Record<string, unknown>): void {
  if (!DSN) {
    // In dev, surface to console so we still see the error.
    console.error('[captureError]', error, context)
    return
  }
  Sentry.captureException(error, context ? { extra: context } : undefined)
}
