import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// `useNavigate` is spied while the rest of react-router-dom (MemoryRouter,
// NavLink used by BottomNav, Link used by PageHeader's back button) stays
// real — same approach as mocking a service boundary, applied to routing.
const navigateMock = vi.fn()
vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>()
  return { ...actual, useNavigate: () => navigateMock }
})

const mockUser = {
  uid: 'u1',
  displayName: 'Тест Тестов',
  email: 't@example.com',
  photoURL: null,
}

vi.mock('../hooks/useAuth', () => ({
  useAuth: () => ({ user: mockUser, loading: false }),
}))
vi.mock('../hooks/useProfile', () => ({
  useProfile: () => ({ profile: null, loading: false }),
}))

const signOutMock = vi.fn(async () => {})
vi.mock('../services/auth', () => ({
  signOut: () => signOutMock(),
}))

vi.mock('../services/rounds', () => ({
  getUserRounds: vi.fn(async () => []),
}))

const deleteAccountMock = vi.fn()
vi.mock('../services/account', () => ({
  deleteAccount: () => deleteAccountMock(),
}))

const updateLocaleMock = vi.fn()
vi.mock('../services/users', () => ({
  updateLocale: (...args: unknown[]) => updateLocaleMock(...args),
}))

import { Profile } from './Profile'
import { en } from '../i18n/en'
import { ru } from '../i18n/ru'
import { setLocale } from '../i18n'

// jsdom's default navigator.language is 'en-US', so useT() resolves to the
// English dictionary in tests (no locale override here — T3 adds the
// language switcher). Building selectors from the dictionary keeps this
// test correct if the copy changes, instead of hardcoding English strings.
const t = en.profile

function renderProfile() {
  return render(
    <MemoryRouter>
      <Profile />
    </MemoryRouter>,
  )
}

beforeEach(() => {
  vi.clearAllMocks()
  setLocale('en') // jsdom's system default — reset between tests since setLocale is a module-level singleton
})

describe('Profile — account deletion', () => {
  it('shows a visible "Delete account" button', () => {
    renderProfile()
    expect(screen.getByRole('button', { name: t.deleteAccount })).toBeInTheDocument()
  })

  it('clicking the button opens a confirmation dialog without calling deleteAccount yet', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: t.deleteAccount }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(deleteAccountMock).not.toHaveBeenCalled()
  })

  it('cancelling the dialog does not call deleteAccount', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: t.deleteAccount }))
    fireEvent.click(screen.getByRole('button', { name: en.common.cancel }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(deleteAccountMock).not.toHaveBeenCalled()
  })

  it('on confirm: calls the callable, then signs out and redirects to /auth', async () => {
    deleteAccountMock.mockResolvedValueOnce(undefined)
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: t.deleteAccount }))
    // Dialog's confirm button label is exactly "Delete" (distinct from the
    // trigger button's "Delete account").
    fireEvent.click(screen.getByRole('button', { name: t.delete }))

    await waitFor(() => expect(deleteAccountMock).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(signOutMock).toHaveBeenCalledTimes(1))
    await waitFor(() =>
      expect(navigateMock).toHaveBeenCalledWith('/auth', { replace: true }),
    )
  })

  it('on error: does not sign out or navigate, and shows an error message', async () => {
    deleteAccountMock.mockRejectedValueOnce(new Error('network down'))
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: t.deleteAccount }))
    fireEvent.click(screen.getByRole('button', { name: t.delete }))

    await waitFor(() => expect(deleteAccountMock).toHaveBeenCalledTimes(1))
    expect(await screen.findByText(t.deleteAccountError)).toBeInTheDocument()
    expect(signOutMock).not.toHaveBeenCalled()
    expect(navigateMock).not.toHaveBeenCalledWith('/auth', { replace: true })
    // The account button is usable again — user is still logged in and can retry.
    expect(screen.getByRole('button', { name: t.deleteAccount })).not.toBeDisabled()
  })
})

describe('Profile — language switcher', () => {
  it('labels the two options in their own language, not translated', () => {
    renderProfile()
    expect(screen.getByRole('button', { name: 'Русский' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'English' })).toBeInTheDocument()
  })

  it('clicking a language switches the UI immediately, without a reload', () => {
    renderProfile()
    // Page title (<h1>, from PageHeader) — a unique heading, unlike "Profile"
    // as plain text, which also appears in BottomNav's own label.
    expect(screen.getByRole('heading', { name: en.profile.title })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Русский' }))

    expect(screen.getByRole('heading', { name: ru.profile.title })).toBeInTheDocument()
  })

  it('persists the choice to the profile', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: 'Русский' }))
    expect(updateLocaleMock).toHaveBeenCalledWith('u1', 'ru')
  })

  it('clicking the already-active language is a no-op (no redundant write)', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: 'English' })) // already en
    expect(updateLocaleMock).not.toHaveBeenCalled()
  })
})
