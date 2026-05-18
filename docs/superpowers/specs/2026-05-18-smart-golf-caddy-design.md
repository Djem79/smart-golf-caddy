# Smart Golf Caddy — Design Spec

**Date:** 2026-05-18  
**Platform:** React PWA (web first, then iOS via React Native)  
**Backend:** Firebase (Firestore + Auth)  
**Design System:** Fairway Elite (Stitch project `5265673801879966458`)

---

## 1. Overview

A mobile-first web application for golfers that replaces a physical caddy. Players find nearby golf courses via geolocation, track shots per hole (including which club was used), play in groups in real-time across multiple devices, and see visually attractive round results at the end.

**Core value:** One-handed, glove-friendly operation on the course. Every tap target ≥ 48px. Readable in direct sunlight.

---

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Framework | React 18 + TypeScript + Vite |
| Styling | Tailwind CSS (Fairway Elite tokens) |
| Routing | React Router v6 |
| State | Zustand (local) + Firestore real-time listeners |
| Auth | Firebase Auth (Google Sign-In, Apple Sign-In) |
| Database | Firebase Firestore |
| Maps / Geo | Google Maps API + browser Geolocation API |
| Hosting | Firebase Hosting (PWA) |
| Golf Courses Discovery | Google Places API (text search: "golf course near me") |
| Golf Course Hole Data | Golfbert API (hole par + distance per course) |

---

## 3. Design System — Fairway Elite

Sourced from Stitch project **Smart Golf Caddy**.

### Colors
| Token | Value | Usage |
|---|---|---|
| `primary` | `#00450D` | CTA buttons, active states |
| `primary-container` | `#1B5E20` | Navbar, header backgrounds |
| `on-primary` | `#FFFFFF` | Text on green buttons |
| `surface` | `#F9F9F9` | App background |
| `surface-container-lowest` | `#FFFFFF` | Cards |
| `on-surface` | `#1A1C1C` | Primary text |
| `on-surface-variant` | `#41493E` | Secondary text |
| `outline-variant` | `#C0C9BB` | Card borders |

### Typography
| Style | Font | Size | Weight |
|---|---|---|---|
| `display-lg` | Montserrat | 40px | 700 |
| `headline-lg` | Montserrat | 32px | 700 |
| `headline-md` | Montserrat | 24px | 600 |
| `title-lg` | Inter | 20px | 600 |
| `body-md` | Inter | 16px | 400 |
| `label-lg` | Inter | 14px | 600 |

### Spacing & Shape
- Base grid: 8px
- Touch target min: 48px
- Card radius: 16px (lg)
- Button radius: 8px (DEFAULT)
- Card shadow: `0px 4px 12px rgba(55, 71, 79, 0.05)` + `1px border rgba(55,71,79,0.1)`

---

## 4. Screens & Navigation

```
/                    → Redirect (auth check)
/auth                → Auth screen (Google / Apple Sign-In)
/home                → Home (New Game / History / Profile)
/courses             → Course search (geolocation list)
/round/setup         → Round setup (holes count, players)
/round/:id/lobby     → Group lobby (QR + 6-digit code)
/round/:id/hole/:n   → Hole tracker (shots + club + GPS)
/round/:id/results   → Round results (visual summary)
/history             → Round history list
/profile             → Profile (club bag + handicap)
```

### Screen Details

#### Auth (`/auth`)
- Google Sign-In button (primary)
- Apple Sign-In button (secondary)
- App logo + tagline

#### Home (`/home`)
- "Start New Round" — primary CTA
- Recent rounds (last 3, card list)
- Bottom nav: Home / History / Profile

#### Course Search (`/courses`)
- Requests browser geolocation on load
- Shows nearest courses sorted by distance
- Each card: course name, distance (km), par, holes count
- Search bar to filter by name
- Tap → goes to Round Setup

#### Round Setup (`/round/setup`)
- Course name (pre-filled)
- Number of holes: 9 or 18 (toggle)
- Players: current user auto-added; button "Invite Players"
- Solo toggle (no lobby needed)
- "Start Round" CTA

#### Group Lobby (`/round/:id/lobby`)
- Large 6-digit code (Montserrat display-lg)
- QR code (encodes deep-link to join)
- Player list: avatar + name, joined status
- Host sees "Start Game" CTA (enabled when ≥1 player joined)
- Non-hosts see "Waiting for host..."

#### Hole Tracker (`/round/:id/hole/:n`)
- Top: Hole N of 18 | Par X | Distance X m
- GPS badge: "↑ 142 m to pin" (updates live)
- For each player (scrollable cards):
  - Player name + avatar
  - Shot counter: large number (display-lg) with − / + buttons
  - Club selector: horizontal chip scroll (from personal bag)
- Bottom nav: ← prev hole | Next hole →
- Real-time: other players' shots sync via Firestore listener

#### Round Results (`/round/:id/results`)
- Header: winner name + trophy icon + total score
- Scorecard table: rows = players, cols = holes 1–18
- Cell color coding:
  - Eagle (−2): gold `#FFD700`
  - Birdie (−1): green `#4CAF50`
  - Par (0): white
  - Bogey (+1): orange `#FF9800`
  - Double+ (+2+): red `#F44336`
