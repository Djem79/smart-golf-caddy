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
- **Firestore `allow list` НЕ фильтрует документы по правилам чтения**: если правило list не ссылается на `resource.data`, неограниченный `getDocs(collection)` отдаёт всю коллекцию. Комментарий в наших правилах утверждал обратное — и дыра прожила до аудита. Правило list обязано содержать условие на `resource.data` (тогда Firestore пропускает только доказуемо-ограниченные запросы). Побочный нюанс: type-guard `x is list` внутри list-правила ломает query-prover — проверять эмулятором, а не рассуждением.
- **Правила «удалить себя из массива» требуют равенства множеств**, а не только «меня нет в новом»: иначе участник переписывает весь массив (выкидывает хоста, вписывает чужих). Шаблон: `new.toSet() == old.toSet().difference([uid].toSet())`.
- **create-правила нужно проверять так же строго, как update**: незаблокированные server-only поля и произвольный `players` при создании открыли обход email-allowlist. Симметрия create/update — обязательный чек-лист при ревью правил.
- **Тесты правил должны покрывать list/query, а не только getDoc** — именно отсутствие list-теста скрыло критическую утечку PII.

## 2026-08-24 — уроки Фазы 3c (Apple Watch)

- **Идемпотентность повторной доставки — на детерминированном ключе, не на
  сравнении содержимого**: первая версия дедупликации батча ударов с часов
  сравнивала хвост клюшек с уже записанными — совпадение казалось
  надёжным сигналом «уже применено». Но совпадение данных бывает
  ЗАКОННЫМ: два патта подряд той же клюшкой — обычнейший игровой случай,
  и эвристика молча теряла второй реальный удар, отчитываясь `accepted:
  true`. Фикс — монотонный `sequence` на слот, присвоенный ОТПРАВИТЕЛЕМ
  при постановке в очередь, а не выводимый получателем из содержимого.
  Правило: дедуплицировать retry/at-least-once доставку всегда по
  ID/sequence, который переживает повтор, никогда — по эквивалентности
  payload.
- **Числа через property-list/XPC (`updateApplicationContext`,
  `transferUserInfo`, и вообще любой `[String: Any]` мост между
  процессами) приходят как `NSNumber`, не как нативный Swift-тип.**
  Строгий каст `as? Int`/`as? Double` на такое значение может дать `nil`
  даже для валидных данных и уронить декодирование ВСЕГО payload (а не
  одного поля) — round-trip в одном процессе (юнит-тест без реального
  XPC) этот класс отказов не ловит вовсе. Разбирать такие поля всегда
  через `(any as? NSNumber)?.intValue`/`.doubleValue`/`.boolValue`, и
  писать в тесты значения, обёрнутые как `NSNumber` явно — не только
  Swift-литералы.
- **«Подтверждено» нельзя выводить из состояния, которое обновляется не
  всегда.** Часовой снимок раунда (`WatchRoundSnapshot.myShots`) шлётся
  телефоном ТОЛЬКО пока на нём открыт конкретный экран — это законное
  архитектурное ограничение, не баг, но если часы считали бы снимок
  источником истины «что подтверждено», подтверждённый удар навсегда
  оставался бы «неподтверждённым» и переотправлялся бы заново при
  каждом новом ударе → дубли на сервере. Источником «подтверждено»
  обязан быть отдельный durable-сигнал с гарантией доставки именно ЗА
  это событие (здесь — квитанция `WatchShotReceipt`), а не побочный
  снимок состояния, который может просто не успеть обновиться.
- **Файловый singleton (`.shared`, durable-хранилище в Application
  Support) в юнит-тестах watchOS/iOS переживает НЕ ТОЛЬКО между тестами
  одного прогона, но и между запусками `xcodebuild test` на одном и том
  же симуляторе** (приложение не переустанавливается между запусками,
  если явно не erase/uninstall). Тест, использующий дефолтный `.shared`
  вместо инжектированного временного хранилища, может годами проходить
  и внезапно упасть на чужой машине/после чужой сессии — не из-за
  регрессии в коде, а из-за накопленного состояния. Диагностика:
  `git stash` + повтор прогона на немодифицированной кодовой базе —
  если падает и там, ищи причину в окружении (найти реальный файл через
  `find ~/Library/Developer/CoreSimulator/Devices -iname '<имя-файла>'`
  и посмотреть его содержимое), а не в диффе.
