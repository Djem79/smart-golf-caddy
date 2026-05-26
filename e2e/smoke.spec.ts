import { test, expect } from '@playwright/test'

// Unauthenticated smoke. Catches build/deploy regressions, broken routes,
// stale-chunk handling, and ProtectedRoute redirects — the cheapest layer
// of defence-in-depth before push. The authenticated solo-round flow needs
// Firebase emulator wiring and is deferred to a follow-up project.

test.describe('app smoke (unauthenticated)', () => {
  test('root redirects to /auth', async ({ page }) => {
    await page.goto('/')
    // Home is gated by <ProtectedRoute>, so an unauthenticated visit lands
    // on /auth and preserves the original path in router state.
    await expect(page).toHaveURL(/\/auth$/)
  })

  test('/auth shows Google sign-in button', async ({ page }) => {
    await page.goto('/auth')
    await expect(page.getByRole('button', { name: /Войти через Google/i })).toBeVisible()
  })

  test('protected route /home redirects to /auth', async ({ page }) => {
    await page.goto('/home')
    await expect(page).toHaveURL(/\/auth$/)
  })

  test('protected deep link /round/abc/results redirects to /auth', async ({ page }) => {
    await page.goto('/round/abc/results')
    await expect(page).toHaveURL(/\/auth$/)
  })

  test('no console errors on /auth load', async ({ page }) => {
    // Drop predictable Firebase placeholder warnings from the noise floor.
    // Real bugs surface as either uncaught errors or non-Firebase warnings.
    const errors: string[] = []
    page.on('pageerror', e => errors.push(`pageerror: ${e.message}`))
    page.on('console', m => {
      if (m.type() !== 'error') return
      const text = m.text()
      // Placeholder Firebase config produces a known auth/api-key error in
      // preview builds — we don't deploy with these, but CI uses them so
      // the build can compile. Filter to keep the smoke green.
      if (text.includes('auth/invalid-api-key')) return
      if (text.includes('Firebase: Error')) return
      errors.push(`console.error: ${text}`)
    })
    await page.goto('/auth')
    await expect(page.getByRole('button', { name: /Войти через Google/i })).toBeVisible()
    expect(errors).toEqual([])
  })
})
