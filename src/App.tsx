import { lazy, Suspense, type ComponentType } from 'react'
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { Auth } from './screens/Auth'
import { Home } from './screens/Home'

// A failed dynamic import almost always means this tab is running an older
// build whose chunk hashes were replaced by a fresh deploy (the old .js 404s).
// Reload ONCE to fetch the new index + chunks; a sessionStorage guard stops a
// genuinely-broken chunk from looping forever, and a successful load clears it
// so the recovery is armed again for the next deploy.
const RELOAD_KEY = 'chunk-reload-attempted'
function lazyWithReload<T extends ComponentType<object>>(
  factory: () => Promise<{ default: T }>,
) {
  return lazy(() =>
    factory().then(
      mod => {
        sessionStorage.removeItem(RELOAD_KEY)
        return mod
      },
      (err: unknown) => {
        if (!sessionStorage.getItem(RELOAD_KEY)) {
          sessionStorage.setItem(RELOAD_KEY, '1')
          window.location.reload()
          // Keep Suspense showing the fallback while the page reloads.
          return new Promise<{ default: T }>(() => {})
        }
        throw err
      },
    ),
  )
}

// Lazy-load heavier / less-immediate screens. Each becomes its own chunk;
// the initial bundle only ships Auth + Home + shared infra.
const CourseSearch = lazyWithReload(() => import('./screens/CourseSearch').then(m => ({ default: m.CourseSearch })))
const RoundSetup   = lazyWithReload(() => import('./screens/RoundSetup').then(m => ({ default: m.RoundSetup })))
const HoleTracker  = lazyWithReload(() => import('./screens/HoleTracker').then(m => ({ default: m.HoleTracker })))
const RoundResults = lazyWithReload(() => import('./screens/RoundResults').then(m => ({ default: m.RoundResults })))
const History      = lazyWithReload(() => import('./screens/History').then(m => ({ default: m.History })))
const Profile      = lazyWithReload(() => import('./screens/Profile').then(m => ({ default: m.Profile })))
const MyBag        = lazyWithReload(() => import('./screens/MyBag').then(m => ({ default: m.MyBag })))
const JoinGame     = lazyWithReload(() => import('./screens/JoinGame').then(m => ({ default: m.JoinGame })))
const GroupLobby   = lazyWithReload(() => import('./screens/GroupLobby').then(m => ({ default: m.GroupLobby })))
const Leaderboard  = lazyWithReload(() => import('./screens/Leaderboard').then(m => ({ default: m.Leaderboard })))

function LoadingScreen({ label = 'Загрузка...' }: { label?: string }) {
  return (
    <div className="screen items-center justify-center">
      <div className="text-on-surface-variant text-body-md">{label}</div>
    </div>
  )
}

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  const location = useLocation()
  if (loading) return <LoadingScreen />
  // Remember where the user was headed (e.g. a /join/:code deep link from a
  // QR scan) so Auth can return them there after sign-in instead of dropping
  // them on /home and losing the lobby code.
  if (!user) {
    return (
      <Navigate
        to="/auth"
        replace
        state={{ from: location.pathname + location.search }}
      />
    )
  }
  return <>{children}</>
}

export default function App() {
  return (
    <BrowserRouter>
      <Suspense fallback={<LoadingScreen />}>
        <Routes>
          <Route path="/auth" element={<Auth />} />
          <Route path="/" element={<Navigate to="/home" replace />} />
          <Route path="/home" element={<ProtectedRoute><Home /></ProtectedRoute>} />
          <Route path="/courses" element={<ProtectedRoute><CourseSearch /></ProtectedRoute>} />
          <Route path="/round/setup" element={<ProtectedRoute><RoundSetup /></ProtectedRoute>} />
          <Route path="/round/:roundId/lobby" element={<ProtectedRoute><GroupLobby /></ProtectedRoute>} />
          <Route path="/round/:roundId/hole/:holeNumber" element={<ProtectedRoute><HoleTracker /></ProtectedRoute>} />
          <Route path="/round/:roundId/leaderboard" element={<ProtectedRoute><Leaderboard /></ProtectedRoute>} />
          <Route path="/round/:roundId/results" element={<ProtectedRoute><RoundResults /></ProtectedRoute>} />
          <Route path="/join" element={<ProtectedRoute><JoinGame /></ProtectedRoute>} />
          <Route path="/join/:code" element={<ProtectedRoute><JoinGame /></ProtectedRoute>} />
          <Route path="/history" element={<ProtectedRoute><History /></ProtectedRoute>} />
          <Route path="/profile" element={<ProtectedRoute><Profile /></ProtectedRoute>} />
          <Route path="/bag" element={<ProtectedRoute><MyBag /></ProtectedRoute>} />
          <Route path="*" element={<Navigate to="/home" replace />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  )
}
