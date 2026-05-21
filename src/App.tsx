import { lazy, Suspense } from 'react'
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { Auth } from './screens/Auth'
import { Home } from './screens/Home'

// Lazy-load heavier / less-immediate screens. Each becomes its own chunk;
// the initial bundle only ships Auth + Home + shared infra.
const CourseSearch = lazy(() => import('./screens/CourseSearch').then(m => ({ default: m.CourseSearch })))
const RoundSetup   = lazy(() => import('./screens/RoundSetup').then(m => ({ default: m.RoundSetup })))
const HoleTracker  = lazy(() => import('./screens/HoleTracker').then(m => ({ default: m.HoleTracker })))
const RoundResults = lazy(() => import('./screens/RoundResults').then(m => ({ default: m.RoundResults })))
const History      = lazy(() => import('./screens/History').then(m => ({ default: m.History })))
const Profile      = lazy(() => import('./screens/Profile').then(m => ({ default: m.Profile })))
const MyBag        = lazy(() => import('./screens/MyBag').then(m => ({ default: m.MyBag })))
const JoinGame     = lazy(() => import('./screens/JoinGame').then(m => ({ default: m.JoinGame })))
const GroupLobby   = lazy(() => import('./screens/GroupLobby').then(m => ({ default: m.GroupLobby })))
const Leaderboard  = lazy(() => import('./screens/Leaderboard').then(m => ({ default: m.Leaderboard })))

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
