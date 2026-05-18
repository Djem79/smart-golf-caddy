# Smart Golf Caddy — Plan 1: Foundation + Solo Game Loop

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully working React PWA for solo golf round tracking — Google auth, course discovery via geolocation, hole-by-hole shot recording with club selection, GPS distance to course, and a visually attractive round results screen.

**Architecture:** Vite + React 18 + TypeScript SPA. Firestore stores rounds and user profiles. Firebase Auth handles Google Sign-In. Google Places API discovers nearby courses. All screens are mobile-first (390px), following the Fairway Elite design system extracted from Stitch.

**Tech Stack:** React 18, TypeScript 5, Vite 5, Tailwind CSS 3, React Router 6, Zustand 4, Firebase 10 (modular SDK), Vitest + @testing-library/react, date-fns 3

> **Note:** This is Plan 1 of 2. Plan 2 adds group play (QR lobby, real-time Firestore listeners), profile screen, club bag customization, and WHS handicap calculation.

---

## File Structure

```
smart-golf-caddy/
├── index.html
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── package.json
├── firebase.json                          # Firebase Hosting config
├── .env.example
├── .env.local                             # Never committed
├── public/
│   ├── manifest.json                      # PWA manifest
│   └── icon-192.png / icon-512.png        # App icons (placeholder PNGs)
└── src/
    ├── main.tsx                           # Entry point
    ├── App.tsx                            # Router + auth guard
    ├── test-setup.ts                      # Vitest + @testing-library setup
    ├── firebase.ts                        # Firebase SDK init (auth + db)
    ├── types/
    │   └── index.ts                       # All TS interfaces + constants + score helpers
    ├── styles/
    │   └── index.css                      # Tailwind directives + Google Fonts
    ├── services/
    │   ├── auth.ts                        # signInWithGoogle, signOut, getUserProfile
    │   ├── courses.ts                     # Google Places nearby search → CourseResult[]
    │   ├── rounds.ts                      # Firestore CRUD: createRound, recordShot, finishRound, getUserRounds
    │   └── distance.ts                    # Haversine formula → metres between two coords
    ├── hooks/
    │   ├── useAuth.ts                     # Firebase onAuthStateChanged observer → { user, loading }
    │   └── useGeolocation.ts             # navigator.geolocation.watchPosition → { lat, lng, error }
    ├── store/
    │   └── useAppStore.ts                 # Zustand: activeRound, currentHoleIndex, lastClubUsed
    ├── components/
    │   ├── ui/
    │   │   ├── Button.tsx                 # variant: primary | secondary | ghost
    │   │   ├── Card.tsx                   # Surface card with Fairway Elite shadow + border
    │   │   ├── ScoreChip.tsx              # Coloured badge: Eagle/Birdie/Par/Bogey
    │   │   └── ClubChip.tsx              # Selectable pill for club selector row
    │   └── layout/
    │       ├── BottomNav.tsx              # Home / History / Profile tabs
    │       └── PageHeader.tsx             # Back button + title bar
    └── screens/
        ├── Auth.tsx                       # Google Sign-In full-screen
        ├── Home.tsx                       # "Start Round" CTA + recent 3 rounds
        ├── CourseSearch.tsx               # Geolocation + nearby courses list
        ├── RoundSetup.tsx                 # 9 or 18 holes toggle → createRound → navigate
        ├── HoleTracker.tsx                # Shot counter + club chips + GPS badge + prev/next nav
        ├── RoundResults.tsx               # Scorecard grid + colour coding + share button
        └── History.tsx                    # All finished rounds, newest first
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `package.json` (via Vite scaffold)
- Create: `vite.config.ts`
- Create: `tsconfig.json`
- Create: `tailwind.config.ts`
- Create: `index.html`
- Create: `src/main.tsx`
- Create: `src/test-setup.ts`
- Create: `.env.example`
- Create: `.gitignore` entry

- [ ] **Step 1: Scaffold Vite project**

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
npm create vite@latest . -- --template react-ts
```

Answer `y` if prompted about overwriting existing files.

- [ ] **Step 2: Install all dependencies**

```bash
npm install
npm install react-router-dom@6 zustand@4 firebase@10 date-fns@3
npm install -D tailwindcss@3 postcss autoprefixer \
  @testing-library/react @testing-library/jest-dom \
  @testing-library/user-event vitest jsdom @vitejs/plugin-react
npx tailwindcss init -p
```

- [ ] **Step 3: Configure Vite with Vitest**

Replace the full contents of `vite.config.ts`:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
  },
})
```

- [ ] **Step 4: Create Vitest setup file**

Create `src/test-setup.ts`:

```typescript
import '@testing-library/jest-dom'
```

- [ ] **Step 5: Update tsconfig.json**

Replace the full contents of `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

- [ ] **Step 6: Add test script to package.json**

In `package.json`, add to `"scripts"` object:

```json
"test": "vitest",
"test:run": "vitest run"
```

- [ ] **Step 7: Create .env.example**

Create `.env.example`:

```
VITE_FIREBASE_API_KEY=
VITE_FIREBASE_AUTH_DOMAIN=
VITE_FIREBASE_PROJECT_ID=
VITE_FIREBASE_STORAGE_BUCKET=
VITE_FIREBASE_MESSAGING_SENDER_ID=
VITE_FIREBASE_APP_ID=
VITE_GOOGLE_PLACES_API_KEY=
```

Also create `.env.local` with your actual Firebase and Google Places values (never commit this file).

- [ ] **Step 8: Add .env.local to .gitignore**

Append to `.gitignore`:

```
.env.local
.env.*.local
```

- [ ] **Step 9: Verify scaffold**

```bash
npm run dev
```

Expected: Vite dev server starts on http://localhost:5173. Open in browser — default React page renders.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: scaffold React + Vite + TypeScript + Tailwind project

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Fairway Elite Design System (Tailwind)

**Files:**
- Modify: `tailwind.config.ts`
- Create: `src/styles/index.css`
- Modify: `src/main.tsx`

- [ ] **Step 1: Configure Tailwind with Fairway Elite tokens**

Replace the full contents of `tailwind.config.ts`:

```typescript
import type { Config } from 'tailwindcss'

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#00450D',
        'primary-container': '#1B5E20',
        'on-primary': '#FFFFFF',
        'inverse-primary': '#91D78A',
        secondary: '#5E604D',
        'secondary-container': '#E1E1C9',
        'on-secondary': '#FFFFFF',
        tertiary: '#2D3D45',
        'tertiary-container': '#44545C',
        'on-tertiary': '#FFFFFF',
        surface: '#F9F9F9',
        'surface-dim': '#DADADA',
        'surface-container-lowest': '#FFFFFF',
        'surface-container-low': '#F3F3F4',
        'surface-container': '#EEEEEE',
        'surface-container-high': '#E8E8E8',
        'on-surface': '#1A1C1C',
        'on-surface-variant': '#41493E',
        outline: '#717A6D',
        'outline-variant': '#C0C9BB',
        error: '#BA1A1A',
        'error-container': '#FFDAD6',
        'on-error': '#FFFFFF',
      },
      fontFamily: {
        headline: ['Montserrat', 'sans-serif'],
        body: ['Inter', 'sans-serif'],
      },
      fontSize: {
        'display-lg': ['40px', { lineHeight: '48px', letterSpacing: '-0.02em', fontWeight: '700' }],
        'headline-lg': ['32px', { lineHeight: '40px', letterSpacing: '-0.01em', fontWeight: '700' }],
        'headline-md': ['24px', { lineHeight: '32px', fontWeight: '600' }],
        'title-lg': ['20px', { lineHeight: '28px', fontWeight: '600' }],
        'body-md': ['16px', { lineHeight: '24px', fontWeight: '400' }],
        'label-lg': ['14px', { lineHeight: '20px', letterSpacing: '0.05em', fontWeight: '600' }],
        'label-md': ['12px', { lineHeight: '16px', fontWeight: '500' }],
      },
      borderRadius: {
        DEFAULT: '0.5rem',
        sm: '0.25rem',
        md: '0.75rem',
        lg: '1rem',
        xl: '1.5rem',
      },
      boxShadow: {
        card: '0px 4px 12px rgba(55, 71, 79, 0.05)',
      },
      minHeight: {
        touch: '48px',
      },
      minWidth: {
        touch: '48px',
      },
    },
  },
  plugins: [],
} satisfies Config
```

