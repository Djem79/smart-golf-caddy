import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import type { AppUser } from '../types'

// `useProfile` is the only Firestore-touching dependency here — mock it so
// the test controls exactly what "the profile" resolves to, same approach
// Profile.test.tsx uses.
let mockProfile: { profile: AppUser | null; loading: boolean } = { profile: null, loading: true }
vi.mock('./useProfile', () => ({
  useProfile: () => mockProfile,
}))

import { useLocaleSync } from './useLocaleSync'
import { useT, setLocale } from '../i18n'

function Probe() {
  useLocaleSync()
  const { locale } = useT()
  return <p data-testid="locale">{locale}</p>
}

beforeEach(() => {
  mockProfile = { profile: null, loading: true }
  // jsdom defaults navigator.language to 'en-US' → system default is 'en'.
  // Reset to a known state before each test regardless of prior mutation.
  act(() => setLocale('en'))
})

describe('useLocaleSync', () => {
  it('does nothing while the profile is still loading (keeps the system default)', () => {
    mockProfile = { profile: null, loading: true }
    render(<Probe />)
    expect(screen.getByTestId('locale').textContent).toBe('en')
  })

  it('a saved profile locale overrides the system default', async () => {
    mockProfile = { profile: { uid: 'u1', name: '', avatar: '', handicap: 0, locale: 'ru' }, loading: false }
    render(<Probe />)
    await waitFor(() => expect(screen.getByTestId('locale').textContent).toBe('ru'))
  })

  it('a profile with no locale field falls back to the system default', async () => {
    mockProfile = { profile: { uid: 'u1', name: '', avatar: '', handicap: 0 }, loading: false }
    render(<Probe />)
    // No override fires — stays whatever setLocale left it at (system 'en' from beforeEach).
    await waitFor(() => expect(screen.getByTestId('locale').textContent).toBe('en'))
  })

  it('signing out (profile resolves to null) resets to the system default, not a stale saved locale', async () => {
    mockProfile = { profile: { uid: 'u1', name: '', avatar: '', handicap: 0, locale: 'ru' }, loading: false }
    const { rerender } = render(<Probe />)
    await waitFor(() => expect(screen.getByTestId('locale').textContent).toBe('ru'))

    mockProfile = { profile: null, loading: false }
    rerender(<Probe />)
    await waitFor(() => expect(screen.getByTestId('locale').textContent).toBe('en'))
  })
})