- **Экранное (in-memory) состояние, у которого есть durable-двойник на
  диске, обязано при инициализации восстанавливаться ИЗ этого двойника —
  иначе перезапуск процесса рассинхронизирует их молча.**
  `WatchRoundViewModel.shotsByHole` жил только в памяти, а `WatchShotQueue`
  (durable) — на диске; `seedIfNeeded` сеяла лунку ИСКЛЮЧИТЕЛЬНО из
  `snapshot.myShots`, никогда не читая уже лежащий в очереди хвост.
  watchOS штатно выгружает приложение из памяти (не экзотика, рядовое
  событие) — реальный, ещё не подтверждённый удар "терялся из вида" при
  пересоздании VM: подтверждённый счётчик (durable) обгонял локальный
  (in-memory), и следующий тап на "+" считал `unsyncedShots` пустым,
  из-за чего `enqueue(clubs: [])` стирал durable-хвост вместо постановки
  нового удара в очередь. Правило: при построении in-memory состояния из
  внешнего источника (снимок/сервер) — если для того же ключа существует
  durable-очередь/локальный лог, рехидратировать состояние из
  ОБЪЕДИНЕНИЯ обоих источников (снимок — это НЕ полная картина, если
  часть "разговора" уже записана на диск), а не только из одного.
  Отдельно: там, где "очистка при пустом входе" — законное поведение
  (`enqueue([])` снимает слот), защитить его явным флагом намерения
  (`allowClear`), чтобы рассинхрон состояний не маскировался под
  легитимное действие пользователя.

  **ПОПРАВКА (следующий раунд того же живого ревью):** рекомендация выше
  — "рехидратировать состояние из ОБЪЕДИНЕНИЯ обоих источников" — сама
  оказалась источником следующего бага (Fix 9): объединение "снимок +
  durable-хвост" вслепую суммированием слагаемых задваивало удар, когда
  снимок обгонял квитанцию (обе величины могли описывать ОДНО И ТО ЖЕ
  событие, а не быть строго дизъюнктными). Правильный урок ниже —
  устранить границу, а не искать более точную формулу для её слияния.
- **Величину «сколько уже подтверждено» НЕЛЬЗЯ выводить из другой
  величины, которая растёт по независимым причинам — такую границу нужно
  либо хранить явно и договорённо непересекающейся с остальными
  источниками, либо устранить из модели вовсе.** Три раунда живого ревью
  подряд (Fix 2 → Fix 7 → Fix 9) латали одну и ту же границу —
  `WatchRoundViewModel` пыталось свести `snapshot.myShots` (растёт по
  СВОЕЙ причине: телефон записал удар — включая через собственный UI, не
  только через часы) и локальное состояние часов в одно число
  ("confirmedCount"), каждый патч закрывал одну трассу потери/дубля и
  открывал соседнюю, потому что сама идея слияния предполагала, что две
  НЕЗАВИСИМЫЕ по своей природе величины дизъюнктны — а это не гарантия,
  а совпадение, которое ломается любым обгоном одного канала другим.
  Решение — не искать пятую версию формулы, а спросить: можно ли вообще
  не сводить эти величины в одну? Здесь можно: счёт на экране = сумма
  двух живых, непересекающихся ПО ПОСТРОЕНИЮ величин (сервер + durable
  локальный хвост), без каких-либо сравнений между ними, ценой признанного
  и явно задокументированного узкого окна кратковременной неточности
  вместо скрытой потери/задвоения данных. Если правка №3 подряд к одному
  и тому же узлу снова требует "более точного условия" — это сигнал
  остановиться и спросить, не является ли сама граница дефектом модели.

## Обнаружение Apple Watch в Xcode требует ПРОВОДНОГО подключения iPhone

**Симптом.** iPhone в `devicectl list devices` — `connected`, приложение
на телефон ставится и запускается, но часы не определяются нигде: ни в
`devicectl`, ни среди назначений watch-схемы, а пункт «Режим
разработчика» на часах не появляется. Возникает ложное впечатление
замкнутого круга (пункт нужен для установки, а появляется он после
подключения к Xcode).

**Причина.** Xcode соединяется с часами транзитом через сопряжённый
iPhone. Беспроводной тоннель до телефона поднимается легко и вводит в
заблуждение — но тоннель ДО ЧАСОВ по Wi-Fi штатно не строится.

**Правило.** Для любых операций с реальными часами (обнаружение,
включение Режима разработчика, установка watch-приложения) сначала
подключить iPhone к Маку КАБЕЛЕМ. Проверять фактом, а не окном Xcode:
`xcrun devicectl list devices` — часы обязаны появиться отдельной
строкой. Ошибка `doesn't have a known architecture` в
`xcodebuild -showdestinations` для часов означает «устройство ещё не
подготовлено к разработке» (Режим разработчика выключен), а не поломку.

**Обобщение.** Утверждение «кабель не нужен, устройство и так видно»
верно для iPhone и НЕВЕРНО для устройств, доступных только транзитом
через него. Проверять доступность нужно именно того устройства, с
которым предстоит работать, а не ближайшего к нему.

## 2026-08-30 — Sign in with Apple (веб + отзыв токена)

- **vitest: статические `import`-ы хоистятся ВЫШЕ обычных `const` в тесте,
  а `vi.mock`-фабрика может дёрнуть эти `const` уже при импорте модуля.**
  `auth.ts` создаёт `new GoogleAuthProvider()` на верхнем уровне — мок-класс
  писал в `const providers = []`, который в этот момент ещё в TDZ →
  `ReferenceError`. Любое состояние, которое мок-фабрика трогает при
  загрузке модуля, объявлять через `vi.hoisted(() => ({...}))`, а не
  обычным `const`. Симптом узнаваем: падает не тест, а импорт модуля.
- **Модульный singleton в сервисе (pending credential) течёт между тестами
  одного файла** — и это не только тестовая проблема: новая попытка входа
  обязана сбрасывать хвост предыдущей (иначе к следующему Google-входу
  привяжется протухший credential). Фикс в продукте, а не в `beforeEach`.
- **Официальные подписи Apple для кнопки берутся с
  `appleid.cdn-apple.com/appleid/button?locale=ru_RU`** (PNG) — для ru это
  «Вход с Apple», а не напрашивающееся «Войти через Apple». HIG запрещает
  свои формулировки; проверять по первоисточнику, не по памяти.
