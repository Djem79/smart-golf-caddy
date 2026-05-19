import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { captureError } from '../sentry'

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
        <div className="text-5xl">⚠️</div>
        <div className="space-y-2">
          <h1 className="font-headline font-bold text-headline-md text-on-surface">
            Что-то пошло не так
          </h1>
          <p className="text-body-md text-on-surface-variant">
            Приложение столкнулось с неожиданной ошибкой. Попробуйте обновить страницу
            или вернуться на главную.
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
            className="w-full min-h-touch bg-primary text-on-primary font-headline font-semibold text-label-lg rounded"
          >
            Обновить страницу
          </button>
          <button
            type="button"
            onClick={this.handleHome}
            className="w-full min-h-touch border border-outline text-on-surface font-headline font-semibold text-label-lg rounded"
          >
            На главную
          </button>
        </div>
      </div>
    )
  }
}