- [ ] **Step 2: Create global CSS**

Create `src/styles/index.css`:

```css
@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700&family=Inter:wght@400;500;600&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  body {
    @apply bg-surface font-body text-on-surface;
    -webkit-tap-highlight-color: transparent;
    overscroll-behavior: none;
  }
  * {
    box-sizing: border-box;
  }
}

@layer components {
  .card {
    @apply bg-surface-container-lowest rounded-lg shadow-card border border-outline-variant/20 p-5;
  }
  .btn-primary {
    @apply bg-primary text-on-primary font-headline font-semibold text-label-lg rounded
           px-6 min-h-touch w-full flex items-center justify-center
           active:scale-[0.98] transition-transform disabled:opacity-40;
  }
  .btn-secondary {
    @apply border border-outline text-on-surface font-headline font-semibold text-label-lg rounded
           px-6 min-h-touch w-full flex items-center justify-center
           active:scale-[0.98] transition-transform disabled:opacity-40;
  }
  .screen {
    @apply min-h-screen flex flex-col bg-surface max-w-[390px] mx-auto;
  }
}
```

- [ ] **Step 3: Update main.tsx**

Replace `src/main.tsx`:

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/index.css'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
```

- [ ] **Step 4: Verify styles load**

```bash
npm run dev
```

Open http://localhost:5173. Background should be `#F9F9F9` (warm light grey), not white. No console errors.

- [ ] **Step 5: Commit**

```bash
git add tailwind.config.ts src/styles/ src/main.tsx
git commit -m "feat: add Fairway Elite design system to Tailwind config

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: TypeScript Types + Score Helpers

**Files:**
- Create: `src/types/index.ts`
- Test: `src/types/index.test.ts`

- [ ] **Step 1: Write failing tests for score helpers**

Create `src/types/index.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { scoreColor, scoreLabel, DEFAULT_CLUBS, CLUB_ABBREV, DEFAULT_HOLE_PARS } from './index'

describe('scoreColor', () => {
  it('returns gold (#FFD700) for eagle (-2)', () => {
    expect(scoreColor(-2)).toBe('#FFD700')
  })
  it('returns gold for albatross (-3)', () => {
    expect(scoreColor(-3)).toBe('#FFD700')
  })
  it('returns green (#4CAF50) for birdie (-1)', () => {
    expect(scoreColor(-1)).toBe('#4CAF50')
  })
  it('returns white (#FFFFFF) for par (0)', () => {
    expect(scoreColor(0)).toBe('#FFFFFF')
  })
  it('returns orange (#FF9800) for bogey (+1)', () => {
    expect(scoreColor(1)).toBe('#FF9800')
  })
  it('returns red (#F44336) for double bogey (+2)', () => {
    expect(scoreColor(2)).toBe('#F44336')
  })
  it('returns red for triple bogey (+3)', () => {
    expect(scoreColor(3)).toBe('#F44336')
  })
})

describe('scoreLabel', () => {
  it('returns "Eagle" for -2', () => expect(scoreLabel(-2)).toBe('Eagle'))
  it('returns "Eagle" for -3 (albatross shown as Eagle)', () => expect(scoreLabel(-3)).toBe('Eagle'))
  it('returns "Birdie" for -1', () => expect(scoreLabel(-1)).toBe('Birdie'))
  it('returns "Par" for 0', () => expect(scoreLabel(0)).toBe('Par'))
  it('returns "Bogey" for +1', () => expect(scoreLabel(1)).toBe('Bogey'))
  it('returns "Double" for +2', () => expect(scoreLabel(2)).toBe('Double'))
  it('returns "+5" for 5', () => expect(scoreLabel(5)).toBe('+5'))
})

describe('DEFAULT_CLUBS', () => {
  it('contains Putter', () => expect(DEFAULT_CLUBS).toContain('Putter'))
  it('contains Driver', () => expect(DEFAULT_CLUBS).toContain('Driver'))
  it('has 14 clubs', () => expect(DEFAULT_CLUBS).toHaveLength(14))
})

describe('CLUB_ABBREV', () => {
  it('has an abbreviation for every DEFAULT_CLUB', () => {
    for (const club of DEFAULT_CLUBS) {
      expect(CLUB_ABBREV).toHaveProperty(club)
    }
  })
})

describe('DEFAULT_HOLE_PARS', () => {
  it('has 9 holes for 9-hole config', () => expect(DEFAULT_HOLE_PARS[9]).toHaveLength(9))
  it('has 18 holes for 18-hole config', () => expect(DEFAULT_HOLE_PARS[18]).toHaveLength(18))
  it('all pars are 3, 4, or 5', () => {
    for (const par of [...DEFAULT_HOLE_PARS[9], ...DEFAULT_HOLE_PARS[18]]) {
      expect([3, 4, 5]).toContain(par)
    }
  })
})
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npm run test:run
```

Expected: `Cannot find module './index'` or similar import error.

- [ ] **Step 3: Create types/index.ts**

Create `src/types/index.ts`:

```typescript
// --- Interfaces ---

export interface AppUser {
  uid: string
  name: string
  avatar: string
  handicap: number
  clubs: string[]
}

export interface HoleShots {
  count: number
  club: string
  updatedAt: Date
}

export interface HoleConfig {
  holeNumber: number
  par: 3 | 4 | 5
  distanceMeters: number
  shots: Record<string, HoleShots>
}

export interface PlayerInfo {
  name: string
  avatar: string
  totalScore: number
  scoreDiff: number
}

export type RoundStatus = 'lobby' | 'active' | 'finished'

export interface Round {
  id: string
  courseId: string
  courseName: string
  totalHoles: 9 | 18
  lobbyCode: string
  status: RoundStatus
  hostId: string
  players: Record<string, PlayerInfo>
  holes: HoleConfig[]
  startedAt: Date
  finishedAt: Date | null
  createdAt: Date
}

export interface CourseResult {
  placeId: string
  name: string
  distanceKm: number
  vicinity: string
  location: { lat: number; lng: number }
}

// --- Constants ---

export const DEFAULT_CLUBS: string[] = [
  'Driver', '3W', '5W',
  '4i', '5i', '6i', '7i', '8i', '9i',
  'PW', 'GW', 'SW', 'LW',
  'Putter',
]

export const CLUB_ABBREV: Record<string, string> = {
  Driver: 'DRV', '3W': '3W', '5W': '5W',
  '4i': '4i', '5i': '5i', '6i': '6i', '7i': '7i', '8i': '8i', '9i': '9i',
  PW: 'PW', GW: 'GW', SW: 'SW', LW: 'LW', Putter: 'PT',
}

export const DEFAULT_HOLE_PARS: Record<9 | 18, (3 | 4 | 5)[]> = {
  9:  [4, 3, 5, 4, 4, 3, 5, 4, 4],
  18: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4],
}

// --- Score Helpers ---

export function scoreColor(delta: number): string {
  if (delta <= -2) return '#FFD700'  // eagle or better
  if (delta === -1) return '#4CAF50' // birdie
  if (delta === 0)  return '#FFFFFF' // par
  if (delta === 1)  return '#FF9800' // bogey
  return '#F44336'                   // double bogey+
}

