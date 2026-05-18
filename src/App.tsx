import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { Auth } from './screens/Auth'
import { Home } from './screens/Home'
import { CourseSearch } from './screens/CourseSearch'
import { RoundSetup } from './screens/RoundSetup'
import { HoleTracker } from './screens/HoleTracker'
import { RoundResults } from './screens/RoundResults'
import { History } from './screens/History'
import { Profile } from './screens/Profile'
import { MyBag } from './screens/MyBag'
import { JoinGame } from './screens/JoinGame'
import { GroupLobby } from './screens/GroupLobby'

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return (
    <div className="screen items-center justify-center">
      <div className="text-on-surface-variant text-body-md">Загрузка...</div>
    </div>
  )
  if (!user) return <Navigate to="/auth" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/auth" element={<Auth />} />
        <Route path="/" element={<Navigate to="/home" replace />} />
        <Route path="/home" element={<ProtectedRoute><Home /></ProtectedRoute>} />
        <Route path="/courses" element={<ProtectedRoute><CourseSearch /></ProtectedRoute>} />
        <Route path="/round/setup" element={<ProtectedRoute><RoundSetup /></ProtectedRoute>} />
        <Route path="/round/:roundId/lobby" element={<ProtectedRoute><GroupLobby /></ProtectedRoute>} />
        <Route path="/round/:roundId/hole/:holeNumber" element={<ProtectedRoute><HoleTracker /></ProtectedRoute>} />
        <Route path="/round/:roundId/results" element={<ProtectedRoute><RoundResults /></ProtectedRoute>} />
        <Route path="/join" element={<ProtectedRoute><JoinGame /></ProtectedRoute>} />
        <Route path="/join/:code" element={<ProtectedRoute><JoinGame /></ProtectedRoute>} />
        <Route path="/history" element={<ProtectedRoute><History /></ProtectedRoute>} />
        <Route path="/profile" element={<ProtectedRoute><Profile /></ProtectedRoute>} />
        <Route path="/bag" element={<ProtectedRoute><MyBag /></ProtectedRoute>} />
        <Route path="*" element={<Navigate to="/home" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
