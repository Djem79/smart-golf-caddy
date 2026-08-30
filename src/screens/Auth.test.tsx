import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

const navigateMock = vi.fn()
vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>()
  return { ...actual, useNavigate: () => navigateMock }
})

const signInWithGoogleMock = vi.fn(async () => {})
const signInWithAppleMock = vi.fn<(locale?: string) => Promise<void>>(async () => {})
vi.mock('../services/auth', () => ({
  signInWithGoogle: () => signInWithGoogleMock(),
  signInWithApple: (locale?: string) => signInWithAppleMock(locale),
  authErrorCode: (e: unknown) =>
    e && typeof e === 'object' && 'code' in e ? String((e as { code: unknown }).code) : '',
  isPopupCancelled: (e: unknown) => {
    const code = e && typeof e === 'object' && 'code' in e ? String((e as { code: unknown }).code) : ''
    return code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request' || code === 'auth/user-cancelled'
  },
}))

import { Auth } from './Auth'
import { en } from '../i18n/en'
import { ru } from '../i18n/ru'
import { setLocale } from '../i18n'

function firebaseError(code: string) {
  return Object.assign(new Error(code), { code })
}

function renderAuth() {
  return render(
    <MemoryRouter>
      <Auth />
    </MemoryRouter>,
  )
}

beforeEach(() => {
  vi.clearAllMocks()
  setLocale('en')
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('Auth — Sign in with Apple (App Store 4.8)', () => {
  it('offers Apple next to Google, both as real buttons', () => {
    renderAuth()
    expect(screen.getByRole('button', { name: en.auth.signInWithGoogle })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: en.auth.signInWithApple })).toBeInTheDocument()
  })

  it("uses Apple's official Russian title, not a home-grown translation", () => {
    setLocale('ru')
    renderAuth()
    expect(screen.getByRole('button', { name: 'Вход с Apple' })).toBeInTheDocument()
    expect(ru.auth.signInWithApple).toBe('Вход с Apple')
  })

  it('passes the active UI locale to Apple so its consent screen matches', async () => {
    setLocale('ru')
    renderAuth()
    fireEvent.click(screen.getByRole('button', { name: ru.auth.signInWithApple }))
    await waitFor(() => expect(signInWithAppleMock).toHaveBeenCalledWith('ru'))
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/home', { replace: true }))
  })

  it('explains the account-linking step when the email is already registered via Google', async () => {
    signInWithAppleMock.mockRejectedValueOnce(firebaseError('auth/account-exists-with-different-credential'))
    renderAuth()
    fireEvent.click(screen.getByRole('button', { name: en.auth.signInWithApple }))
    expect(await screen.findByRole('alert')).toHaveTextContent(en.auth.errors.accountExists)
    expect(navigateMock).not.toHaveBeenCalled()
    // Both buttons are usable again — the recovery is "now sign in with Google".
    expect(screen.getByRole('button', { name: en.auth.signInWithGoogle })).not.toBeDisabled()
  })

  it('a closed popup is silent — no error, no navigation', async () => {
    signInWithAppleMock.mockRejectedValueOnce(firebaseError('auth/popup-closed-by-user'))
    renderAuth()
    fireEvent.click(screen.getByRole('button', { name: en.auth.signInWithApple }))
    await waitFor(() => expect(signInWithAppleMock).toHaveBeenCalledTimes(1))
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(navigateMock).not.toHaveBeenCalled()
  })

  it('disables both buttons while either sign-in is in flight', async () => {
    let resolve!: () => void
    signInWithAppleMock.mockImplementationOnce(() => new Promise<void>(r => { resolve = r }))
    renderAuth()
    fireEvent.click(screen.getByRole('button', { name: en.auth.signInWithApple }))
    expect(screen.getByRole('button', { name: en.auth.signInWithGoogle })).toBeDisabled()
    expect(screen.getByRole('button', { name: en.auth.signingIn })).toBeDisabled()
    resolve()
    await waitFor(() => expect(navigateMock).toHaveBeenCalled())
  })

  it('Google sign-in still works and returns to the deep-link origin', async () => {
    render(
      <MemoryRouter initialEntries={[{ pathname: '/auth', state: { from: '/join/ABC123' } }]}>
        <Auth />
      </MemoryRouter>,
    )
    fireEvent.click(screen.getByRole('button', { name: en.auth.signInWithGoogle }))
    await waitFor(() => expect(signInWithGoogleMock).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/join/ABC123', { replace: true }))
  })
})
