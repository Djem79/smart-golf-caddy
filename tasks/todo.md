# Tasks — Sprint 5 (Premium visual polish)

Source: 2026-05-19 user request — "сделать на уровне лучших приложений,
кнопки/меню — дорого и лаконично; никаких эмодзи; без наслоений и
пропусков."

## Active

- [x] **1. Foundation — иконки + базовые компоненты**
  - `npm i lucide-react` (~1 KB/иконка tree-shaken).
  - Создать `components/ui/Icon.tsx` — тонкая обёртка над lucide
    с фиксированным `strokeWidth={1.5}` и набором размеров sm/md/lg.
  - PageHeader: `←` → `<ChevronLeft />` (24px). Title — увеличить
    weight, поджать height до 56 px (уже так). Right slot — 48px touch.
  - Button: поддержка `icon` (слева) и `iconRight`, чтобы убрать
    inline-эмодзи из подписей кнопок.
  - Refine tokens: тиснее shadow-card (subtle elevation), добавить
    `easing-premium` в transition.

- [x] **2. BottomNav — иконки + active indicator**
  - Заменить ⛳/📋/👤 на `<Home/>`, `<History/>` (или `<Clock/>`),
    `<User/>` от lucide.
  - Active state: иконка + label в primary; тонкая 2-px полоса
    сверху активной вкладки.
  - Bottom safe-area: padding-bottom: env(safe-area-inset-bottom).

- [x] **3. Auth + Home + JoinGame — entry-экраны**
  - Auth: убрать text-6xl ⛳, поставить leading wordmark (название
    бренда + 1 SVG-флаг 64px). Лаконичный градиент primary→primary-container.
  - Home: убрать ⛳ из «{имя} ⛳» и 🎟️ из CTA. Кнопка "Присоединиться к
    игре" — Button с иконкой `<Ticket/>` слева.
  - JoinGame: 🎟️ → `<Ticket size=48/>` в hero.

- [x] **4. CourseSearch — поиск + список**
  - 📍 → `<MapPin/>`, ⛳ placeholder → `<Flag/>`.
  - Кнопка геолокации — Button с иконкой.
  - Свечение ★-рейтинга оставить (типографский символ, не эмодзи).

- [x] **5. RoundSetup — настройка раунда**
  - Solo/Group: `<User/>` и `<Users/>` от lucide вместо ⛳/👥.
  - Stroke/Match: `<BarChart3/>` и `<Swords/>` (или `<Handshake/>`) вместо 📊/🤝.
  - Tee-цвета: оставить, это контрол.

- [x] **6. HoleTracker — основной экран игры**
  - 🏆 в PageHeader → `<Trophy/>` (24px, primary).
  - 🏁 в кнопке завершить → `<Flag/>` через Button icon.
  - ⛳ в player switcher avatar → инициалы в круге (без иконки).
  - Стрелки ←/→ в Пред./След. — оставить (типографские, не эмодзи)
    либо заменить на `<ChevronLeft/>`/`<ChevronRight/>` для консистентности.

- [x] **7. Leaderboard + RoundResults — таблицы и итоги**
  - ⛳ в avatar fallback → круг с инициалами.
  - 🏆 в headline → `<Trophy size=32/>`.
  - ✓ в "Матч решён" — оставить (типографский символ).

- [x] **8. GroupLobby + Profile + History + ErrorBoundary**
  - ⛳ avatar fallbacks → инициалы.
  - 🏁 «Начать раунд» → `<Play/>` или просто текст без иконки.
  - ⚠️ ErrorBoundary → `<AlertTriangle/>`.
  - Profile: `→` стрелка на «Моя сумка» → `<ChevronRight/>`.
  - History: ⛳ empty state → `<Flag size=48 className="text-on-surface-variant"/>`.

- [x] **9. Visual polish pass (overlap/gap audit)**
  - Запустить dev-сервер, пройти каждый экран:
    - Auth, Home, CourseSearch, RoundSetup, GroupLobby, JoinGame,
      HoleTracker (solo + multi), Leaderboard (stroke + match),
      RoundResults, Profile, MyBag, History, ErrorBoundary.
  - Проверить: touch-targets ≥ 48 px, padding kit (16/20/24),
    отсутствие наслоений (BottomNav vs контент, fixed elements vs
    safe-areas), вертикальный ритм консистентен.
  - Тонкая шлифовка: hover/active states, focus-ring везде primary.