export function scoreLabel(delta: number): string {
  if (delta <= -2) return 'Eagle'
  if (delta === -1) return 'Birdie'
  if (delta === 0)  return 'Par'
  if (delta === 1)  return 'Bogey'
  if (delta === 2)  return 'Double'
  return `+${delta}`
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npm run test:run
```

Expected: 19 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add src/types/
git commit -m "feat: add TypeScript types, constants, score color/label helpers

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: GPS Distance Service

**Files:**
- Create: `src/services/distance.ts`
- Test: `src/services/distance.test.ts`
- Create: `src/hooks/useGeolocation.ts`

- [ ] **Step 1: Write failing tests for Haversine**

Create `src/services/distance.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { haversineMetres } from './distance'

describe('haversineMetres', () => {
  it('returns 0 for identical coordinates', () => {
    expect(haversineMetres(55.751, 37.618, 55.751, 37.618)).toBe(0)
  })

  it('computes ~557 km between Moscow and St Petersburg', () => {
    // Moscow: 55.7558°N, 37.6176°E
    // St Pete: 59.9311°N, 30.3609°E
    const dist = haversineMetres(55.7558, 37.6176, 59.9311, 30.3609)
    expect(dist).toBeGreaterThan(630_000)
    expect(dist).toBeLessThan(680_000)
  })

  it('computes ~111 km for 1 degree of latitude', () => {
    const dist = haversineMetres(0, 0, 1, 0)
    expect(dist).toBeGreaterThan(110_000)
    expect(dist).toBeLessThan(112_000)
  })

  it('returns a positive number for any two different points', () => {
    expect(haversineMetres(51.5, -0.1, 48.8, 2.3)).toBeGreaterThan(0)
  })
})
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npm run test:run -- src/services/distance.test.ts
```

Expected: `Cannot find module './distance'`.

- [ ] **Step 3: Implement haversineMetres**

Create `src/services/distance.ts`:

```typescript
const EARTH_RADIUS_M = 6_371_000

function toRad(degrees: number): number {
  return (degrees * Math.PI) / 180
}

export function haversineMetres(
  lat1: number, lng1: number,
  lat2: number, lng2: number,
): number {
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npm run test:run -- src/services/distance.test.ts
```

Expected: 4 tests pass.

- [ ] **Step 5: Create useGeolocation hook**

Create `src/hooks/useGeolocation.ts`:

```typescript
import { useState, useEffect } from 'react'

export interface GeoState {
  lat: number | null
  lng: number | null
  error: string | null
  loading: boolean
}

export function useGeolocation(): GeoState {
  const [state, setState] = useState<GeoState>({
    lat: null, lng: null, error: null, loading: true,
  })

  useEffect(() => {
    if (!navigator.geolocation) {
      setState({ lat: null, lng: null, error: 'Геолокация не поддерживается', loading: false })
      return
    }
    const watchId = navigator.geolocation.watchPosition(
      ({ coords }) => setState({
        lat: coords.latitude,
        lng: coords.longitude,
        error: null,
        loading: false,
      }),
      (err) => setState({ lat: null, lng: null, error: err.message, loading: false }),
      { enableHighAccuracy: true, maximumAge: 5000 },
    )
    return () => navigator.geolocation.clearWatch(watchId)
  }, [])

  return state
}
```

- [ ] **Step 6: Commit**

```bash
git add src/services/distance.ts src/services/distance.test.ts src/hooks/useGeolocation.ts
git commit -m "feat: add Haversine distance service and useGeolocation hook

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Firebase Init + Auth Service

**Files:**
- Create: `src/firebase.ts`
- Create: `src/services/auth.ts`
- Create: `src/hooks/useAuth.ts`

- [ ] **Step 1: Create Firebase init**

Create `src/firebase.ts`:

```typescript
import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey:            import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain:        import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId:         import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket:     import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId:             import.meta.env.VITE_FIREBASE_APP_ID,
}

export const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app)
```

- [ ] **Step 2: Create auth service**

Create `src/services/auth.ts`:

```typescript
import { GoogleAuthProvider, signInWithPopup, signOut as fbSignOut } from 'firebase/auth'
import { doc, setDoc, getDoc, serverTimestamp } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { AppUser, DEFAULT_CLUBS } from '../types'

const googleProvider = new GoogleAuthProvider()

export async function signInWithGoogle(): Promise<void> {
  const { user } = await signInWithPopup(auth, googleProvider)
  const ref = doc(db, 'users', user.uid)
  const snap = await getDoc(ref)
  if (!snap.exists()) {
    await setDoc(ref, {
      name: user.displayName ?? 'Golfer',
      avatar: user.photoURL ?? '',
      handicap: 0,
      clubs: DEFAULT_CLUBS,
      createdAt: serverTimestamp(),
    })
  }
}

export async function signOut(): Promise<void> {
  await fbSignOut(auth)
}

export async function getUserProfile(uid: string): Promise<AppUser | null> {
  const snap = await getDoc(doc(db, 'users', uid))
  if (!snap.exists()) return null
  return { uid, ...snap.data() } as AppUser
}
```

- [ ] **Step 3: Create useAuth hook**

Create `src/hooks/useAuth.ts`:

```typescript
import { useEffect, useState } from 'react'
import { onAuthStateChanged, User } from 'firebase/auth'
import { auth } from '../firebase'

export interface AuthState {
  user: User | null
  loading: boolean
}

export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>({ user: null, loading: true })

  useEffect(() => {
    return onAuthStateChanged(auth, (user) => {
      setState({ user, loading: false })
    })
  }, [])

  return state
}
```

- [ ] **Step 4: Commit**

```bash
git add src/firebase.ts src/services/auth.ts src/hooks/useAuth.ts
git commit -m "feat: add Firebase init, auth service, useAuth hook

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Rounds Service + Zustand Store

**Files:**
- Create: `src/services/rounds.ts`
- Create: `src/store/useAppStore.ts`

- [ ] **Step 1: Create rounds service**

Create `src/services/rounds.ts`:

```typescript
import {
  collection, doc, setDoc, updateDoc, getDoc,
  onSnapshot, query, where, orderBy, getDocs, serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import { Round, HoleConfig, PlayerInfo, DEFAULT_HOLE_PARS } from '../types'

export function generateLobbyCode(): string {
  return Math.random().toString(36).substring(2, 8).toUpperCase()
}

export function buildDefaultHoles(totalHoles: 9 | 18): HoleConfig[] {
  return DEFAULT_HOLE_PARS[totalHoles].map((par, i) => ({
    holeNumber: i + 1,
    par,
    distanceMeters: par === 3 ? 150 : par === 5 ? 480 : 360,
    shots: {},
  }))
}

export async function createRound(
  hostId: string,
  hostInfo: PlayerInfo,
  courseId: string,
  courseName: string,
  totalHoles: 9 | 18,
): Promise<string> {
  const ref = doc(collection(db, 'rounds'))
  await setDoc(ref, {
    courseId,
    courseName,
    totalHoles,
    lobbyCode: generateLobbyCode(),
    status: 'active',
    hostId,
    players: { [hostId]: hostInfo },
    holes: buildDefaultHoles(totalHoles),
    startedAt: serverTimestamp(),
    finishedAt: null,
    createdAt: serverTimestamp(),
  })
  return ref.id
}

export async function recordShot(
  roundId: string,
  holeIndex: number,
  userId: string,
  count: number,
  club: string,
): Promise<void> {
  const ref = doc(db, 'rounds', roundId)
  const snap = await getDoc(ref)
  const data = snap.data() as Omit<Round, 'id'>
  const holes = data.holes.map((h, i) =>
    i === holeIndex
      ? { ...h, shots: { ...h.shots, [userId]: { count, club, updatedAt: new Date() } } }
      : h,
  )
  await updateDoc(ref, { holes })
}

export async function finishRound(roundId: string): Promise<void> {
  await updateDoc(doc(db, 'rounds', roundId), {
    status: 'finished',
    finishedAt: serverTimestamp(),
  })
}

export function subscribeToRound(
  roundId: string,
  callback: (round: Round) => void,
): () => void {
  return onSnapshot(doc(db, 'rounds', roundId), (snap) => {
    if (snap.exists()) callback({ id: snap.id, ...snap.data() } as Round)
  })
}

export async function getUserRounds(userId: string): Promise<Round[]> {
  // Firestore inequality filter workaround: fetch all rounds where user is a player
  // by checking the players map field exists for this userId
  const q = query(
    collection(db, 'rounds'),
    where('hostId', '==', userId),
    orderBy('createdAt', 'desc'),
  )
  const snap = await getDocs(q)
  return snap.docs.map(d => ({ id: d.id, ...d.data() } as Round))
}
```

- [ ] **Step 2: Write test for generateLobbyCode and buildDefaultHoles**

Create `src/services/rounds.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { generateLobbyCode, buildDefaultHoles } from './rounds'

describe('generateLobbyCode', () => {
  it('generates a 6-character string', () => {
    expect(generateLobbyCode()).toHaveLength(6)
  })
  it('uses uppercase characters', () => {
    const code = generateLobbyCode()
    expect(code).toBe(code.toUpperCase())
  })
  it('generates different codes each time', () => {
    const codes = new Set(Array.from({ length: 20 }, () => generateLobbyCode()))
    expect(codes.size).toBeGreaterThan(15)
  })
})

describe('buildDefaultHoles', () => {
  it('builds 9 holes for 9-hole round', () => {
    expect(buildDefaultHoles(9)).toHaveLength(9)
  })
  it('builds 18 holes for 18-hole round', () => {
    expect(buildDefaultHoles(18)).toHaveLength(18)
  })
  it('each hole has holeNumber, par, distanceMeters, and empty shots', () => {
    const holes = buildDefaultHoles(9)
    for (const hole of holes) {
      expect(hole).toHaveProperty('holeNumber')
      expect(hole).toHaveProperty('par')
      expect(hole).toHaveProperty('distanceMeters')
      expect(hole.shots).toEqual({})
    }
  })
  it('hole numbers are 1-indexed', () => {
    const holes = buildDefaultHoles(9)
    expect(holes[0].holeNumber).toBe(1)
    expect(holes[8].holeNumber).toBe(9)
  })
})
```

- [ ] **Step 3: Run tests — expect PASS**

```bash
npm run test:run -- src/services/rounds.test.ts
```

Expected: 7 tests pass.

- [ ] **Step 4: Create Zustand store**

Create `src/store/useAppStore.ts`:

```typescript
import { create } from 'zustand'
import { Round } from '../types'

interface AppStore {
  activeRound: Round | null
  currentHoleIndex: number
  lastClubUsed: string

  setActiveRound: (round: Round | null) => void
  setCurrentHoleIndex: (index: number) => void
  setLastClubUsed: (club: string) => void
}

export const useAppStore = create<AppStore>((set) => ({
  activeRound: null,
  currentHoleIndex: 0,
  lastClubUsed: 'Driver',

  setActiveRound: (round) => set({ activeRound: round }),
  setCurrentHoleIndex: (index) => set({ currentHoleIndex: index }),
  setLastClubUsed: (club) => set({ lastClubUsed: club }),
}))
```

- [ ] **Step 5: Commit**

```bash
git add src/services/rounds.ts src/services/rounds.test.ts src/store/
git commit -m "feat: add rounds Firestore service, lobby code generator, Zustand store

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: UI Components

**Files:**
- Create: `src/components/ui/Button.tsx`
- Create: `src/components/ui/Card.tsx`
- Create: `src/components/ui/ScoreChip.tsx`
- Create: `src/components/ui/ClubChip.tsx`
- Create: `src/components/layout/BottomNav.tsx`
- Create: `src/components/layout/PageHeader.tsx`
- Test: `src/components/ui/ScoreChip.test.tsx`
- Test: `src/components/ui/ClubChip.test.tsx`

- [ ] **Step 1: Write failing component tests**

Create `src/components/ui/ScoreChip.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ScoreChip } from './ScoreChip'

describe('ScoreChip', () => {
  it('renders "Eagle" for delta -2', () => {
    render(<ScoreChip shots={2} par={4} />)
    expect(screen.getByText('Eagle')).toBeInTheDocument()
  })
  it('renders "Birdie" for delta -1', () => {
    render(<ScoreChip shots={3} par={4} />)
    expect(screen.getByText('Birdie')).toBeInTheDocument()
  })
  it('renders "Par" for delta 0', () => {
    render(<ScoreChip shots={4} par={4} />)
    expect(screen.getByText('Par')).toBeInTheDocument()
  })
  it('renders "Bogey" for delta +1', () => {
    render(<ScoreChip shots={5} par={4} />)
    expect(screen.getByText('Bogey')).toBeInTheDocument()
  })
  it('renders the shot count', () => {
    render(<ScoreChip shots={5} par={4} />)
    expect(screen.getByText('5')).toBeInTheDocument()
  })
})
```

Create `src/components/ui/ClubChip.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ClubChip } from './ClubChip'

describe('ClubChip', () => {
  it('renders abbreviated club name', () => {
    render(<ClubChip club="Driver" selected={false} onSelect={vi.fn()} />)
    expect(screen.getByText('DRV')).toBeInTheDocument()
  })
  it('calls onSelect with club name on click', () => {
    const onSelect = vi.fn()
    render(<ClubChip club="Putter" selected={false} onSelect={onSelect} />)
    fireEvent.click(screen.getByRole('button'))
    expect(onSelect).toHaveBeenCalledWith('Putter')
  })
  it('applies selected styling when selected=true', () => {
    render(<ClubChip club="7i" selected={true} onSelect={vi.fn()} />)
    const btn = screen.getByRole('button')
    expect(btn.className).toContain('bg-primary')
  })
})
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npm run test:run -- src/components/ui
```

Expected: import errors.

- [ ] **Step 3: Create Button**

Create `src/components/ui/Button.tsx`:

```tsx
interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost'
}

export function Button({ variant = 'primary', className = '', children, ...props }: ButtonProps) {
  const base = 'font-headline font-semibold text-label-lg rounded min-h-touch w-full flex items-center justify-center active:scale-[0.98] transition-transform disabled:opacity-40'
  const variants = {
    primary: 'bg-primary text-on-primary',
    secondary: 'border border-outline text-on-surface',
    ghost: 'text-primary underline',
  }
  return (
    <button className={`${base} ${variants[variant]} ${className}`} {...props}>
      {children}
    </button>
  )
}
```

- [ ] **Step 4: Create Card**

Create `src/components/ui/Card.tsx`:

```tsx
interface CardProps {
  children: React.ReactNode
  className?: string
  onClick?: () => void
}

export function Card({ children, className = '', onClick }: CardProps) {
  return (
    <div
      className={`bg-surface-container-lowest rounded-lg shadow-card border border-outline-variant/20 p-5 ${onClick ? 'cursor-pointer active:scale-[0.99] transition-transform' : ''} ${className}`}
      onClick={onClick}
    >
      {children}
    </div>
  )
}
```

- [ ] **Step 5: Create ScoreChip**

Create `src/components/ui/ScoreChip.tsx`:

```tsx
import { scoreColor, scoreLabel } from '../../types'

interface ScoreChipProps {
  shots: number
  par: number
}

export function ScoreChip({ shots, par }: ScoreChipProps) {
  const delta = shots - par
  const bg = scoreColor(delta)
  const label = scoreLabel(delta)
  const textColor = delta === 0 ? '#1A1C1C' : delta <= -1 ? '#1A1C1C' : '#FFFFFF'

  return (
    <div
      className="flex flex-col items-center justify-center rounded-lg w-12 h-12 text-center border border-outline-variant/20"
      style={{ backgroundColor: bg }}
    >
      <span className="text-label-lg font-semibold" style={{ color: textColor }}>{shots}</span>
      <span className="text-[10px] font-medium leading-none" style={{ color: textColor }}>{label}</span>
    </div>
  )
}
```

- [ ] **Step 6: Create ClubChip**

Create `src/components/ui/ClubChip.tsx`:

```tsx
import { CLUB_ABBREV } from '../../types'

interface ClubChipProps {
  club: string
  selected: boolean
  onSelect: (club: string) => void
}

export function ClubChip({ club, selected, onSelect }: ClubChipProps) {
  return (
    <button
      onClick={() => onSelect(club)}
      className={`px-3 py-2 rounded-full text-label-lg font-semibold min-h-touch min-w-touch shrink-0 transition-colors ${
        selected
          ? 'bg-primary text-on-primary'
          : 'bg-surface-container border border-outline-variant text-on-surface-variant'
      }`}
    >
      {CLUB_ABBREV[club] ?? club}
    </button>
  )
}
```

- [ ] **Step 7: Create BottomNav**

Create `src/components/layout/BottomNav.tsx`:

```tsx
import { NavLink } from 'react-router-dom'

const tabs = [
  { to: '/home', label: 'Главная', icon: '⛳' },
  { to: '/history', label: 'История', icon: '📋' },
]

export function BottomNav() {
  return (
    <nav className="fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-[390px] bg-surface-container-lowest border-t border-outline-variant/30 flex z-50">
      {tabs.map(({ to, label, icon }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) =>
            `flex-1 flex flex-col items-center justify-center min-h-touch gap-0.5 text-label-md font-semibold transition-colors ${
              isActive ? 'text-primary' : 'text-on-surface-variant'
            }`
          }
        >
          <span className="text-xl">{icon}</span>
          <span>{label}</span>
        </NavLink>
      ))}
    </nav>
  )
}
```

- [ ] **Step 8: Create PageHeader**

Create `src/components/layout/PageHeader.tsx`:

```tsx
import { useNavigate } from 'react-router-dom'

interface PageHeaderProps {
  title: string
  showBack?: boolean
  right?: React.ReactNode
}

export function PageHeader({ title, showBack = true, right }: PageHeaderProps) {
  const navigate = useNavigate()
  return (
    <header className="flex items-center px-5 py-3 bg-surface-container-lowest border-b border-outline-variant/20 min-h-[56px]">
      {showBack && (
        <button
          onClick={() => navigate(-1)}
          className="min-h-touch min-w-touch flex items-center justify-center -ml-2 text-on-surface"
          aria-label="Назад"
        >
          ←
        </button>
      )}
      <h1 className="flex-1 text-center font-headline font-bold text-title-lg text-on-surface">
        {title}
      </h1>
      <div className="min-w-touch">{right}</div>
    </header>
  )
}
```

- [ ] **Step 9: Run tests — expect PASS**

```bash
npm run test:run
```

Expected: all tests pass (19 types + 4 distance + 7 rounds + 8 component = 38 total).

- [ ] **Step 10: Commit**

```bash
git add src/components/
git commit -m "feat: add UI components (Button, Card, ScoreChip, ClubChip, BottomNav, PageHeader)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: App Routing + Auth Screen

**Files:**
- Create: `src/App.tsx`
- Create: `src/screens/Auth.tsx`

- [ ] **Step 1: Create App.tsx with routing**

Create `src/App.tsx`:

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { Auth } from './screens/Auth'
import { Home } from './screens/Home'
import { CourseSearch } from './screens/CourseSearch'
import { RoundSetup } from './screens/RoundSetup'
import { HoleTracker } from './screens/HoleTracker'
import { RoundResults } from './screens/RoundResults'
import { History } from './screens/History'

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return (
    <div className="screen items-center justify-center">
      <div className="text-on-surface-variant text-body-md">Загрузка...</div>
    </div>
  )
  if (!user) return <Navigate to="/auth" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/auth" element={<Auth />} />
        <Route path="/" element={<Navigate to="/home" replace />} />
        <Route path="/home" element={<ProtectedRoute><Home /></ProtectedRoute>} />
        <Route path="/courses" element={<ProtectedRoute><CourseSearch /></ProtectedRoute>} />
        <Route path="/round/setup" element={<ProtectedRoute><RoundSetup /></ProtectedRoute>} />
        <Route path="/round/:roundId/hole/:holeNumber" element={<ProtectedRoute><HoleTracker /></ProtectedRoute>} />
        <Route path="/round/:roundId/results" element={<ProtectedRoute><RoundResults /></ProtectedRoute>} />
        <Route path="/history" element={<ProtectedRoute><History /></ProtectedRoute>} />
      </Routes>
    </BrowserRouter>
  )
}
```

- [ ] **Step 2: Create Auth screen**

Create `src/screens/Auth.tsx`:

```tsx
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { signInWithGoogle } from '../services/auth'
import { Button } from '../components/ui/Button'

export function Auth() {
  const navigate = useNavigate()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleGoogleSignIn() {
    setLoading(true)
    setError(null)
    try {
      await signInWithGoogle()
      navigate('/home')
    } catch (e) {
      setError('Ошибка входа. Попробуйте ещё раз.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="screen items-center justify-center px-5 gap-8">
      <div className="text-center space-y-3">
        <div className="text-6xl">⛳</div>
        <h1 className="font-headline font-bold text-headline-lg text-primary">Smart Golf Caddy</h1>
        <p className="text-body-md text-on-surface-variant">Ваш цифровой кэдди на поле</p>
      </div>

      <div className="w-full space-y-3">
        <Button onClick={handleGoogleSignIn} disabled={loading}>
          {loading ? 'Вход...' : '🔵  Войти через Google'}
        </Button>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Verify in browser**

```bash
npm run dev
```

Open http://localhost:5173. Should redirect to `/auth` and show the Auth screen with green logo, app name, and Google sign-in button. (Clicking sign-in requires real Firebase credentials in `.env.local`.)

- [ ] **Step 4: Commit**

```bash
git add src/App.tsx src/screens/Auth.tsx
git commit -m "feat: add app routing, auth guard, Auth screen with Google Sign-In

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Courses Service + Course Search Screen

**Files:**
- Create: `src/services/courses.ts`
- Create: `src/screens/CourseSearch.tsx`

- [ ] **Step 1: Create courses service**

Create `src/services/courses.ts`:

```typescript
import { CourseResult } from '../types'
import { haversineMetres } from './distance'

const API_KEY = import.meta.env.VITE_GOOGLE_PLACES_API_KEY as string

export async function findNearbyCourses(
  lat: number,
  lng: number,
): Promise<CourseResult[]> {
  const url = new URL('https://maps.googleapis.com/maps/api/place/nearbysearch/json')
  url.searchParams.set('location', `${lat},${lng}`)
  url.searchParams.set('radius', '20000')          // 20 km
  url.searchParams.set('type', 'golf_course')
  url.searchParams.set('key', API_KEY)

  // Note: Google Places API requires a server-side proxy in production
  // to avoid exposing the API key. For MVP/dev, we call directly.
  const res = await fetch(url.toString())
  if (!res.ok) throw new Error('Places API error')

  const data = await res.json() as {
    results: Array<{
      place_id: string
      name: string
      vicinity: string
      geometry: { location: { lat: number; lng: number } }
    }>
  }

  return data.results.map((p) => ({
    placeId: p.place_id,
    name: p.name,
    vicinity: p.vicinity,
    location: p.geometry.location,
    distanceKm: Math.round(haversineMetres(lat, lng, p.geometry.location.lat, p.geometry.location.lng) / 100) / 10,
  }))
}
```

- [ ] **Step 2: Create CourseSearch screen**

Create `src/screens/CourseSearch.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGeolocation } from '../hooks/useGeolocation'
import { findNearbyCourses } from '../services/courses'
import { CourseResult } from '../types'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'

export function CourseSearch() {
  const navigate = useNavigate()
  const { lat, lng, error: geoError, loading: geoLoading } = useGeolocation()
  const [courses, setCourses] = useState<CourseResult[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  useEffect(() => {
    if (!lat || !lng) return
    setLoading(true)
    findNearbyCourses(lat, lng)
      .then(setCourses)
      .catch(() => setError('Не удалось загрузить поля. Проверьте интернет.'))
      .finally(() => setLoading(false))
  }, [lat, lng])

  const filtered = courses.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase()),
  )

  function selectCourse(course: CourseResult) {
    navigate('/round/setup', { state: { course } })
  }

  return (
    <div className="screen">
      <PageHeader title="Поиск полей" />

      <div className="px-5 pt-4 pb-2">
        <input
          type="text"
          placeholder="Поиск по названию..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full border border-outline-variant rounded px-4 py-3 text-body-md bg-surface-container-lowest outline-none focus:border-primary"
        />
      </div>

      <div className="flex-1 px-5 pb-6 space-y-3 overflow-y-auto">
        {geoLoading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            Определяем вашу позицию...
          </p>
        )}
        {geoError && (
          <p className="text-center text-error text-body-md pt-8">
            {geoError}. Введите название поля выше.
          </p>
        )}
        {loading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            Ищем ближайшие поля...
          </p>
        )}
        {error && (
          <p className="text-center text-error text-body-md pt-8">{error}</p>
        )}
        {filtered.map(course => (
          <Card key={course.placeId} onClick={() => selectCourse(course)}>
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-headline font-semibold text-title-lg text-on-surface">{course.name}</h3>
                <p className="text-label-lg text-on-surface-variant mt-1">{course.vicinity}</p>
              </div>
              <span className="font-headline font-bold text-headline-md text-primary shrink-0 ml-3">
                {course.distanceKm} км
              </span>
            </div>
          </Card>
        ))}
        {!loading && !geoLoading && filtered.length === 0 && courses.length > 0 && (
          <p className="text-center text-on-surface-variant text-body-md pt-4">Поля не найдены</p>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Commit**

```bash
git add src/services/courses.ts src/screens/CourseSearch.tsx
git commit -m "feat: add course discovery via Google Places API and CourseSearch screen

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Home Screen + Round Setup Screen

**Files:**
- Create: `src/screens/Home.tsx`
- Create: `src/screens/RoundSetup.tsx`

- [ ] **Step 1: Create Home screen**

Create `src/screens/Home.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { BottomNav } from '../components/layout/BottomNav'
import { format } from 'date-fns'
import { ru } from 'date-fns/locale'

export function Home() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [recentRounds, setRecentRounds] = useState<Round[]>([])

  useEffect(() => {
    if (!user) return
    getUserRounds(user.uid).then(rounds =>
      setRecentRounds(rounds.filter(r => r.status === 'finished').slice(0, 3)),
    )
  }, [user])

  function formatDate(round: Round) {
    const ts = round.createdAt as unknown as { seconds: number }
    const date = ts?.seconds ? new Date(ts.seconds * 1000) : new Date()
    return format(date, 'd MMM yyyy', { locale: ru })
  }

  function scoreSummary(round: Round, uid: string) {
    const player = round.players[uid]
    if (!player) return ''
    const sign = player.scoreDiff >= 0 ? '+' : ''
    return `${player.totalScore} (${sign}${player.scoreDiff})`
  }

  return (
    <div className="screen pb-20">
      <div className="px-5 pt-8 pb-6 bg-primary-container">
        <p className="text-on-primary/80 text-label-lg font-semibold">Добро пожаловать</p>
        <h1 className="font-headline font-bold text-headline-md text-on-primary mt-1">
          {user?.displayName?.split(' ')[0] ?? 'Голфер'} ⛳
        </h1>
      </div>

      <div className="px-5 pt-6 space-y-4">
        <Button onClick={() => navigate('/courses')}>
          Начать новый раунд
        </Button>

        {recentRounds.length > 0 && (
          <div>
            <h2 className="font-headline font-semibold text-title-lg text-on-surface mb-3">
              Последние раунды
            </h2>
            <div className="space-y-3">
              {recentRounds.map(round => (
                <Card key={round.id} onClick={() => navigate(`/round/${round.id}/results`)}>
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-body-md text-on-surface">{round.courseName}</p>
                      <p className="text-label-lg text-on-surface-variant mt-0.5">
                        {formatDate(round)} · {round.totalHoles} лунок
                      </p>
                    </div>
                    {user && (
                      <span className="font-headline font-bold text-title-lg text-primary">
                        {scoreSummary(round, user.uid)}
                      </span>
                    )}
                  </div>
                </Card>
              ))}
            </div>
          </div>
        )}
      </div>

      <BottomNav />
    </div>
  )
}
```

- [ ] **Step 2: Create RoundSetup screen**

Create `src/screens/RoundSetup.tsx`:

```tsx
import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { createRound } from '../services/rounds'
import { CourseResult } from '../types'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function RoundSetup() {
  const navigate = useNavigate()
  const location = useLocation()
  const { user } = useAuth()
  const course = location.state?.course as CourseResult | undefined

  const [totalHoles, setTotalHoles] = useState<9 | 18>(18)
  const [loading, setLoading] = useState(false)

  async function handleStart() {
    if (!user || !course) return
    setLoading(true)
    try {
      const roundId = await createRound(
        user.uid,
        {
          name: user.displayName ?? 'Голфер',
          avatar: user.photoURL ?? '',
          totalScore: 0,
          scoreDiff: 0,
        },
        course.placeId,
        course.name,
        totalHoles,
      )
      navigate(`/round/${roundId}/hole/1`)
    } catch (e) {
      console.error('Failed to create round', e)
    } finally {
      setLoading(false)
    }
  }

  if (!course) {
    return (
      <div className="screen items-center justify-center px-5">
        <p className="text-body-md text-error">Поле не выбрано.</p>
        <Button onClick={() => navigate('/courses')} className="mt-4">
          Выбрать поле
        </Button>
      </div>
    )
  }

  return (
    <div className="screen">
      <PageHeader title="Настройка раунда" />

      <div className="px-5 pt-6 space-y-6 flex-1">
        <div className="card">
          <h2 className="font-headline font-bold text-title-lg text-on-surface">{course.name}</h2>
          <p className="text-label-lg text-on-surface-variant mt-1">{course.vicinity} · {course.distanceKm} км</p>
        </div>

        <div>
          <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
            Количество лунок
          </p>
          <div className="flex gap-3">
            {([9, 18] as const).map(n => (
              <button
                key={n}
                onClick={() => setTotalHoles(n)}
                className={`flex-1 min-h-touch rounded font-headline font-bold text-title-lg border-2 transition-colors ${
                  totalHoles === n
                    ? 'border-primary bg-primary text-on-primary'
                    : 'border-outline-variant text-on-surface-variant'
                }`}
              >
                {n}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="px-5 pb-8">
        <Button onClick={handleStart} disabled={loading}>
          {loading ? 'Создаём раунд...' : 'Начать игру'}
        </Button>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Commit**

```bash
git add src/screens/Home.tsx src/screens/RoundSetup.tsx
git commit -m "feat: add Home screen and RoundSetup screen

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Hole Tracker Screen

**Files:**
- Create: `src/screens/HoleTracker.tsx`

- [ ] **Step 1: Create HoleTracker screen**

Create `src/screens/HoleTracker.tsx`:

```tsx
import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { useGeolocation } from '../hooks/useGeolocation'
import { useAppStore } from '../store/useAppStore'
import { subscribeToRound, recordShot, finishRound } from '../services/rounds'
import { haversineMetres } from '../services/distance'
import { Round, DEFAULT_CLUBS } from '../types'
import { ClubChip } from '../components/ui/ClubChip'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function HoleTracker() {
  const { roundId, holeNumber } = useParams<{ roundId: string; holeNumber: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { lat, lng } = useGeolocation()
  const { lastClubUsed, setLastClubUsed } = useAppStore()

  const holeIndex = (parseInt(holeNumber ?? '1', 10) - 1)
  const [round, setRound] = useState<Round | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  const hole = round?.holes[holeIndex]
  const myShots = (hole && user) ? (hole.shots[user.uid]?.count ?? 0) : 0
  const myClub = (hole && user) ? (hole.shots[user.uid]?.club ?? lastClubUsed) : lastClubUsed

  const distanceM = hole && lat && lng
    ? Math.round(haversineMetres(lat, lng, lat + 0.001, lng + 0.001)) // placeholder until real hole pin coords
    : null

  const save = useCallback(async (count: number, club: string) => {
    if (!roundId || !user || !hole) return
    setSaving(true)
    try {
      await recordShot(roundId, holeIndex, user.uid, count, club)
      setLastClubUsed(club)
    } finally {
      setSaving(false)
    }
  }, [roundId, user, hole, holeIndex, setLastClubUsed])

  function changeShots(delta: number) {
    const next = Math.max(1, myShots + delta)
    save(next, myClub)
  }

  function changeClub(club: string) {
    save(myShots === 0 ? 1 : myShots, club)
  }

  async function goToHole(n: number) {
    navigate(`/round/${roundId}/hole/${n}`)
  }

  async function handleFinish() {
    if (!roundId) return
    await finishRound(roundId)
    navigate(`/round/${roundId}/results`)
  }

  if (!round || !hole) {
    return (
      <div className="screen items-center justify-center">
        <p className="text-on-surface-variant text-body-md">Загрузка...</p>
      </div>
    )
  }

  const totalHoles = round.totalHoles
  const currentHole = holeIndex + 1

  return (
    <div className="screen pb-6">
      <PageHeader
        title={`Лунка ${currentHole} / ${totalHoles}`}
        right={
          <button
            onClick={handleFinish}
            className="text-label-lg text-error font-semibold min-h-touch flex items-center"
          >
            Финиш
          </button>
        }
      />

      {/* Hole info */}
      <div className="bg-primary-container px-5 py-4 flex items-center justify-between">
        <div>
          <p className="text-on-primary/70 text-label-lg">Пар</p>
          <p className="font-headline font-bold text-headline-md text-on-primary">{hole.par}</p>
        </div>
        <div className="text-center">
          <p className="font-headline font-bold text-display-lg text-on-primary">{currentHole}</p>
        </div>
        <div className="text-right">
          <p className="text-on-primary/70 text-label-lg">Дист.</p>
          <p className="font-headline font-bold text-headline-md text-on-primary">{hole.distanceMeters} м</p>
        </div>
      </div>

      {/* GPS badge */}
      {distanceM !== null && (
        <div className="mx-5 mt-3 px-4 py-2 bg-tertiary-container rounded-lg flex items-center gap-2">
          <span className="text-on-tertiary text-label-lg">📍</span>
          <span className="text-on-tertiary text-label-lg font-semibold">
            ~{distanceM} м до поля
          </span>
        </div>
      )}

      {/* Shot counter */}
      <div className="flex-1 flex flex-col items-center justify-center gap-6 px-5">
        <p className="text-on-surface-variant text-label-lg font-semibold uppercase tracking-wider">
          Ваши удары
        </p>
        <div className="flex items-center gap-8">
          <button
            onClick={() => changeShots(-1)}
            disabled={myShots <= 1 || saving}
            className="w-16 h-16 rounded-full bg-surface-container-high text-on-surface text-headline-lg font-bold flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30"
          >
            −
          </button>
          <span className="font-headline font-bold text-display-lg text-on-surface w-16 text-center">
            {myShots}
          </span>
          <button
            onClick={() => changeShots(+1)}
            disabled={saving}
            className="w-16 h-16 rounded-full bg-primary text-on-primary text-headline-lg font-bold flex items-center justify-center active:scale-95 transition-transform"
          >
            +
          </button>
        </div>
      </div>

      {/* Club selector */}
      <div className="px-5 space-y-2">
        <p className="text-label-lg text-on-surface-variant font-semibold uppercase tracking-wider">
          Клюшка
        </p>
        <div className="flex gap-2 overflow-x-auto pb-2 -mx-5 px-5">
          {DEFAULT_CLUBS.map(club => (
            <ClubChip
              key={club}
              club={club}
              selected={myClub === club}
              onSelect={changeClub}
            />
          ))}
        </div>
      </div>

      {/* Prev / Next navigation */}
      <div className="flex gap-3 px-5 mt-4">
        <Button
          variant="secondary"
          disabled={currentHole === 1}
          onClick={() => goToHole(currentHole - 1)}
          className="w-auto flex-1"
        >
          ← Пред.
        </Button>
        {currentHole < totalHoles ? (
          <Button onClick={() => goToHole(currentHole + 1)} className="flex-1">
            След. →
          </Button>
        ) : (
          <Button onClick={handleFinish} className="flex-1 bg-tertiary-container text-on-tertiary">
            Завершить раунд
          </Button>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/screens/HoleTracker.tsx
git commit -m "feat: add HoleTracker screen with shot counter, club selector, GPS badge

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Round Results Screen

**Files:**
- Create: `src/screens/RoundResults.tsx`
- Test: `src/screens/RoundResults.test.tsx`

- [ ] **Step 1: Write failing test for score delta computation**

Create `src/screens/RoundResults.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest'
import { computePlayerTotals } from './RoundResults'
import { Round, HoleConfig } from '../types'

function makeRound(overrides: Partial<Round> = {}): Round {
  const holes: HoleConfig[] = [
    { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 3, club: '7i', updatedAt: new Date() } } },
    { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: 4, club: 'PW', updatedAt: new Date() } } },
    { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: 5, club: 'Driver', updatedAt: new Date() } } },
  ]
  return {
    id: 'r1', courseId: 'c1', courseName: 'Test Course',
    totalHoles: 9, lobbyCode: 'ABC123', status: 'finished', hostId: 'uid1',
    players: { uid1: { name: 'Alice', avatar: '', totalScore: 0, scoreDiff: 0 } },
    holes, startedAt: new Date(), finishedAt: new Date(), createdAt: new Date(),
    ...overrides,
  }
}

