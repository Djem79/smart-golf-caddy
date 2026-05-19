import { useNavigate } from 'react-router-dom'
import { ChevronLeft } from 'lucide-react'

interface PageHeaderProps {
  title: string
  showBack?: boolean
  right?: React.ReactNode
}

export function PageHeader({ title, showBack = true, right }: PageHeaderProps) {
  const navigate = useNavigate()
  return (
    <header className="flex items-center px-4 h-14 bg-surface-container-lowest border-b border-outline-variant/30">
      <div className="w-12 flex items-center">
        {showBack && (
          <button
            onClick={() => navigate(-1)}
            className="min-h-touch min-w-touch -ml-3 flex items-center justify-center text-on-surface rounded-full active:bg-surface-container-high/60 transition-colors"
            aria-label="Назад"
          >
            <ChevronLeft size={24} strokeWidth={1.75} />
          </button>
        )}
      </div>
      <h1 className="flex-1 text-center font-headline font-semibold text-title-lg text-on-surface tracking-tight">
        {title}
      </h1>
      <div className="w-12 flex items-center justify-end">{right}</div>
    </header>
  )
}
