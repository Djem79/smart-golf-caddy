import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import { captureError } from '../sentry'
import { getLocale } from '../i18n'
import { ru } from '../i18n/ru'
import { en } from '../i18n/en'

// React error boundaries are class components, so they can't call the
// useT() hook. Locale changes (T3) won't re-render this rarely-mounted
// screen anyway — a plain lookup by the current locale is enough.
const t = () => (getLocale() === 'ru' ? ru : en)

interface ErrorBoundaryProps {
  children: ReactNode
}

interface ErrorBoundaryState {
  error: Error | null
}

// React error boundaries must be class components; there's no hook equivalent.
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    // Forward to Sentry when DSN is configured; falls back to console in dev.
    captureError(error, { componentStack: info.componentStack })
  }

  handleReload = (): void => {
    window.location.reload()
  }

  handleHome = (): void => {
    window.location.assign('/home')
  }

  render(): ReactNode {
    if (!this.state.error) return this.props.children

    return (
      <div className="screen items-center justify-center px-5 py-10 gap-6 text-center">
        <div className="w-16 h-16 rounded-full bg-error-container flex items-center justify-center text-error">
          <AlertTriangle size={28} strokeWidth={1.5} />
        </div>
        <div className="space-y-2">
          <h1 className="font-headline font-bold text-headline-md text-on-surface tracking-tight">
            {t().errorBoundary.title}
          </h1>
          <p className="text-body-md text-on-surface-variant">
            {t().errorBoundary.body}
          </p>
        </div>

        {import.meta.env.DEV && (
          <pre className="w-full text-left text-label-md text-error bg-error-container/30 rounded-md p-3 overflow-auto max-h-40">
            {this.state.error.message}
          </pre>
        )}

        <div className="w-full space-y-3">
          <button
            type="button"
            onClick={this.handleReload}
            className="w-full min-h-touch bg-primary text-on-primary font-headline font-semibold text-label-lg rounded-md active:scale-[0.985] transition-transform"
          >
            {t().errorBoundary.reload}
          </button>
          <button
            type="button"
            onClick={this.handleHome}
            className="w-full min-h-touch border border-outline-variant text-on-surface font-headline font-semibold text-label-lg rounded-md active:scale-[0.985] transition-transform"
          >
            {t().common.goHome}
          </button>
        </div>
      </div>
    )
  }
}