describe('computePlayerTotals', () => {
  it('computes total score and scoreDiff for a player', () => {
    const round = makeRound()
    const result = computePlayerTotals(round, 'uid1')
    // shots: 3+4+5=12, par: 4+3+5=12, diff=0
    expect(result.totalScore).toBe(12)
    expect(result.scoreDiff).toBe(0)
  })

  it('returns 0/0 for a player with no shots recorded', () => {
    const round = makeRound()
    const result = computePlayerTotals(round, 'unknown-uid')
    expect(result.totalScore).toBe(0)
    expect(result.scoreDiff).toBe(0)
  })

  it('correctly computes negative scoreDiff (under par)', () => {
    const round = makeRound()
    // Alice shot 3,4,5 → 12. Par = 4+3+5=12. But let's make her shoot 2,3,5 → 10
    round.holes[0].shots['uid1'] = { count: 2, club: '7i', updatedAt: new Date() }
    round.holes[1].shots['uid1'] = { count: 3, club: 'PW', updatedAt: new Date() }
    const result = computePlayerTotals(round, 'uid1')
    expect(result.totalScore).toBe(10)
    expect(result.scoreDiff).toBe(-2)
  })
})
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npm run test:run -- src/screens/RoundResults.test.tsx
```

Expected: import error.

- [ ] **Step 3: Create RoundResults screen with exported helper**

Create `src/screens/RoundResults.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { subscribeToRound } from '../services/rounds'
import { Round, scoreColor, scoreLabel } from '../types'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function computePlayerTotals(
  round: Round,
  userId: string,
): { totalScore: number; scoreDiff: number } {
  let totalScore = 0
  let totalPar = 0
  for (const hole of round.holes) {
    const shots = hole.shots[userId]?.count ?? 0
    totalScore += shots
    totalPar += hole.par
  }
  return { totalScore, scoreDiff: totalScore - totalPar }
}

