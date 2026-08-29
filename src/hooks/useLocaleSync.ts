import { useEffect } from 'react'
import { useProfile } from './useProfile'
import { setLocale, detectSystemLocale } from '../i18n'

// T3: mounted once at the app root (see App.tsx) so there's a single
// subscription for the whole session. `src/i18n/index.ts` already renders
// the first frame in the system language (computed at module load, before
// any auth/profile round-trip), so there's nothing to gate on here — once
// the profile resolves, this just calls `setLocale`, which re-renders every
// subscribed component (via `useT`) in place. No remount, no full-screen
// loading state, so a saved locale that differs from the system default
// reads as an instant text swap rather than a flash.
//
// Signed-out (or not-yet-loaded) state resolves `profile` to `null` — once
// `loading` clears, that falls back to the system locale too, so a previous
// user's saved language never leaks into the next sign-in.
export function useLocaleSync(): void {
  const { profile, loading } = useProfile()

  useEffect(() => {
    if (loading) return
    setLocale(profile?.locale ?? detectSystemLocale())
  }, [profile, loading])
}