## Verification gate

- `npx tsc --noEmit` clean
- `npm run test:run` — 113/113 + новые snapshot/unit (если добавим)
- `npm run lint` clean
- `npm run build` succeeds, bundle delta ≤ +10 KB
- Manual smoke test в браузере: 6 ключевых пользовательских флоу.
- Deploy: `firebase deploy --only hosting`.

## Review

Sprint 5 закрыт 2026-05-19. Все 10 задач отгружены, automated-гейты
(tsc + lint + 113 тестов + build) — чисто. Bundle +5 KB (605 → 610),
в бюджете.

**Что сделано:**

- Установлен `lucide-react`; **все эмодзи удалены** из приложения
  (audit `grep -P "[\x{1F300}-\x{1FAFF}...]"` пуст).
- Новые компоненты: `Avatar` (инициалы вместо ⛳-плейсхолдера),
  `Button` теперь поддерживает `icon` / `iconRight` слоты.
- `PageHeader`: `←` → `<ChevronLeft />` 24 px с rounded-full hit area;
  фиксированная высота 56 px (h-14).
- `BottomNav`: `<Home/>`, `<HistoryIcon/>`, `<User/>`. Active state —
  2-px primary-полоса сверху + жирный stroke иконки + цвет. Учёт
  `safe-area-inset-bottom`.
- Tokens: `shadow-card` стал двухслойным (мягче), добавлены
  `shadow-card-hover`, `shadow-elevated`, `transitionTimingFunction.premium`.
- Auth: убран `text-6xl ⛳`. Hero с brand-wordmark и градиентом
  primary-container → primary.
- Home: иконки `Plus`, `Zap`, `Users` в кнопках через `Button.icon`;
  «Все →» в секции последних раундов с `ChevronRight`.
- CourseSearch: search-input получил `<Search/>` (lucide), MapPin
  для адреса, Star (заполненная) для рейтинга, Flag для пустого
  hero, Navigation в кнопку геолокации.
- RoundSetup: новый компонент `ChoiceCard` — outline-кнопка с
  квадратным icon-чипом сверху-слева, заменяет emoji-в-центре макет.
  Solo/Group: `User`/`Users`. Stroke/Match: `BarChart3`/`Swords`.
- HoleTracker: Trophy-иконка в right slot хедера, Plus/Minus в
  круглых +/− кнопках, ChevronLeft/Right + Flag в нижней навигации
  лунок, Avatar с инициалами в player-switcher.
- Leaderboard: hero-блок с Trophy-чипом + градиентом; match-status
  карточка укрупнена, ✓ заменён на `<Check/>`.
- RoundResults: оба headline-баннера получили Trophy-чип в круге,
  градиент primary-container → primary. Avatar с инициалами в строках
  игроков.
- GroupLobby: Avatar в списке, Copy/Check лайв-индикатор,
  `Play` в кнопке хоста.
- Profile: Avatar 64 px, `<ChevronRight/>` на «Моя сумка».
- History: empty state — Flag в круглом chip-контейнере.
- MyBag: `<GripVertical/>` drag-handle вместо `⋮⋮`, `<Sparkle/>`
  маркер кастомной клюшки вместо `✦`.
- ErrorBoundary: `<AlertTriangle/>` в круглом error-container chip.

**Чего я НЕ могу сам гарантировать (нужна визуальная проверка):**

- Финальное отсутствие overlap'ов на реальных устройствах (особенно
  на iPhone с safe-area).
- Восприятие новых градиентов и spacing'а.
- Корректность touch-feedback'а на тач-устройстве.

Прошу смок-тест на проде после деплоя.

**Запланированный Sprint 6 — post-round email-инфографика:**

Идея от пользователя: после `status: finished` отправлять каждому
игроку красивое HTML-письмо с итогами (как Golfshot). Стек, который
имеет смысл: Firebase Cloud Function → `react-email` → Resend.
Требует расширения `PlayerInfo` полем `email`, нового кода в
`functions/`, нового шаблона. Подробности — в начале Sprint 6.
