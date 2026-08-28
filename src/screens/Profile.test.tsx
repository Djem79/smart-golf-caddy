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

import { Profile } from './Profile'

function renderProfile() {
  return render(
    <MemoryRouter>
      <Profile />
    </MemoryRouter>,
  )
}

beforeEach(() => {
  vi.clearAllMocks()
})

describe('Profile — account deletion', () => {
  it('shows a visible "Удалить аккаунт" button', () => {
    renderProfile()
    expect(screen.getByRole('button', { name: /удалить аккаунт/i })).toBeInTheDocument()
  })

  it('clicking the button opens a confirmation dialog without calling deleteAccount yet', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: /удалить аккаунт/i }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(deleteAccountMock).not.toHaveBeenCalled()
  })

  it('cancelling the dialog does not call deleteAccount', () => {
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: /удалить аккаунт/i }))
    fireEvent.click(screen.getByRole('button', { name: /отмена/i }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(deleteAccountMock).not.toHaveBeenCalled()
  })

  it('on confirm: calls the callable, then signs out and redirects to /auth', async () => {
    deleteAccountMock.mockResolvedValueOnce(undefined)
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: /удалить аккаунт/i }))
    // Dialog's confirm button label is exactly "Удалить" (distinct from the
    // trigger button's "Удалить аккаунт").
    fireEvent.click(screen.getByRole('button', { name: /^удалить$/i }))

    await waitFor(() => expect(deleteAccountMock).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(signOutMock).toHaveBeenCalledTimes(1))
    await waitFor(() =>
      expect(navigateMock).toHaveBeenCalledWith('/auth', { replace: true }),
    )
  })

  it('on error: does not sign out or navigate, and shows an error message', async () => {
    deleteAccountMock.mockRejectedValueOnce(new Error('network down'))
    renderProfile()
    fireEvent.click(screen.getByRole('button', { name: /удалить аккаунт/i }))
    fireEvent.click(screen.getByRole('button', { name: /^удалить$/i }))

    await waitFor(() => expect(deleteAccountMock).toHaveBeenCalledTimes(1))
    expect(await screen.findByText(/не удалось удалить аккаунт/i)).toBeInTheDocument()
    expect(signOutMock).not.toHaveBeenCalled()
    expect(navigateMock).not.toHaveBeenCalledWith('/auth', { replace: true })
    // The account button is usable again — user is still logged in and can retry.
    expect(screen.getByRole('button', { name: /удалить аккаунт/i })).not.toBeDisabled()
  })
})
