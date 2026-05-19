# Tasks — Sprint 6 (Post-round email infographic)

Source: 2026-05-19 user request — "после окончания игры скидывать
игрокам письма с инфографикой как у Golfshot", потом — «и кнопку
поделиться результатом на вкладке итоги раунда».

Референс: Golfshot scorecard email (разбор сабагентом).
Стек (утверждено): **Resend** + **react-email**, dev-режим через
`onboarding@resend.dev` (письма только на верифицированный
аккаунт владельца проекта; для прод-рассылки добавим домен позже).

## Active

- [ ] **1. Foundation — Cloud Functions + email-зависимости**
  - `firebase init functions` → TypeScript, Node 20, без линтера
    функций (используем корневой eslint).
  - В `functions/`: `npm i resend react @react-email/components`,
    `npm i -D @react-email/render @types/react esbuild`.
  - Обновить `firebase.json` — секция `functions` с предеплой-билдом.
  - Завести Functions secret `RESEND_API_KEY` (документ в SETUP.md;
    в коде — `defineSecret`).
  - Завести env `MAIL_FROM` (= `Smart Golf Caddy <onboarding@resend.dev>`
    по умолчанию).

- [ ] **2. Data model — email в PlayerInfo**
  - `types/index.ts`: `PlayerInfo.email?: string`.
  - `services/rounds.ts`:
    - `createRound`: писать `players[hostId].email = hostInfo.email`.
    - `joinRoundByCode`: писать `players[uid].email`.
  - `screens/RoundSetup` / `JoinGame` / `HoleTracker`: при формировании
    `PlayerInfo` подставлять `user.email ?? ''`.
  - Старые раунды не апгрейдим: функция просто скипнет игроков без email.

- [ ] **3. Email-шаблон `RoundSummary.tsx`** (functions/src/emails/)
  - React-email компоненты: Html/Head/Preview/Container/Section/Row/
    Column/Heading/Text/Hr/Button.
  - 600 px ширина, mobile-first, dark-mode-aware (`@media`).
  - Структура сверху вниз:
    1. **Header** — wordmark «Smart Golf Caddy» на primary-container.
    2. **Hero** — название поля, дата, тип раунда; **большая дельта vs par**
       (display-lg) + total score + кол-во лунок.
    3. **Match-play banner** (опционально) — `X UP` / `N&M` / `AS`,
       победитель.
    4. **Scorecard** — таблица 9 или 18 лунок:
       - Колонки: hole #, Par, Score (pill), ±Par.
       - Цвета pill: eagle `#7C3AED`, birdie `#42A5F5`, par `#66BB6A`,
         bogey `#757575`, double `#EF5350`, worse `#9A1A1A`.
       - OUT / IN / TOTAL — серые агрегатные строки.
    5. **Insight** — «Лучшая лунка: №3, birdie на пар-4».
    6. **Клюшки** — top-3 по использованию, числами + %.
    7. **CTA** — кнопка «Открыть полные итоги» → smart-golf-caddy.web.app/
       round/{id}/results.
    8. **Footer** — отписка (пока заглушка), copyright.
  - Шрифт: -apple-system / Segoe UI fallback (без Google Fonts — почтовики
    режут или не подгружают).
  - Превью: `react-email dev` в браузере на 3000.

- [ ] **4. Cloud Function — `onRoundFinished`**
  - Триггер: `firestore.document('rounds/{id}').onUpdate`.
  - Гарды:
    - `before.status !== 'finished' && after.status === 'finished'`.
    - `after.emailedAt == null` (идемпотентность).
  - Для каждого `playerIds[]`:
    - Резолвить email из `players[uid].email` (skip если пусто).
    - Рендер шаблона с данными игрока (его scorecard, его стат).
    - `resend.emails.send({ from, to, subject, html })`.
    - Лог в Functions logger.
  - После успешной рассылки: `tx.update({ emailedAt: serverTimestamp() })`.

- [ ] **5. Local testing — Functions emulator + react-email dev**
  - `firebase emulators:start --only functions,firestore`.
  - Тестовый скрипт `scripts/send-test-round.ts` — пишет фейковый
    раунд со статусом active → finished.
  - react-email превью на 3000.
  - Sanity: убедиться что письмо приходит на tdm.979@gmail.com.

- [ ] **6. SETUP.md — инструкция настройки Resend**
  - Регистрация на resend.com (1 мин).
  - Создание API key.
  - `firebase functions:secrets:set RESEND_API_KEY`.
  - (Опционально) добавление и верификация custom domain.
  - Обновить README/SETUP.md.

- [ ] **7. RoundResults: «Поделиться результатом»**
  - На RoundResults — иконка `<Share2/>` в PageHeader right slot.
  - При клике:
    - `navigator.share({ title, text, url })` если доступно — нативный
      share sheet (Telegram/WhatsApp/Mail).
    - Fallback: dialog c полем email и кнопкой «Отправить».
  - Новая callable-функция `sendRoundEmailToAddress(roundId, email)` —
    использует тот же шаблон + Resend.
  - Rate-limit: 5 запросов на пользователя в час (Firestore counter
    или Functions runtime — оставим pragmatic-логику в коде функции).

- [ ] **8. Verification + deploy**
  - `npx tsc --noEmit` (root + functions/).
  - `npm run lint`.
  - `npm run test:run` — 113/113 минимум; добавить unit для
    `pickInsight()` если будет нетривиальная логика.
  - `npm run build` для веба.
  - `firebase deploy --only functions,hosting`.
  - Smoke: создать solo-раунд, завершить, дождаться письма.

## Verification gate

- tsc / lint / tests / build — clean.
- Письмо приходит и читается на iOS Mail, Gmail web, Outlook web.
- Кнопка «Поделиться» открывает share sheet на телефоне.
- Старые завершённые раунды (`emailedAt == null` исторически) НЕ
  получают рассылку post-factum.

## Review

_(заполнится после спринта)_
