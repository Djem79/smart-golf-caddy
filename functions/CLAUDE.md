# Cloud Functions

Загружается при работе с `functions/`. Общие для проекта правила — в
корневом `CLAUDE.md`.

Отдельный TypeScript-проект со своим `package.json` и `tsconfig.json`;
все команды выполнять из `functions/`.

```bash
npm run build            # tsc
npx tsc --noEmit         # type-check без emit
npm run email:dev        # react-email dev preview :3000
npm audit --audit-level=high   # то же гоняет CI
```

Все функции в `us-central1` (Firestore в `europe-west3` — cross-region
warning подавляется, см. `firebase.json`). Актуальный список и сигнатуры
— в `src/index.ts`; ниже только то, чего в коде не видно.

**У всех callable `enforceAppCheck: true`** — без валидного App Check
токена вызов отклоняется.

- `recordShot` принимает `targetUid`: **хост может писать удары за любого
  игрока**, остальные только за себя (host-or-self check). Пишет весь
  массив `clubs` лунки → **идемпотентно**, на это опираются офлайн-очереди
  веба и iOS.
- `joinLobbyByCode` — server-side lookup лобби, клиент НЕ читает раунд
  напрямую. Rate-limit против перебора кодов.
- `onRoundFinished` — auto-email при `status: active → finished`. Atomic
  lease + per-uid tracking (`emailingStartedAt`, `emailedTo`, `emailedAt`).
- Квоты per-user/per-kind в `userQuota/{uid}` через generic
  `bumpDailyQuota(uid, kind, limit)` (kinds `share`/`join`/`auto`,
  структура `{ [kind]: { day, count } }`, Admin-SDK only).

Secrets через `defineSecret('RESEND_API_KEY')`. Ротация: `firebase
functions:secrets:set RESEND_API_KEY` + redeploy; старые версии остаются
disabled и могут быть re-enabled.

## Callable contracts (Zod)

Валидация payload всех 4 callable централизована в `src/contracts.ts`
(`RecordShotInput`, `UpdateHoleConfigInput`, `JoinLobbyInput`,
`ShareInput`). Каждый callable начинается со строчки
`const x = parseInput(SchemaName, request.data)` — она бросает
`HttpsError('invalid-argument', ...)` с первым issue.message, поэтому
руками `if (typeof x !== 'number')` уже **не пишем**.

Клиент **зеркалит** эти схемы как plain TypeScript-интерфейсы в
`src/types/callable.ts` (без zod-рантайма в браузерном бандле — экономит
~50 KB), iOS — как Swift-структуры в
`ios/SmartGolfCaddy/Services/CallableContracts.swift`. Синхронизируются
вручную, во всех трёх стоит маркер `SYNC:`. При правке схемы на одной
стороне — **обязательно** обновить обе остальные, иначе клиент пошлёт
payload, который сервер отклонит.

## Email

Шаблон в `src/emails/RoundSummary.tsx` (react-email), payload собирается
`buildPayload.ts`. Цвета pill'ов в `src/emails/types.ts` — **отдельная,
email-client-safe палитра**, она НЕ совпадает с web `scoreColor`: разные
таргеты рендера, не пытаться «синхронизировать». А вот при изменении
club abbreviations в `src/types/index.ts:CLUB_ABBREV` — синхронизировать
с `src/emails/buildPayload.ts:CLUB_ABBREV`, это реальное дублирование.
