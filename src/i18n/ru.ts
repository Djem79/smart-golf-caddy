import type { PluralForms } from './types'

// Canonical dictionary — the русский is the source of truth for wording.
// `en.ts` is typed as `typeof ru`, so a missing (or extra) key there is a
// `tsc` error, not a blank spot on screen. String literals here are widened
// to `string` by TypeScript (no `as const`), so `en.ts` only has to match
// shape, not exact Russian text.
export const ru = {
  common: {
    retry: 'Повторить',
    all: 'Все',
    // Plural forms for "лунка/лунки/лунок" (hole/holes), consumed via
    // `plural(n, locale, forms)`. Typed as `PluralForms` (not inferred as an
    // exact `{ one, few, many }` object) so English can supply just
    // `{ one, other }` without tripping excess/missing-property checks.
    holesWord: { one: 'лунка', few: 'лунки', many: 'лунок' } as PluralForms,
  },
  auth: {
    subtitle: 'Считайте удары, ведите статистику и играйте с друзьями — всё в одном месте.',
    signingIn: 'Вход...',
    signInWithGoogle: 'Войти через Google',
    termsNotice: 'Продолжая, вы соглашаетесь с условиями использования',
    errors: {
      popupBlocked: 'Браузер заблокировал всплывающее окно. Разрешите всплывающие окна для этого сайта.',
      unauthorizedDomain: 'Этот домен не разрешён в Firebase Authentication. Добавьте его в Firebase Console → Authentication → Settings → Authorized domains.',
      operationNotAllowed: 'Вход через Google не включён в Firebase Console (Authentication → Sign-in method).',
      networkFailed: 'Нет связи с серверами Firebase. Проверьте интернет.',
      tryAgain: 'Попробуйте ещё раз.',
      // `Ошибка входа (auth/foo).` — the leading half of the generic error;
      // the caller appends `detail || errors.tryAgain` after it.
      signInFailed: (code: string) => `Ошибка входа${code ? ` (${code})` : ''}.`,
    },
  },
  home: {
    welcome: 'Добро пожаловать',
    fallbackName: 'Голфер',
    lobbyOpen: 'Лобби открыто',
    continueRound: 'Продолжить раунд',
    returnToLobby: 'Вернуться в лобби',
    playedOf: (played: number, total: number) => `Пройдено ${played} из ${total}`,
    startNewRound: 'Начать новый раунд',
    quickStart: 'Быстрый старт без выбора поля',
    joinGame: 'Присоединиться к игре',
    loadError: 'Не удалось загрузить раунды',
    recentRounds: 'Последние раунды',
  },
}

export type Dictionary = typeof ru
