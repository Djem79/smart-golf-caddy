import { useEffect, useRef } from 'react'

/**
 * Wires up the three accessibility primitives every modal needs:
 *
 *   1. **Body scroll lock** — prevents the background from scrolling
 *      underneath the dialog on iOS Safari (the most common offender).
 *   2. **Focus capture on open** — moves keyboard focus inside the dialog
 *      so screen-reader and keyboard users land in the right context.
 *      Falls back to focusing the dialog root if no `data-autofocus`
 *      element is present.
 *   3. **Focus restoration on close** — returns focus to whatever element
 *      had it before the dialog opened (typically the button that triggered
 *      the dialog).
 *
 * Use by attaching the returned `ref` to the dialog's outermost in-content
 * `<div>` (the panel, not the backdrop).
 */
export function useDialogA11y(open: boolean) {
  const containerRef = useRef<HTMLDivElement>(null)
  const previousFocusRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open) return

    previousFocusRef.current = document.activeElement as HTMLElement | null
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    const root = containerRef.current
    if (root) {
      const auto = root.querySelector<HTMLElement>('[data-autofocus]')
      const target = auto ?? root
      // The dialog root needs tabIndex=-1 to receive programmatic focus.
      if (target === root && !root.hasAttribute('tabindex')) {
        root.setAttribute('tabindex', '-1')
      }
      target.focus({ preventScroll: true })
    }

    return () => {
      document.body.style.overflow = prevOverflow
      previousFocusRef.current?.focus?.({ preventScroll: true })
    }
  }, [open])

  return containerRef
}

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

/**
 * Companion handler: install on the dialog panel's `onKeyDown` to keep Tab
 * cycling inside the dialog. Combine with `useDialogA11y` for full
 * focus-trap behaviour.
 */
export function trapTab(e: React.KeyboardEvent<HTMLDivElement>): void {
  if (e.key !== 'Tab') return
  const root = e.currentTarget
  const items = Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    el => !el.hasAttribute('disabled') && el.offsetParent !== null,
  )
  if (items.length === 0) return
  const first = items[0]
  const last = items[items.length - 1]
  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault()
    last.focus()
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault()
    first.focus()
  }
}
