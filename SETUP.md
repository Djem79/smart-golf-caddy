# Smart Golf Caddy — Setup Guide

Step-by-step instructions to wire up Firebase + Google Places API and run the app locally.

---

## Prerequisites

- Node.js 20+ (nvm recommended)
- A Google account (for Firebase Console + Google Cloud Console)
- ~10 minutes of clicking through web consoles

---

## Step 1 — Create a Firebase project

1. Open https://console.firebase.google.com
2. Click **"Create a project"** (or "Добавить проект")
3. Name it `smart-golf-caddy` (or anything you like)
4. **Disable Google Analytics** (we don't need it for MVP — saves complexity)
5. Click **"Create project"**, wait ~30 seconds, then click **"Continue"**

Copy the **Project ID** shown at the top of the dashboard (usually `smart-golf-caddy-xxxxx`). You'll need it.

---

## Step 2 — Enable services in Firebase

### 2a. Enable Authentication (Google Sign-In)

1. In the Firebase Console sidebar: **Build → Authentication → Get started**
2. On the "Sign-in method" tab, click **Google**
3. Toggle **Enable** → set a **Project support email** (your email) → **Save**

### 2b. Enable Firestore

1. Sidebar: **Build → Firestore Database → Create database**
2. Choose **Start in test mode** (we'll deploy proper rules in Step 6, but this gets you started)
3. Pick a location closest to you (e.g. `europe-west3` for Europe)
4. Click **Enable**

### 2c. Add a Web App

1. In Firebase Console, click the **gear icon → Project settings**
2. Scroll to **"Your apps"** → click the **`</>` (Web)** icon
3. App nickname: `Smart Golf Caddy Web` → click **Register app**
4. You'll see a code snippet with `firebaseConfig = { ... }` — **keep this tab open**, you'll copy values from it next

---

## Step 3 — Fill in `.env.local`

In the project root, create `.env.local` (it's gitignored — never commit it):

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
cp .env.example .env.local
```

Open `.env.local` and fill in the 6 Firebase values from the `firebaseConfig` snippet you saw in Step 2c:

```
VITE_FIREBASE_API_KEY=AIza...
VITE_FIREBASE_AUTH_DOMAIN=smart-golf-caddy-xxxxx.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=smart-golf-caddy-xxxxx
VITE_FIREBASE_STORAGE_BUCKET=smart-golf-caddy-xxxxx.appspot.com
VITE_FIREBASE_MESSAGING_SENDER_ID=123456789012
VITE_FIREBASE_APP_ID=1:123...:web:abc...
VITE_GOOGLE_PLACES_API_KEY=  # we'll fill this in Step 4
```

---

## Step 4 — Google Places API (New)

Course search (nearby + by-name) uses **Places API (New)** — the modern CORS-friendly REST endpoint at `places.googleapis.com/v1/`. The **legacy** Places API at `maps.googleapis.com/maps/api/place/*` does NOT send CORS headers and fails from any HTTPS origin other than localhost.

### 4a. Enable Places API (New)

1. Go to https://console.cloud.google.com — make sure your **Firebase project** is selected in the top-left dropdown
2. Direct link: https://console.cloud.google.com/apis/library/places.googleapis.com?project=YOUR-PROJECT-ID
3. Click **ENABLE**

> If you already had the legacy Places API enabled — keep it, the new key works with both. Just make sure the **New** one is also on.

### 4b. Create / configure the API key

1. Sidebar: **APIs & Services → Credentials**
2. If a key exists for this project (e.g. "API key 2"), click into it. Otherwise: **+ CREATE CREDENTIALS → API key**
3. Copy the key — paste into `.env.local`:

   ```
   VITE_GOOGLE_PLACES_API_KEY=AIza...
   ```

4. **Restrict the key** (don't skip):
   - **Application restrictions → HTTP referrers (web sites):**
     - `http://localhost:5173/*` (dev)
     - `https://YOUR-PROJECT.web.app/*` (production)
     - `https://YOUR-PROJECT.firebaseapp.com/*` (alt production)
   - **API restrictions → Restrict key** → in the dropdown select:
     - ✅ **Places API (New)** (required)
     - ✅ **Places API** (optional, for legacy compat)
     - ✅ **Maps JavaScript API** (optional, future-proofing)
   - **Save** — changes apply in 1-5 minutes

### 4c. Do NOT restrict the Firebase "Browser key"

When you create the Firebase web app (Step 2c), Firebase auto-creates a second API key called **"Browser key (auto created by Firebase)"**. This one is used by Firebase Auth (Identity Toolkit API), Firestore, etc.

**Leave its API restrictions either unrestricted, or include `Identity Toolkit API` + `Cloud Firestore API` + `Token Service API` in the allowlist.** Restricting it to only Places APIs will break Google Sign-In with an `auth/requests-to-this-api-identitytoolkit-...are-blocked` error.

> **Billing note:** Google requires a billing account for the new Places API. The free tier covers ~$200/month of usage — for development and a small group of users you'll pay nothing.

---

## Step 5 — Update `.firebaserc`

Edit `.firebaserc` and replace the placeholder with your real project ID:

```json
{
  "projects": {
    "default": "smart-golf-caddy-xxxxx"
  }
}
```

---

## Step 6 — Deploy Firestore security rules + indexes

The repo ships with `firestore.rules` (field-aware: separate branches for join / leave / start / record-shot / finish, see `firestore.rules` for details) and `firestore.indexes.json` (two composite indexes: `playerIds + createdAt desc` for round history, and `lobbyCode + status` for the group-play join-by-code query).

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
firebase login        # opens browser; sign in with the Google account that owns the project
firebase deploy --only firestore   # deploys both rules and indexes
```

If indexes are missing, the first time the app queries Firestore it will throw an error in the console with a one-click "Create index" link. Either click that link or re-run `firebase deploy --only firestore`.

---

## Step 7 — Run locally

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
npm run dev
```

Open http://localhost:5173 — you should see the Auth screen. Click **"Войти через Google"** to sign in.

> If browser prompts for geolocation permission — allow it (CourseSearch screen needs it).

---

## Step 8 — Deploy to Firebase Hosting

```bash
npm run build
firebase deploy --only hosting
```

You'll get a URL like `https://smart-golf-caddy-xxxxx.web.app` — open it on your phone, "Add to Home Screen" in Safari/Chrome → installs as a PWA.

### 8a. Add the deployed domain to Firebase Auth's Authorized domains

Firebase Auth rejects sign-in popups from any domain not in its allow-list.

1. Firebase Console → **Authentication → Settings → Authorized domains**
2. Add `smart-golf-caddy.web.app` (or your actual hosting domain)

`localhost` and `*.firebaseapp.com` are usually pre-added, but `.web.app` is **not** automatic.

---

## Group play — deep links

The lobby code can be shared as a 6-character string or via a QR code that encodes:

```
https://YOUR-PROJECT.web.app/join/<LOBBY_CODE>
```

The receiving device opens that URL → the app navigates to `/join/<CODE>` → if the user is signed in, it auto-attempts to join the lobby. If not signed in, it goes through auth first and you have to retype the code.

For this deep-link to work, make sure your deployed domain is in **Firebase Auth → Authorized domains** (Step 8a) so the popup-based sign-in flow works from a fresh visit.

---

## Troubleshooting

| Problem | Likely cause |
|---|---|
| `auth/requests-to-this-api-identitytoolkit-...are-blocked` | The Firebase "Browser key" has API restrictions that exclude Identity Toolkit API. Either unrestrict it, or add `Identity Toolkit API` to its allow-list. |
| `auth/unauthorized-domain` | The deployed domain isn't in Firebase Auth → Settings → Authorized domains. Add `smart-golf-caddy.web.app`. |
| Auth popup closes silently | Pop-up blocker; or the user closed it (we silently ignore `auth/popup-closed-by-user`). |
| `TypeError: Load failed` on course search | You're calling the legacy Places endpoint (`maps.googleapis.com`) which has no CORS. We migrated to Places API (New) — make sure the new API is **enabled** in Cloud Console and the key allows it. |
| "Доступ к Places API (New) запрещён" (403) | Either Places API (New) is not enabled, or your current host isn't in the API key's HTTP referrers. |
| "Missing or insufficient permissions" on Firestore reads/writes | Rules not deployed; run `firebase deploy --only firestore`. |
| Recent rounds empty after finishing a round | Composite index not built yet — Firestore console will print a one-click "Create index" link, or run `firebase deploy --only firestore`. |
| Geolocation prompt doesn't appear (iOS Safari) | We added a manual "📍 Определить местоположение" button on the CourseSearch screen; tap that to trigger the prompt from a user gesture. |
| Custom clubs appear at the end of the picker instead of inside their category | Should be fixed in current builds. Re-add the custom club; it inserts at the end of its category. |

---

## What's in this repo

| File | Purpose |
|---|---|
| `.env.example` | Template for env vars (commit-safe) |
| `.env.local` | **Your actual secrets** (gitignored — never commit) |
| `firebase.json` | Hosting + Firestore deploy config |
| `.firebaserc` | Firebase project ID |
| `firestore.rules` | Security rules (field-aware per-action); deploy via `firebase deploy --only firestore` |
| `firestore.indexes.json` | Composite indexes: `playerIds + createdAt desc` (round history) and `lobbyCode + status` (group play join lookup) |
| `public/manifest.json` | PWA manifest |
| `public/icon.svg`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png` | App icons |
| `scripts/generate-icons.mjs` | Regenerate PNG icons from `public/icon.svg` if you redesign it |
| `CLAUDE.md` | Architecture + workflow guide for Claude Code / agents |
| `tasks/todo.md`, `tasks/lessons.md` | Sprint plan + accumulated lessons |
