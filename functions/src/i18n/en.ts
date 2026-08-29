import type { Dictionary } from './ru'

// English dictionary. Typed as `Dictionary` (= `typeof ru`) so a missing
// key is a compile error — `npm run build` / `tsc --noEmit` fails instead
// of an English recipient silently seeing a blank spot (or `undefined`)
// in their inbox.
export const en: Dictionary = {
  title: 'Round summary',
  strokes: 'Strokes',
  holesWord: { one: 'hole', other: 'holes' },
  shotsWord: { one: 'stroke', other: 'strokes' },
  winner: 'Winner',
  playersEven: 'Players are even',
  scorecardTitle: 'Scorecard',
  bestHoleTitle: 'Best hole',
  onPar: 'on par',
  favoriteClubsTitle: 'Favorite clubs',
  ctaButton: 'Open full results',
  footer: 'This is an automated email. Smart Golf Caddy · smart-golf-caddy.web.app',
  worseLabel: 'Worse',
  playerFallback: 'Player',
  clubFallback: 'Club',
  // Matches the English wording already used in web/iOS delete-account
  // copy ("Removed player") — see src/i18n/en.ts deleteConfirmBody and
  // ios/SmartGolfCaddy/Models/Localization/Strings.swift.
  deletedPlayerName: 'Removed player',
}
