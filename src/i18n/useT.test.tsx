import { describe, it, expect } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { useT, setLocale } from './index'

function Probe() {
  const { t, locale } = useT()
  return <p data-testid="probe">{locale}:{t.home.welcome}</p>
}

describe('useT', () => {
  it('re-renders subscribed components when setLocale changes the language, no reload required', () => {
    render(<Probe />)

    act(() => setLocale('en'))
    expect(screen.getByTestId('probe').textContent).toBe('en:Welcome')

    act(() => setLocale('ru'))
    expect(screen.getByTestId('probe').textContent).toBe('ru:Добро пожаловать')
  })
})
