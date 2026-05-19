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
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset cached profile when the auth user transitions to null; this is the only place these states converge
      setProfile(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const unsub = subscribeToProfile(user.uid, (p) => {
      // Snapshot callback fires asynchronously from Firestore, not inside the effect body — these setStates are fine.
      setProfile(p)
      setLoading(false)
    })
    return unsub
  }, [user])

  return { profile, loading }
}
