# Smart Golf Caddy

Мобильный PWA для трекинга гольф-раундов — твой цифровой кэдди в кармане.

🌐 **Live:** https://smart-golf-caddy.web.app
📋 **Setup:** см. [SETUP.md](SETUP.md) перед первым запуском
🤖 **Для агентов:** см. [CLAUDE.md](CLAUDE.md)

## Возможности

- 🔐 Вход через Google
- 📍 Поиск ближайших полей по геолокации + глобальный поиск по названию (Google Places API)
- ⛳ Поэлементный трекинг ударов с записью клюшки на каждый удар
- 👥 Групповая игра: 6-значный код лобби + QR, реальное время через Firestore
- 🎯 Выбор тии (Pro / Men / Senior / Ladies) с авто-пересчётом дистанций
- 🎒 Кастомизируемая сумка: дистанции, метры/ярды, drag-and-drop порядок, свои клюшки
- 📊 Итоги раунда: цветная карта счёта, распределение по клюшкам, победитель
- 📋 История раундов с пересчётом счёта по записанным ударам
- 👤 Статистика по клюшкам в профиле

## Стек

| Слой | Технология |
|---|---|
| UI | React 19 + TypeScript + Vite 8 + Tailwind 3 |
| Дизайн | Fairway Elite (Stitch) — токены в `tailwind.config.js` |
| Роутинг | React Router 6 + `React.lazy` per-screen chunking |
| State | Zustand (минимально) + Firestore real-time listeners |
| Backend | Firebase Auth + Firestore + Hosting |
| Поля | Google Places API (New) — `places.googleapis.com/v1` |
| DnD | `@dnd-kit` для перестановки клюшек |
| QR | `qrcode.react` для лобби |
| Тесты | Vitest + @testing-library/react |

Целевая ширина — **390 px** (`.screen` utility = `max-w-[390px] mx-auto`). Дизайн mobile-first, на десктопе UI отрендерится в центре экрана.

## Запуск локально

Нужно: Node 20+ через `nvm`.

```bash
nvm use default                    # активировать node + npm
npm install                        # один раз
npm run dev                        # http://localhost:5173

# Тесты
npm run test                       # vitest watch
npm run test:run                   # CI mode
npm run test:run -- src/utils      # один файл/директория

# Лint и type-check
npm run lint
npx tsc --noEmit                   # без сборки

# Production билд
npm run build                      # → dist/
npm run preview                    # serve dist/
```

Для Firebase / Places API ключей см. [SETUP.md](SETUP.md). Без `.env.local` приложение собирается, но не работает в рантайме.

## Деплой

```bash
nvm use default
npm run build
firebase deploy --only hosting     # → smart-golf-caddy.web.app
firebase deploy --only firestore   # правила + индексы
```

## Структура

```
src/
├── App.tsx                  Router + lazy-load экранов
├── firebase.ts              Init SDK (auth + db)
├── types/index.ts           Канонические TS-типы + хелперы (single source of truth)
├── services/                Слой Firestore/REST (firebase/* импортится только здесь)
│   ├── auth.ts              Google Sign-In
│   ├── rounds.ts            CRUD раундов + транзакционная запись ударов
│   ├── users.ts             Профиль / сумка / единицы
│   ├── courses.ts           Places API (New): nearby + text search + photos
│   ├── distance.ts          Haversine
│   └── scoring.ts           Подсчёт результатов + статистика по клюшкам
├── hooks/                   React-обёртки над сервисами
│   ├── useAuth.ts           onAuthStateChanged
│   ├── useProfile.ts        subscribeToProfile
│   └── useGeolocation.ts    watchPosition + manual request
├── store/useAppStore.ts     Zustand: только lastClubUsed
├── components/
│   ├── ui/                  Button, Card, ClubChip, ScoreChip, ConfirmDialog
│   ├── layout/              PageHeader, BottomNav
│   └── ErrorBoundary.tsx    Глобальный fallback
├── screens/                 10 экранов: Auth, Home, CourseSearch, RoundSetup,
│                            GroupLobby, JoinGame, HoleTracker, RoundResults,
│                            History, Profile, MyBag
├── utils/intl.ts            pluralRu — русская плюрализация
└── styles/index.css         Tailwind + Fairway Elite
```

## Документация

- **[SETUP.md](SETUP.md)** — настройка Firebase, Places API, env vars, деплой
- **[CLAUDE.md](CLAUDE.md)** — гайд для Claude Code / агентов: архитектура, конвенции, рабочий процесс
- **[docs/superpowers/specs/](docs/superpowers/specs/)** — оригинальные спеки
- **[docs/superpowers/plans/](docs/superpowers/plans/)** — планы реализации
- **[tasks/todo.md](tasks/todo.md)** — текущий план работ
- **[tasks/lessons.md](tasks/lessons.md)** — извлечённые уроки

## Лицензия

Внутренний проект. Все права у автора.
