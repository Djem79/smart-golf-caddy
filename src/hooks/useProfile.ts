import { useEffect, useState } from 'react'
import { useAuth } from './useAuth'
import { subscribeToProfile } from '../services/users'
import type { AppUser } from '../types'

export interface ProfileState {
  profile: AppUser | null
  loading: boolean
}

export function useProfile(): ProfileState {
  const { user } = useAuth()
  const [profile, setProfile] = useState<AppUser | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!user) {
      setProfile(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const unsub = subscribeToProfile(user.uid, (p) => {
      setProfile(p)
      setLoading(false)
    })
    return unsub
  }, [user])

  return { profile, loading }
}
