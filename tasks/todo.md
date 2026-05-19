# Tasks — Sprint 4 (GameBook-inspired features)

Source: Golf GameBook analysis 2026-05-19 + Plan 1 handicap debt.

## Active

- [x] **1. Расширенная статистика игрока + WHS handicap**
  - `services/scoring.ts`: new `computePlayerStats(rounds, userId)` that
    returns `{ roundsPlayed, totalShots, avgShots, bestScore,
    bestScoreDiff, holeStats: {eagle/birdie/par/bogey/double/worse},
    totalHolesPlayed }`. Iterates finished rounds, tallies hole-level
    deltas.
  - `services/scoring.ts`: new `computeHandicap(rounds, userId)` —
    simplified WHS: score differential = (score − sum of pars played),
    take best 8 of last 20, average × 0.96. Returns null when fewer
    than 3 rounds (not enough data).
  - Profile screen: replace "Сводка" with new stats card showing
    rounds / avg / best / all-time best, plus a percentage breakdown
    bar across the six result types using existing `scoreColor`.
  - Profile: replace "Гандикап скоро будет доступен" placeholder with
    real number when available (or "сыграйте ещё N раундов" hint).
  - Tests: 6+ for computePlayerStats + computeHandicap.

- [x] **2. Live leaderboard during a round**
  - `services/scoring.ts`: `computeLeaderboard(round)` returning
    `Array<{ uid, name, avatar, totalScore, scoreDiff, thru }>` sorted
    by `scoreDiff` asc; ties broken by `totalShots` then by name.
  - `thru` = number of holes where the player has recorded ≥ 1 shot.
  - New screen `Leaderboard.tsx` at `/round/:roundId/leaderboard`.
    Subscribes to round, renders sorted table.
  - Add a "Таблица" button in HoleTracker's PageHeader right slot
    (next to / replacing Финиш link is too crowded — keep both,
    leaderboard is a separate icon).
  - Leaderboard screen has a "← Назад к лунке" button.

- [x] **3. Match play mode**
  - `types/index.ts`: `PlayMode = 'stroke' | 'match'`; add
    `Round.playMode?: PlayMode` (default 'stroke').
  - `services/rounds.ts`: `createRound(..., playMode?)` writes it.
  - `services/scoring.ts`: `computeMatchPlayStatus(round, holesPlayed)`
    for 2-player rounds — returns `{ leaderUid, holesUp, status }`
    where status is 'X UP' / 'X DOWN' / 'AS' / 'CLOSED' (if mathematically
    decided: e.g. 4&3 means leader is 4 up with 3 to play).
  - RoundSetup: new "Stroke play / Match play" toggle next to mode
    selector. Match play disabled when mode === 'solo' (need ≥ 2
    players); falls back to stroke play.
  - Leaderboard screen: when playMode === 'match' and players.length
    === 2, show match-play format (X UP / DOWN / AS) instead of
    stroke totals.
  - RoundResults: show match result as the headline for match-play
    rounds.

## Verification gate

- `npx tsc --noEmit` clean
- `npm run test:run` — all pass including new scoring tests
- `npm run lint` clean
- `npm run build` succeeds
- Deploy + manual smoke test: create a stroke-play group round,
  see leaderboard; create a 2-player match-play round, see X UP/DOWN.

## Review

Sprint 4 wrapped 2026-05-19. Все три задачи отгружены, верификация чистая
(113/113 тестов, tsc + lint + build OK).

**Shipped:**

- `computePlayerStats` + `computeHandicap` в `services/scoring.ts`;
  Profile теперь показывает rounds/avg/best/diff, цветной стек по
  типам лунок и реальный WHS-индекс (или подсказку «сыграйте ещё
  N раундов»).
- `computeLeaderboard` + новый экран `Leaderboard.tsx` на
  `/round/:roundId/leaderboard`; HoleTracker получил кнопку 🏆 в
  правый слот PageHeader.
- `PlayMode = 'stroke' | 'match'` в types/index.ts;
  `Round.playMode` пишется в `createRound`. Match play доступен
  только в групповом режиме (solo всегда стрейк-плей).
- RoundSetup: блок «Формат игры» (Stroke/Match) появляется при
  выборе группового режима.
- `computeMatchPlayStatus` возвращает `{ leaderUid, trailerUid,
  holesPlayed, holesRemaining, delta, label, closed }`, метки
  AS / N UP / N&M / FINAL. Leaderboard показывает баннер
  match-status. RoundResults — match-play хедлайн вместо
  «Победитель» для 2-игроковых матч-плей раундов.
- Тесты: 17 новых юнитов покрыли все 4 функции; `makeMatch`-фикстура
  допиливает массив `holes` до полной длины раунда, чтобы N&M-сценарии
  считались корректно.

**Известные ограничения, не входившие в спринт:**

- Match play >2 игроков не поддерживается — старые групповые
  раунды без `playMode` остаются stroke-play.
- Bundle всё ещё ~605 kB; React.lazy уже на основных экранах,
  дальнейшая оптимизация — отдельный спринт.
