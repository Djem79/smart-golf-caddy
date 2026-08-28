import type { LucideIcon } from 'lucide-react'

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  icon?: LucideIcon
  iconRight?: LucideIcon
}

export function Button({
  variant = 'primary',
  className = '',
  children,
  icon: Icon,
  iconRight: IconRight,
  ...props
}: ButtonProps) {
  // Buttons are full-pill (rounded-full) per the premium design system —
  // serif headlines + pill CTAs read as "editorial / luxury".
  const base =
    'font-body font-semibold text-label-lg rounded-full min-h-touch w-full min-w-0 ' +
    'flex items-center justify-center gap-2 px-5 ' +
    'transition-[transform,background-color,opacity] duration-150 ease-out ' +
    'active:scale-[0.985] disabled:opacity-40 disabled:active:scale-100 ' +
    'focus-visible:outline-2 focus-visible:outline-primary focus-visible:outline-offset-2'
  const variants = {
    primary: 'bg-primary text-on-primary hover:bg-primary-container',
    secondary:
      'border border-outline-variant text-on-surface bg-surface-container-lowest ' +
      'hover:bg-surface-container-low',
    ghost: 'text-primary underline-offset-4 hover:underline',
    // Destructive actions (delete account, etc). Outlined rather than
    // filled — matches `secondary`'s weight so it doesn't compete with the
    // primary CTA on a screen, but reads unmistakably as "dangerous".
    danger:
      'border border-error/40 text-error bg-surface-container-lowest ' +
      'hover:bg-error-container/30',
  }
  return (
    <button className={`${base} ${variants[variant]} ${className}`} {...props}>
      {Icon && <Icon size={18} strokeWidth={1.75} />}
      <span className="truncate">{children}</span>
      {IconRight && <IconRight size={18} strokeWidth={1.75} />}
    </button>
  )
}
