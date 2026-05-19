import { useEffect, useState } from 'react'
import { Check, Copy, Mail, Send, X } from 'lucide-react'
import { Button } from './Button'
import { shareRoundByEmail } from '../../services/share'
import { trapTab, useDialogA11y } from '../../hooks/useDialogA11y'

interface ShareDialogProps {
  open: boolean
  roundId: string
  shareUrl: string
  shareTitle: string
  shareText: string
  onClose: () => void
}

export function ShareDialog({
  open,
  roundId,
  shareUrl,
  shareTitle,
  shareText,
  onClose,
}: ShareDialogProps) {
  const [email, setEmail] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [linkCopied, setLinkCopied] = useState(false)
  const dialogRef = useDialogA11y(open)

  // Escape closes the dialog
  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  // Reset transient form state whenever the dialog re-opens. We track the
  // previous `open` so the resets run exactly on the false→true edge.
  const [wasOpen, setWasOpen] = useState(open)
  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setEmail('')
      setError(null)
      setSuccess(null)
      setLinkCopied(false)
    }
  }

  if (!open) return null

  const canNativeShare =
    typeof navigator !== 'undefined' && typeof navigator.share === 'function'

  async function handleNativeShare() {
    try {
      await navigator.share({ title: shareTitle, text: shareText, url: shareUrl })
    } catch {
      // user dismissed — silent
    }
  }

  async function handleCopyLink() {
    try {
      await navigator.clipboard.writeText(shareUrl)
      setLinkCopied(true)
      window.setTimeout(() => setLinkCopied(false), 1500)
    } catch {
      setError('Не удалось скопировать ссылку')
    }
  }

  async function handleEmailSend() {
    setError(null)
    setSuccess(null)
    if (!/.+@.+\..+/.test(email)) {
      setError('Введите корректный email')
      return
    }
    setSending(true)
    try {
      await shareRoundByEmail(roundId, email.trim())
      setSuccess(`Письмо отправлено на ${email.trim()}`)
      setEmail('')
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Не удалось отправить письмо'
      setError(msg)
    } finally {
      setSending(false)
    }
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="share-title"
      className="fixed inset-0 z-[100] bg-on-surface/40 flex items-end sm:items-center justify-center px-3 sm:px-5"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        className="bg-surface-container-lowest rounded-t-xl sm:rounded-xl max-w-sm w-full p-5 space-y-4 shadow-elevated overflow-hidden focus:outline-none"
        onClick={e => e.stopPropagation()}
        onKeyDown={trapTab}
      >
        <div className="flex items-center justify-between">
          <h2
            id="share-title"
            className="font-headline font-bold text-title-lg text-on-surface tracking-tight"
          >
            Поделиться раундом
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Закрыть"
            data-autofocus
            className="min-h-touch min-w-touch -mr-2 flex items-center justify-center text-on-surface-variant rounded-full active:bg-surface-container/60"
          >
            <X size={20} strokeWidth={1.75} />
          </button>
        </div>

        {/* Native share / copy link row */}
        <div className="flex gap-2">
          {canNativeShare && (
            <Button variant="secondary" icon={Send} onClick={handleNativeShare} className="flex-1">
              Поделиться
            </Button>
          )}
          <Button
            variant="secondary"
            icon={linkCopied ? Check : Copy}
            onClick={handleCopyLink}
            className="flex-1"
          >
            {linkCopied ? 'Скопировано' : 'Скопировать'}
          </Button>
        </div>

        <div className="relative py-1">
          <div className="absolute inset-0 flex items-center" aria-hidden>
            <div className="w-full border-t border-outline-variant/40" />
          </div>
          <div className="relative flex justify-center">
            <span className="bg-surface-container-lowest px-3 text-label-md text-on-surface-variant uppercase tracking-wider">
              или email
            </span>
          </div>
        </div>

        {/* Email form */}
        <div className="space-y-2">
          <label className="text-label-md text-on-surface-variant font-semibold uppercase tracking-wider">
            Отправить отчёт по email
          </label>
          <div className="relative">
            <Mail
              size={18}
              strokeWidth={1.75}
              className="absolute left-3 top-1/2 -translate-y-1/2 text-on-surface-variant pointer-events-none"
            />
            <input
              type="email"
              inputMode="email"
              autoComplete="email"
              placeholder="player@example.com"
              value={email}
              onChange={e => {
                setEmail(e.target.value)
                if (error) setError(null)
              }}
              className="w-full h-12 pl-10 pr-3 bg-surface-container-low rounded-md text-body-md border border-outline-variant/30 focus:border-primary focus:outline-none placeholder:text-on-surface-variant/70"
            />
          </div>
          <Button onClick={handleEmailSend} disabled={sending || email.length === 0}>
            {sending ? 'Отправляем...' : 'Отправить'}
          </Button>
        </div>

        {error && <p className="text-center text-label-lg text-error">{error}</p>}
        {success && (
          <p className="text-center text-label-lg text-primary inline-flex items-center justify-center gap-1.5 w-full">
            <Check size={16} strokeWidth={2.5} />
            {success}
          </p>
        )}
      </div>
    </div>
  )
}
