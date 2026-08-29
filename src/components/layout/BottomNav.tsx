import { NavLink } from 'react-router-dom'
import { Home, History as HistoryIcon, User, type LucideIcon } from 'lucide-react'
import { useT } from '../../i18n'

export function BottomNav() {
  const { t } = useT()
  const tabs: { to: string; label: string; Icon: LucideIcon }[] = [
    { to: '/home', label: t.bottomNav.home, Icon: Home },
    { to: '/history', label: t.bottomNav.history, Icon: HistoryIcon },
    { to: '/profile', label: t.bottomNav.profile, Icon: User },
  ]
  return (
    <nav
      className="fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-[390px] bg-surface-container-lowest border-t border-outline-variant/30 flex z-50"
      style={{ paddingBottom: 'env(safe-area-inset-bottom, 0px)' }}
    >
      {tabs.map(({ to, label, Icon }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) =>
            `relative flex-1 flex flex-col items-center justify-center min-h-touch h-14 gap-1 text-label-md font-semibold transition-colors ${
              isActive ? 'text-primary' : 'text-on-surface-variant'
            }`
          }
        >
          {({ isActive }) => (
            <>
              {isActive && (
                <span
                  aria-hidden
                  className="absolute top-0 left-1/2 -translate-x-1/2 w-8 h-[2px] rounded-b-full bg-primary"
                />
              )}
              <Icon size={22} strokeWidth={isActive ? 2 : 1.5} />
              <span className="tracking-wide">{label}</span>
            </>
          )}
        </NavLink>
      ))}
    </nav>
  )
}
