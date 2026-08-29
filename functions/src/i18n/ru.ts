import type { PluralForms } from './types'

// Canonical dictionary for the round-summary email — the русский is the
// source of truth for wording, same convention as the web app's
// src/i18n/ru.ts. `en.ts` is typed as `typeof ru`, so a missing (or extra)
// key there is a `tsc` error, not a blank spot in someone's inbox.
//
// Scope is deliberately narrow: only strings the email template
// (RoundSummary.tsx) and payload builder (buildPayload.ts) actually need.
// Golf jargon that's used verbatim in both languages today (Match play,
// Hole/Par/OUT/IN/TOTAL column headers, the 'E' even-par notation) is left
// as literals in the component — see RoundSummary.tsx — mirroring the
// same choice already made on the web (src/screens/Leaderboard.tsx keeps
// 'E' unlocalized, roundResults.matchPlay is 'Match play' in both en/ru).
export const ru = {
  // Shared between the <Heading> in the email body and the subject line.
  title: 'Итоги раунда',
  strokes: 'Удары',
  holesWord: { one: 'лунка', few: 'лунки', many: 'лунок' } as PluralForms,
  shotsWord: { one: 'удар', few: 'удара', many: 'ударов' } as PluralForms,
  winner: 'Победитель',
  playersEven: 'Игроки на равных',
  scorecardTitle: 'Карта счёта',
  bestHoleTitle: 'Лучшая лунка',
  onPar: 'на пар',
  favoriteClubsTitle: 'Любимые клюшки',
  ctaButton: 'Открыть полные итоги',
  footer: 'Это автоматическое письмо. Smart Golf Caddy · smart-golf-caddy.web.app',
  // categorize() 'worse' bucket (diff >= 3). 'empty' (no shots recorded)
  // stays '—' in both locales — see formatDiff/categoryLabel in types.ts.
  worseLabel: 'Хуже',
  // Fallback shown when a player's name is missing entirely (very old
  // data, or a lookup failure) — matches web's common.player: 'Игрок'.
  playerFallback: 'Игрок',
  // Fallback for a custom club id that resolveClubLabel can't find in the
  // owner's bag — matches web's common.clubLabels.missingCustom: 'Клюшка'.
  clubFallback: 'Клюшка',
  // Localized stand-in for the literal Russian string deleteAccount()
  // writes into players.{uid}.name when anonymising a departed group-round
  // participant (functions/src/index.ts, DELETED_PLAYER_NAME in
  // emails/buildPayload.ts). Matches the wording already used in the web
  // and iOS delete-confirmation copy ("«Удалённый игрок»" / "Removed
  // player") so the term is consistent across the whole product.
  deletedPlayerName: 'Удалённый игрок',
}

export type Dictionary = typeof ru
