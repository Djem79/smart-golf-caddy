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
      onKeyDown={
        isClickable
          ? e => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault()
                onClick?.()
              }
            }
          : undefined
      }
      className={
        `bg-surface-container-lowest rounded-lg shadow-card ` +
        `border border-outline-variant/25 p-5 ` +
        (isClickable
          ? `cursor-pointer transition-[transform,box-shadow] duration-150 ease-out ` +
            `hover:shadow-card-hover active:scale-[0.995] ` +
            `focus-visible:outline-2 focus-visible:outline-primary focus-visible:outline-offset-2 `
          : ``) +
        className
      }
    >
      {children}
    </div>
  )
}