- Stats per player: fairways hit, avg shots/hole, best hole
- Share button (generates PNG scorecard)
- "Play Again" + "Back to Home" buttons

#### History (`/history`)
- List of completed rounds, sorted by date descending
- Each item: course name, date, total score, players count
- Tap → opens Round Results
- Pull-to-refresh

#### Profile (`/profile`)
- Avatar + display name
- **Handicap section:** current handicap (WHS calculation), chart of last 20 rounds
- **My Bag:** grid of clubs user has in their set
  - Predefined list: Driver, 3W, 5W, 4i–9i, PW, GW, SW, LW, Putter
  - Toggle on/off per club
  - Drag to reorder (shown order = selector order on hole tracker)
- Stats summary: total rounds, best score, avg score

---

## 5. Data Model (Firestore)

### `users/{userId}`
```ts
{
  uid: string
  name: string
  avatar: string          // photoURL from Auth
  handicap: number        // computed, stored for display
  clubs: string[]         // ordered list: ["Driver","5W","7i","PW","Putter"]
  createdAt: Timestamp
}
```

### `rounds/{roundId}`
```ts
{
  id: string
  courseId: string
  courseName: string
  totalHoles: 9 | 18
  lobbyCode: string       // 6-char uppercase
  status: "lobby" | "active" | "finished"
  hostId: string
  players: {
    [userId: string]: {
      name: string
      avatar: string
      totalScore: number  // updated after each hole
      scoreDiff: number   // vs par (+ or -)
    }
  }
  startedAt: Timestamp
  finishedAt: Timestamp | null
  createdAt: Timestamp
}
```

### `rounds/{roundId}/holes/{holeNumber}`
```ts
{
  holeNumber: number      // 1–18
  par: number
  distanceMeters: number
  shots: {
    [userId: string]: {
      count: number       // total shots on this hole
      club: string        // last club used
      updatedAt: Timestamp
    }
  }
}
```

### `courses/{courseId}` (cache)
```ts
{
  id: string
  name: string
  location: GeoPoint
  distanceKm: number      // computed at query time, not stored
  totalHoles: 9 | 18
  par: number
  holes: Array<{
    number: number
    par: number
    distanceMeters: number
  }>
  source: string          // API source identifier
}
```

---

## 6. Real-Time Group Play

1. Host creates round → Firestore doc created with `status: "lobby"`, `lobbyCode` generated (random 6-char)
2. Guests open app → tap "Join Game" → enter code or scan QR
3. App queries `rounds` where `lobbyCode == input` → joins by adding self to `players` map
4. All players listen to `rounds/{roundId}` via `onSnapshot` → lobby updates live
5. Host taps "Start" → `status` changes to `"active"` → all devices navigate to hole tracker
6. On each hole, any player can edit any player's shots (by default edits own; tap player card to switch)
7. Every shot increment writes to `rounds/{roundId}/holes/{n}/shots/{userId}.count`
8. All listeners receive the update within ~500ms → UI updates without refresh
9. After hole 18, host (or auto) taps "Finish Round" → `status: "finished"`, `finishedAt` set → all navigate to Results

---

## 7. GPS Distance to Pin

- Browser `navigator.geolocation.watchPosition()` — updates every ~5s while on hole tracker screen
- Pin location = course hole's GPS coordinate (from Golf Course API or manual entry)
- Distance computed client-side: Haversine formula
- Displayed as: `↑ 142 m` with directional arrow
- Accuracy caveat: shown as approximate; no accuracy indicator needed for MVP

---

## 8. Handicap Calculation (WHS)

- Triggered when a round is marked `finished`
- Inputs: all `finished` rounds for user, each round's score differential = `(score - course par)`
- WHS algorithm (simplified for MVP):
  1. Take last 20 finished rounds (or fewer if less available)
  2. Sort by score differential ascending
  3. Take best 8 (lowest differentials)
  4. Average them × 0.96
  5. Round to 1 decimal
- Result stored in `users/{userId}.handicap`
- Displayed on Profile screen with trend chart (last 20 rounds)

---

## 9. Club Selector UX

- On hole tracker, club selector is a horizontal scrollable chip row
- Chips show abbreviated club names: "DRV", "5W", "7i", "PW", "PT"
- Selected chip: filled green background, white text
- Default selection: the club used on the previous hole (React state, session-only — not persisted to Firestore)
- Club list comes from `users/{userId}.clubs` (configured in Profile)

---

## 10. Error Handling

| Scenario | Behavior |
|---|---|
| No geolocation permission | Show manual course search (text input) |
| Offline during round | Writes queue in Firestore offline cache; sync on reconnect |
| Lobby code not found | Inline error: "Code not found. Check and try again." |
| GPS unavailable on hole | Hide distance badge; no error shown |
| Auth failure | Retry button; guest mode is post-MVP |

---

## 11. Out of Scope (Post-MVP)

- Push notifications ("Your turn")
- Weather integration
- Course map / hole layout diagram
- Social features (friends list, global leaderboard)
- Stroke play vs match play modes
- Video / photo capture on course
- Apple Watch companion
