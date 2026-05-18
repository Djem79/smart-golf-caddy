import { useNavigate } from 'react-router-dom'

interface PageHeaderProps {
  title: string
  showBack?: boolean
  right?: React.ReactNode
}

export function PageHeader({ title, showBack = true, right }: PageHeaderProps) {
  const navigate = useNavigate()
  return (
    <header className="flex items-center px-5 py-3 bg-surface-container-lowest border-b border-outline-variant/20 min-h-[56px]">
      {showBack && (
        <button
          onClick={() => navigate(-1)}
          className="min-h-touch min-w-touch flex items-center justify-center -ml-2 text-on-surface"
          aria-label="Назад"
        >
          ←
        </button>
      )}
      <h1 className="flex-1 text-center font-headline font-bold text-title-lg text-on-surface">
        {title}
      </h1>
      <div className="min-w-touch">{right}</div>
    </header>
  )
}
