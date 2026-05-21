import { initializeApp } from 'firebase/app'
import { initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check'
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

// App Check attests that requests come from our real app before backends
// (the Cloud Functions callables) accept them. Initialised right after the
// app and before any service that makes backend calls. Entirely no-op until
// VITE_APP_CHECK_SITE_KEY (a reCAPTCHA v3 site key) is set, so dev/CI builds
// without a key keep working. Enable enforcement on the callables only AFTER
// this is deployed and tokens are seen in the Firebase console, or every call
// will be rejected.
const appCheckSiteKey = import.meta.env.VITE_APP_CHECK_SITE_KEY as string | undefined
if (appCheckSiteKey) {
  // For local dev / CI against a registered debug token: setting this global
  // before initializeAppCheck makes the SDK mint a debug token instead of
  // calling reCAPTCHA. Register the printed token in Firebase console.
  const debugToken = import.meta.env.VITE_APP_CHECK_DEBUG_TOKEN as string | undefined
  if (debugToken) {
    ;(self as unknown as { FIREBASE_APPCHECK_DEBUG_TOKEN?: string | boolean }).FIREBASE_APPCHECK_DEBUG_TOKEN =
      debugToken
  }
  initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(appCheckSiteKey),
    isTokenAutoRefreshEnabled: true,
  })
}

export const auth = getAuth(app)
export const db = getFirestore(app)