function findWinner(round: Round): string {
  let best = Infinity
  let winnerId = ''
  for (const [uid, player] of Object.entries(round.players)) {
    const { scoreDiff } = computePlayerTotals(round, uid)
    if (scoreDiff < best) { best = scoreDiff; winnerId = uid }
  }
  return round.players[winnerId]?.name ?? 'Неизвестно'
}

export function RoundResults() {
  const { roundId } = useParams<{ roundId: string }>()
  const navigate = useNavigate()
  const [round, setRound] = useState<Round | null>(null)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  if (!round) {
    return (
      <div className="screen items-center justify-center">
        <p className="text-on-surface-variant text-body-md">Загрузка результатов...</p>
      </div>
    )
  }

  const players = Object.entries(round.players)
  const winner = findWinner(round)

  return (
    <div className="screen pb-8">
      <PageHeader title="Итоги раунда" showBack={false} />

      {/* Winner banner */}
      <div className="bg-primary-container px-5 py-6 text-center">
        <p className="text-on-primary/70 text-label-lg uppercase tracking-wider">Победитель</p>
        <p className="font-headline font-bold text-headline-lg text-on-primary mt-1">🏆 {winner}</p>
        <p className="text-on-primary/70 text-label-md mt-1">{round.courseName} · {round.totalHoles} лунок</p>
      </div>

      {/* Player score summaries */}
      <div className="px-5 pt-5 space-y-3">
        {players
          .map(([uid, player]) => ({ uid, player, ...computePlayerTotals(round, uid) }))
          .sort((a, b) => a.scoreDiff - b.scoreDiff)
          .map(({ uid, player, totalScore, scoreDiff }) => (
            <Card key={uid}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {player.avatar
                    ? <img src={player.avatar} className="w-10 h-10 rounded-full" alt={player.name} />
                    : <div className="w-10 h-10 rounded-full bg-surface-container flex items-center justify-center text-headline-md">⛳</div>
                  }
                  <span className="font-semibold text-body-md text-on-surface">{player.name}</span>
                </div>
                <div className="text-right">
                  <p className="font-headline font-bold text-title-lg text-on-surface">{totalScore}</p>
                  <p className="text-label-lg" style={{ color: scoreColor(scoreDiff) === '#FFFFFF' ? '#717A6D' : scoreColor(scoreDiff) }}>
                    {scoreDiff >= 0 ? '+' : ''}{scoreDiff} ({scoreLabel(scoreDiff)})
                  </p>
                </div>
              </div>
            </Card>
          ))}
      </div>

      {/* Scorecard grid */}
      <div className="px-5 pt-6">
        <h2 className="font-headline font-semibold text-title-lg text-on-surface mb-3">Карта счёта</h2>
        <div className="overflow-x-auto rounded-lg border border-outline-variant/30">
          <table className="w-full text-center text-label-md min-w-max">
            <thead>
              <tr className="bg-surface-container">
                <th className="py-2 px-3 text-left text-on-surface-variant font-semibold sticky left-0 bg-surface-container">Игрок</th>
                {round.holes.map(h => (
                  <th key={h.holeNumber} className="py-2 px-2 text-on-surface-variant font-semibold">{h.holeNumber}</th>
                ))}
                <th className="py-2 px-3 text-on-surface font-bold">∑</th>
              </tr>
            </thead>
            <tbody>
              {players.map(([uid, player]) => {
                const { totalScore } = computePlayerTotals(round, uid)
                return (
                  <tr key={uid} className="border-t border-outline-variant/20">
                    <td className="py-2 px-3 text-left font-semibold text-on-surface sticky left-0 bg-surface-container-lowest truncate max-w-[80px]">
                      {player.name}
                    </td>
                    {round.holes.map(hole => {
                      const shots = hole.shots[uid]?.count
                      const delta = shots != null ? shots - hole.par : null
                      return (
                        <td
                          key={hole.holeNumber}
                          className="py-2 px-2 font-semibold"
                          style={{ backgroundColor: delta != null ? scoreColor(delta) : undefined, color: delta === 0 ? '#1A1C1C' : delta != null && delta < 0 ? '#1A1C1C' : '#1A1C1C' }}
                        >
                          {shots ?? '—'}
                        </td>
                      )
                    })}
                    <td className="py-2 px-3 font-headline font-bold text-on-surface">{totalScore || '—'}</td>
                  </tr>
                )
              })}
              {/* Par row */}
              <tr className="border-t-2 border-outline-variant/50 bg-surface-container">
                <td className="py-2 px-3 text-left font-semibold text-on-surface-variant sticky left-0 bg-surface-container">Пар</td>
                {round.holes.map(hole => (
                  <td key={hole.holeNumber} className="py-2 px-2 text-on-surface-variant">{hole.par}</td>
                ))}
                <td className="py-2 px-3 font-bold text-on-surface-variant">
                  {round.holes.reduce((s, h) => s + h.par, 0)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div className="px-5 pt-6 space-y-3">
        <Button onClick={() => navigate('/courses')}>Новый раунд</Button>
        <Button variant="secondary" onClick={() => navigate('/home')}>На главную</Button>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npm run test:run
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/screens/RoundResults.tsx src/screens/RoundResults.test.tsx
git commit -m "feat: add RoundResults screen with scorecard grid and winner banner

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 13: History Screen

**Files:**
- Create: `src/screens/History.tsx`

- [ ] **Step 1: Create History screen**

Create `src/screens/History.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { getUserRounds } from '../services/rounds'
import { Round } from '../types'
import { Card } from '../components/ui/Card'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { computePlayerTotals } from './RoundResults'
import { format } from 'date-fns'
import { ru } from 'date-fns/locale'

export function History() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [rounds, setRounds] = useState<Round[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!user) return
    getUserRounds(user.uid)
      .then(all => setRounds(all.filter(r => r.status === 'finished')))
      .finally(() => setLoading(false))
  }, [user])

  function formatDate(round: Round) {
    const ts = round.createdAt as unknown as { seconds: number }
    const date = ts?.seconds ? new Date(ts.seconds * 1000) : new Date()
    return format(date, 'd MMMM yyyy', { locale: ru })
  }

  return (
    <div className="screen pb-20">
      <PageHeader title="История раундов" showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-3 overflow-y-auto">
        {loading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">Загрузка...</p>
        )}
        {!loading && rounds.length === 0 && (
          <div className="text-center pt-16 space-y-3">
            <p className="text-4xl">⛳</p>
            <p className="text-on-surface-variant text-body-md">Нет завершённых раундов</p>
          </div>
        )}
        {rounds.map(round => {
          const { totalScore, scoreDiff } = user ? computePlayerTotals(round, user.uid) : { totalScore: 0, scoreDiff: 0 }
          const sign = scoreDiff >= 0 ? '+' : ''
          return (
            <Card key={round.id} onClick={() => navigate(`/round/${round.id}/results`)}>
              <div className="flex items-center justify-between">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-body-md text-on-surface truncate">{round.courseName}</p>
                  <p className="text-label-lg text-on-surface-variant mt-0.5">
                    {formatDate(round)} · {round.totalHoles} лунок · {Object.keys(round.players).length} игр.
                  </p>
                </div>
                <div className="ml-3 text-right shrink-0">
                  <p className="font-headline font-bold text-title-lg text-primary">{totalScore}</p>
                  <p className="text-label-md text-on-surface-variant">{sign}{scoreDiff}</p>
                </div>
              </div>
            </Card>
          )
        })}
      </div>

      <BottomNav />
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/screens/History.tsx
git commit -m "feat: add History screen with completed rounds list

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 14: PWA Manifest + Firebase Hosting

**Files:**
- Create: `public/manifest.json`
- Modify: `index.html`
- Create: `firebase.json`
- Create: `.firebaserc`

- [ ] **Step 1: Create PWA manifest**

Create `public/manifest.json`:

```json
{
  "name": "Smart Golf Caddy",
  "short_name": "Golf Caddy",
  "description": "Ваш цифровой кэдди на поле",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#F9F9F9",
  "theme_color": "#1B5E20",
  "orientation": "portrait",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

- [ ] **Step 2: Update index.html with PWA meta tags**

Replace `index.html`:

```html
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <meta name="theme-color" content="#1B5E20" />
    <meta name="mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-status-bar-style" content="default" />
    <meta name="apple-mobile-web-app-title" content="Golf Caddy" />
    <link rel="manifest" href="/manifest.json" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <title>Smart Golf Caddy</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 3: Create Firebase Hosting config**

Create `firebase.json`:

```json
{
  "hosting": {
    "public": "dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(js|css)",
        "headers": [{ "key": "Cache-Control", "value": "max-age=31536000" }]
      },
      {
        "source": "manifest.json",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
      }
    ]
  }
}
```

- [ ] **Step 4: Create .firebaserc**

Create `.firebaserc`:

```json
{
  "projects": {
    "default": "YOUR_FIREBASE_PROJECT_ID"
  }
}
```

Replace `YOUR_FIREBASE_PROJECT_ID` with the actual Firebase project ID from the Firebase console.

- [ ] **Step 5: Run full test suite**

```bash
npm run test:run
```

Expected: all tests pass.

- [ ] **Step 6: Build for production**

```bash
npm run build
```

Expected: `dist/` folder created, no TypeScript errors, no build warnings.

- [ ] **Step 7: Commit**

```bash
git add public/manifest.json index.html firebase.json .firebaserc
git commit -m "feat: add PWA manifest and Firebase Hosting config

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 8: Push to GitHub**

```bash
git push origin main
```

---

## Self-Review Checklist

| Spec requirement | Covered by |
|---|---|
| Geolocation → find nearest course | Task 9: `useGeolocation` + `findNearbyCourses` |
| Shot tracking per hole | Task 11: `HoleTracker` + `recordShot` |
| Club recording per shot | Task 11: `ClubChip` + `recordShot(club)` |
| GPS distance to course | Task 11: `haversineMetres` in HoleTracker |
| Visual round results | Task 12: `RoundResults` scorecard with color coding |
| Round history | Task 13: `History` screen |
| Auth (Google Sign-In) | Task 5 + Task 8 |
| Firebase Firestore | Tasks 6, 11, 12 |
| Fairway Elite design | Task 2 |
| PWA | Task 14 |
| React Router navigation | Task 8: `App.tsx` |

**Out of scope in Plan 1 (→ Plan 2):**
- Group lobby + QR code
- Real-time multi-device sync
- Profile screen + club bag customization
- Handicap calculation
