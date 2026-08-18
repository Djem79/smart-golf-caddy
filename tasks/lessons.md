# Lessons — patterns to not repeat

> Per CLAUDE.md workflow #3: after **any** user correction, append a rule here
> phrased so the next session doesn't repeat the mistake.
> Re-read this file at the start of each session in this project.

## Active rules

- **Execute plan tasks one subagent at a time.** During plan execution
  (subagent-driven-development), dispatch a single plan task per implementer
  subagent and run both reviews (spec + quality) before the next task.
  Do not bundle plan tasks even if they look related.
  See `~/.claude/projects/.../memory/feedback_one_task_at_a_time.md`.
  _Source: user feedback during Plan 1 execution._

- **Security hardening that removes a capability must update the UI that
  relied on it.** Sprint 7 made `recordShot` self-only (anti-griefing) but
  left HoleTracker's player-switcher + `save(activeUserId)` path intact, so
  the host scoring for another player silently wrote to their own slot →
  the other player's counter "rolled back to 0". Rule: when locking down a
  callable/rules path, grep every client call site that passed the
  now-ignored argument and either restore the capability with proper
  authorization (host-or-self) or disable the orphaned UI.
  _Source: group-play bug report — host couldn't score the 2nd player._

- **`onSnapshot` without an error callback = silent infinite spinner.**
  `subscribeToRound`/`subscribeToProfile` omitted the error handler, so a
  permission/network failure never surfaced and screens spun on "Загрузка…"
  forever. Always pass the 3rd `onError` arg to `onSnapshot` and render a
  visible error + escape hatch.
  _Source: same report — 2nd player "couldn't connect, kept loading"._

- **Firestore dot-path updates do NOT support array indices.** Before
  recommending a path like `arr.0.field` for `tx.update`, verify the
  target field is a map, not an array. If it's an array, the choices are:
  (a) keep the full-array rewrite (acceptable for small arrays), or
  (b) refactor the field to `Record<string, T>` keyed by a stable id.
  _Source: Sprint 1 audit follow-up — the audit recommended dot-path for
  `recordShot`, but `holes` is an array, so the optimization was deferred
  in favor of in-transaction safety checks._

- **When wiring CI for a CLI, pin the runtime to what the CLI requires
  TODAY, not what its docs said last year.** Picked Java 17 for the
  Firestore emulator (`npm run test:rules`) based on the Firebase docs
  page — but `firebase-tools` dropped support for JDKs below 21 in late
  2025, so the rules job failed instantly with
  `firebase-tools no longer supports Java version before 21`. Rule:
  when adding a CI step for any external CLI (firebase, gh, docker,
  etc.), check the package's latest release notes / its current runtime
  matrix before choosing a setup-action version. Don't trust stale
  conventions from the project's CLAUDE.md or older docs.
  _Source: first CI run after enabling `firestore rules` job (2026-05-26)._

## 2026-08-17 — уроки iOS-фазы 1

- **U+00A0 в пути ломает Apple-тулчейн**: swift-driver экранирует ASCII-пробелы, но не NBSP → список файлов рвётся посередине пути. Симлинки не спасают (build system разворачивает в физический путь). Лечится только чистым физическим путём (папку переименовали, симлинк со старым именем оставлен для совместимости).
- **Артефакты сборки нельзя держать в iCloud-синхронизируемых папках**: File Provider вешает xattr (com.apple.fileprovider.fpfs#P) на файлы прямо между линковкой и codesign → «resource fork, Finder information, or similar detritus not allowed». DerivedData — только вне ~/Documents (см. ios/scripts/*).
- **firebase-ios-sdk#14464**: бинарный FirebaseFirestore из SPM не линкуется в два таргета (app + tests). ПЕРВЫЙ обход (FIREBASE_SOURCE_FIRESTORE=1, сборка из исходников) оказался ХУЖЕ болезни: Firestore стал отдельным framework со ВТОРОЙ копией FirebaseCore → пустой реестр apps → FIRIllegalStateException и краш-луп после входа. Правильный фикс: Firestore линкуется ТОЛЬКО в app-таргет; app-hosted тестам линковка не нужна — классы Firebase достаются из рантайма хоста (NSClassFromString("FIRTimestamp")).
- **«Безвредное» предупреждение о duplicate ObjC classes безвредным не бывает**: две копии класса = два независимых глобальных состояния. Предупреждение в тестовом прогоне (Задача 5) было тем же дефектом, что уронил приложение в проде-симуляторе. Дубликаты классов — всегда блокер, не шум.
- **App Check debug-токены регистрируются через CLI**: `firebase appcheck:debugtokens:create <UUID> --app <iosAppId> --project smart-golf-caddy` — консоль не нужна. Токен per-инсталляция приложения.
- **GoogleSignIn 8.x при отмене бросает GIDSignInError.canceled (NSError), а не CancellationError** — ловить Swift-овский CancellationError бесполезно; маппить в доменную ошибку на границе сервиса.
- **План с дословным кодом — сила и слабость**: 6 из 7 Important-финдингов ревью были дефектами кода в самом плане (plan-mandated), а не ошибками исполнителей. Ревью после каждой задачи окупилось полностью.
- **SwiftUI: `@State(initialValue:)` от параметров вью — ловушка при неизменной identity**: NavigationStack при замене значения Route в той же позиции стека НЕ пересоздаёт identity destination-вью — let-параметры обновляются (заголовок «Лунка N» менялся), а @State (вью-модель с holeIndex) остаётся старым → все удары уходили в первую лунку. Фикс: `.id(route)` на destination. Проверять навигацию с parametrized-@State только рантайм-прогоном — код-ревью и юнит-тесты это не ловят.
- **Фиксированная светлая палитра требует `.preferredColorScheme(.light)`**: иначе тёмная тема устройства даёт системный белый текст на наших светлых фонах (невидимый ввод в HoleEditorSheet).
- **Places API с iOS-app-restriction требует заголовок `X-Ios-Bundle-Identifier`** в каждом REST-запросе — без него 403 «Requests from this iOS client <empty> are blocked». Веб-порту это неочевидно (браузер шлёт referer сам). Диагностика 403 от Google: curl с ключом и с/без ограничительного заголовка мгновенно различает «не тот API включён» от «не хватает идентификации клиента».
