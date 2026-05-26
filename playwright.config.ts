import { defineConfig, devices } from '@playwright/test'

// First-pass e2e: an unauthenticated smoke that runs against a built
// `vite preview` server. Auth/Firestore live behind real Firebase, so the
// authenticated solo-round flow needs the Firebase emulator suite — wire
// that up as a second project once we add auth stubs.
export default defineConfig({
  testDir: './e2e',
  // 30s per test is plenty for a smoke; long timeouts mask real hangs.
  timeout: 30_000,
  // No retries — a flaky smoke is a broken smoke. Surface flakes loudly.
  retries: 0,
  // Run serial in CI so a failure produces clean output; parallel locally.
  fullyParallel: !process.env.CI,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  use: {
    baseURL: 'http://localhost:4173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  // Launch `vite preview` against the built bundle. CI builds first via the
  // dedicated `Build (with placeholder env)` step in ci.yml.
  webServer: {
    command: 'npm run preview -- --port 4173 --strictPort',
    url: 'http://localhost:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
  projects: [
    {
      name: 'mobile-chromium',
      // Pixel 7 is close to our 390px-wide target viewport without forcing
      // the exact width — that way we exercise the .screen utility's
      // `max-w-[390px] mx-auto` centring behaviour.
      use: { ...devices['Pixel 7'] },
    },
  ],
})
