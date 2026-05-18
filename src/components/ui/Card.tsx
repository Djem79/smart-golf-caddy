interface CardProps {
  children: React.ReactNode
  className?: string
  onClick?: () => void
}

export function Card({ children, className = '', onClick }: CardProps) {
  const isClickable = !!onClick
  return (
    <div
      role={isClickable ? 'button' : undefined}
      tabIndex={isClickable ? 0 : undefined}
      onClick={onClick}
      onKeyDown={isClickable ? (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onClick?.()
        }
      } : undefined}
      className={`bg-surface-container-lowest rounded-lg shadow-card border border-outline-variant/20 p-5 ${isClickable ? 'cursor-pointer active:scale-[0.99] transition-transform focus:outline-2 focus:outline-primary focus:outline-offset-2' : ''} ${className}`}
    >
      {children}
    </div>
  )
}
