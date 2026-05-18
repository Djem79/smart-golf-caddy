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

## Step 4 — Google Places API key

The course search uses the Places API to find golf courses near the user.

1. Go to https://console.cloud.google.com — make sure your **Firebase project** is selected in the top-left dropdown (it's automatically a Google Cloud project)
2. Sidebar: **APIs & Services → Library**
3. Search for **"Places API"** (the **legacy** one, not "Places API (New)") — click **Enable**
4. Sidebar: **APIs & Services → Credentials**
5. Click **+ CREATE CREDENTIALS → API key**
6. Copy the key — paste into `.env.local`:
   ```
   VITE_GOOGLE_PLACES_API_KEY=AIza...
   ```
7. **Important — restrict the key** (don't skip; otherwise anyone can use it):
   - Click the new key → **Application restrictions → HTTP referrers (web sites)**
   - Add referrers:
     - `http://localhost:5173/*` (dev)
     - `https://YOUR-PROJECT.web.app/*` (production, fill in after deploy)
   - **API restrictions → Restrict key → Select APIs → "Places API"**
   - Save

> **Billing note:** Google requires a billing account for Places API, but the free tier is generous (~$200/month credit). For development you'll use pennies.

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

## Step 6 — Deploy Firestore security rules

The repo ships with `firestore.rules` (users can read/write own profile + rounds they host or play in).

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
firebase login        # opens browser, sign in with the Google account that owns the project
firebase deploy --only firestore:rules
```

If you also want to deploy the index for `getUserRounds`:

```bash
firebase deploy --only firestore:indexes
```

---

## Step 7 — Run locally

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
npm run dev
```

Open http://localhost:5173 — you should see the Auth screen. Click **"Войти через Google"** to sign in.

> If browser prompts for geolocation permission — allow it (CourseSearch screen needs it).

---

## Step 8 — Deploy to Firebase Hosting (optional, for testing on phone)

```bash
npm run build
firebase deploy --only hosting
```

You'll get a URL like `https://smart-golf-caddy-xxxxx.web.app` — open it on your phone, "Add to Home Screen" in Safari/Chrome → installs as a PWA.

---

## Troubleshooting

| Problem | Likely cause |
|---|---|
| Auth popup closes silently | Pop-up blocker; or `localhost` is not in Firebase Auth's "Authorized domains" (Console → Auth → Settings) |
| "Places API error: REQUEST_DENIED" | Places API not enabled, or key restricted to the wrong domain |
| "Missing or insufficient permissions" on Firestore reads | Rules not deployed; run `firebase deploy --only firestore:rules` |
| Recent rounds empty after finishing a round | Firestore index not created — Firebase console will print a one-click link to create it the first time the query runs |
| Geolocation not working | HTTPS or `localhost` required; check site permissions in browser settings |

---

## What's in this repo

| File | Purpose |
|---|---|
| `.env.example` | Template for env vars (commit-safe) |
| `.env.local` | **Your actual secrets** (gitignored — never commit) |
| `firebase.json` | Hosting + Firestore deploy config |
| `.firebaserc` | Firebase project ID |
| `firestore.rules` | Security rules (deploy via `firebase deploy --only firestore:rules`) |
| `firestore.indexes.json` | Composite indexes for queries |
| `public/manifest.json` | PWA manifest |
| `public/icon.svg`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png` | App icons |
| `scripts/generate-icons.mjs` | Regenerate icons from `public/icon.svg` if you change it |
