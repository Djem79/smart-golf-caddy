/// <reference types="vitest" />
import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// Build-time release identifier for Sentry. Prefer an explicit env override
// (set by CI), else `<pkgVersion>+<gitShortSha>`, else just the package
// version. Without this, Sentry tags every event `unversioned`, defeating
// release-based regression tracking.
function resolveAppVersion(): string {
  if (process.env.VITE_APP_VERSION) return process.env.VITE_APP_VERSION
  const { version } = JSON.parse(
    readFileSync(new URL('./package.json', import.meta.url), 'utf-8'),
  ) as { version: string }
  try {
    const sha = execSync('git rev-parse --short HEAD', {
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .toString()
      .trim()
    return `${version}+${sha}`
  } catch {
    return version
  }
}

export default defineConfig({
  define: {
    'import.meta.env.VITE_APP_VERSION': JSON.stringify(resolveAppVersion()),
  },
  plugins: [
    react(),
    VitePWA({
      // Auto-update SW when a new version is deployed, no user prompt needed.
      // Combined with our hosting cache headers (long-cache for hashed assets,
      // no-cache for manifest/index.html) this gives reliable updates.
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      // We already maintain our own public/manifest.json — let it stay.
      manifest: false,
      // Precache the built app shell so first-paint works offline once the
      // service worker has run at least once.
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,webp,woff2}'],
        // Don't precache map photos or Google API responses — those go through
        // runtime cache below.
        navigateFallback: '/index.html',
        runtimeCaching: [
          {
            // Google Place Photos — short cache, network-first.
            urlPattern: /^https:\/\/places\.googleapis\.com\/v1\/places\/[^/]+\/photos\/[^/]+\/media\?/,
            handler: 'CacheFirst',
            options: {
              cacheName: 'place-photos',
              expiration: { maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 7 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
          {
            // Fonts (Google Fonts CSS + woff2)
            urlPattern: /^https:\/\/fonts\.(googleapis|gstatic)\.com\/.*/,
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'google-fonts',
              expiration: { maxEntries: 30, maxAgeSeconds: 60 * 60 * 24 * 30 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
        ],
      },
      devOptions: {
        // Enable the SW in `npm run dev` for easier testing; harmless in prod.
        enabled: false,
      },
    }),
  ],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
    // The Firestore rules test is a standalone emulator script (run via
    // `npm run test:rules`), not a jsdom unit test — keep vitest from picking
    // it up by its .test.mjs name.
    exclude: ['**/node_modules/**', '**/dist/**', 'firestore.rules.test.mjs'],
  },
})
