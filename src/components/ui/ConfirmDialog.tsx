import { useEffect } from 'react'
import { Button } from './Button'

interface ConfirmDialogProps {
  open: boolean
  title: string
  body?: string
  confirmLabel?: string
  cancelLabel?: string
  destructive?: boolean
  loading?: boolean
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open,
  title,
  body,
  confirmLabel = 'Подтвердить',
  cancelLabel = 'Отмена',
  destructive = false,
  loading = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onCancel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onCancel])

  if (!open) return null

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-title"
      className="fixed inset-0 z-[100] bg-on-surface/40 flex items-center justify-center p-5"
      onClick={onCancel}
    >
      <div
        className="bg-surface-container-lowest rounded-xl max-w-sm w-full p-5 space-y-4 shadow-card"
        onClick={e => e.stopPropagation()}
      >
        <h2
          id="confirm-title"
          className="font-headline font-bold text-title-lg text-on-surface"
        >
          {title}
        </h2>
        {body && (
          <p className="text-body-md text-on-surface-variant">{body}</p>
        )}
        <div className="flex gap-2 pt-2">
          <Button variant="secondary" onClick={onCancel} disabled={loading} className="flex-1">
            {cancelLabel}
          </Button>
          <Button
            onClick={onConfirm}
            disabled={loading}
            className={`flex-1 ${destructive ? 'bg-error text-on-error' : ''}`}
          >
            {loading ? '...' : confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
