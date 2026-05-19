interface AvatarProps {
  src?: string | null
  name?: string | null
  size?: 24 | 32 | 40 | 48 | 64
  className?: string
}

function getInitials(name?: string | null): string {
  if (!name) return ''
  const parts = name.trim().split(/\s+/)
  if (parts.length === 0) return ''
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

const sizeMap: Record<NonNullable<AvatarProps['size']>, { box: string; text: string }> = {
  24: { box: 'w-6 h-6', text: 'text-[10px]' },
  32: { box: 'w-8 h-8', text: 'text-[11px]' },
  40: { box: 'w-10 h-10', text: 'text-label-md' },
  48: { box: 'w-12 h-12', text: 'text-label-lg' },
  64: { box: 'w-16 h-16', text: 'text-title-lg' },
}

export function Avatar({ src, name, size = 40, className = '' }: AvatarProps) {
  const { box, text } = sizeMap[size]
  if (src) {
    return (
      <img
        src={src}
        alt={name ?? ''}
        className={`${box} rounded-full object-cover shrink-0 ${className}`}
      />
    )
  }
  return (
    <div
      aria-label={name ?? 'Игрок'}
      className={
        `${box} rounded-full shrink-0 bg-primary-container text-on-primary ` +
        `flex items-center justify-center font-headline font-semibold tracking-wide ${text} ${className}`
      }
    >
      {getInitials(name) || '—'}
    </div>
  )
}
