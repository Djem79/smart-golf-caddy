import { useEffect, useState } from 'react'
import { subscribeToAuth, type AuthUser } from '../services/auth'

export interface AuthState {
  user: AuthUser | null
  loading: boolean
}

export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>({ user: null, loading: true })

  useEffect(() => {
    return subscribeToAuth((user) => {
      setState({ user, loading: false })
    })
  }, [])

  return state
}
