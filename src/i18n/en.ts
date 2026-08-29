import type { Dictionary } from './ru'

// English dictionary. Typed as `Dictionary` (= `typeof ru`) so a missing key
// is a compile error — `tsc` fails the build instead of the UI silently
// falling back to nothing. Keep translations short and idiomatic: the layout
// is a fixed 390px-wide mobile screen, and English strings tend to run
// longer than Russian, so prefer concise phrasing over literal translation.
export const en: Dictionary = {
  common: {
    retry: 'Retry',
    all: 'All',
    holesWord: { one: 'hole', other: 'holes' },
  },
  auth: {
    subtitle: 'Track your strokes, keep stats, and play with friends — all in one place.',
    signingIn: 'Signing in...',
    signInWithGoogle: 'Sign in with Google',
    termsNotice: 'By continuing, you agree to the Terms of Use',
    errors: {
      popupBlocked: 'Your browser blocked the pop-up. Allow pop-ups for this site.',
      unauthorizedDomain: "This domain isn't authorized in Firebase Authentication. Add it in Firebase Console → Authentication → Settings → Authorized domains.",
      operationNotAllowed: "Google sign-in isn't enabled in Firebase Console (Authentication → Sign-in method).",
      networkFailed: "Can't reach Firebase servers. Check your connection.",
      tryAgain: 'Try again.',
      signInFailed: (code: string) => `Sign-in error${code ? ` (${code})` : ''}.`,
    },
  },
  home: {
    welcome: 'Welcome',
    fallbackName: 'Golfer',
    lobbyOpen: 'Lobby open',
    continueRound: 'Continue round',
    returnToLobby: 'Return to lobby',
    playedOf: (played: number, total: number) => `Played ${played} of ${total}`,
    startNewRound: 'Start new round',
    quickStart: 'Quick start without picking a course',
    joinGame: 'Join a game',
    loadError: "Couldn't load rounds",
    recentRounds: 'Recent rounds',
  },
}
