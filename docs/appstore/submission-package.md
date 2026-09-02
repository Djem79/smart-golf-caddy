# App Store — пакет подачи (готов до оплаты аккаунта)

Всё, что можно было подготовить без Apple Developer Program, — здесь.
После оплаты: сначала чек-лист «Sign in with Apple — включение после
оплаты» в `SETUP.md`, потом этот файл сверху вниз.

**Стратегия запуска (решение владельца, 2026-08-30): сначала обкатка в
TestFlight, затем публикация ПЛАТНЫМ приложением.** Что из этого следует:

- TestFlight всегда бесплатен для тестеров — обкатка не зависит от цены.
- Цена меняется в любой момент без ревью — можно выйти платным сразу
  или поднять цену после релиза; уже купившие ничего не доплачивают.
- Платное приложение требует **Paid Applications Agreement** в App Store
  Connect (банковские реквизиты + налоговые формы). Проверка занимает
  от дней до недель — **запустить сразу после оплаты аккаунта**,
  параллельно с TestFlight, чтобы к концу обкатки договор был активен.
- **Аккаунт и банк — ОАЭ (решение владельца, 30.08.2026).** Что из этого
  следует:
  - банк для выплат — эмиратский, валюту выплат можно выбрать (AED/USD);
    NDB/IBAN ОАЭ Apple принимает штатно;
  - налоговые формы: как не-резидент США заполняется **W-8BEN** (для
    физлица; W-8BEN-E для компании). У ОАЭ **нет налогового договора с
    США**, поэтому с продаж в американской витрине Apple удерживает
    **30%** (только с продаж в США; остальные витрины — без этого
    удержания). Уточнить при заполнении форм — Apple показывает ставку
    прямо в интерфейсе;
  - НДС/налоги покупательских стран Apple считает и удерживает сам —
    разработчику приходит нетто по своему проценту (85/70);
  - Free Zone / mainland-статус и 9% corporate tax ОАЭ — вопрос к
    местному бухгалтеру, к App Store Connect отношения не имеет.
- В анкете **Digital Services Act (ЕС)** продажа = статус **Trader**:
  адрес и контакты публично показываются на странице приложения в ЕС и
  проходят верификацию. (Не хочется публичных контактов — можно снять
  приложение с витрин стран ЕС.)
- Честное предупреждение по рынку РФ: оплата в App Store российскими
  картами не работает, из рабочих способов — в основном счёт мобильного
  оператора. Платная модель режет аудиторию в РФ; freemium (бесплатно +
  встроенная покупка) — запасной вариант, но это отдельная разработка
  (StoreKit). Решение остаётся за владельцем, пакет ниже — под платную
  модель.

## Перед всем: оформление аккаунта разработчика (Individual, ОАЭ)

Решение владельца (31.08.2026): регистрируемся как **физлицо** на личный
Apple ID с регионом ОАЭ. В App Store именем разработчика будет имя и
фамилия из Apple ID (латиницей) — сменить на бренд потом можно только
переходом на Organization (D-U-N-S, юрлицо).

**Подготовка (до оплаты, 5 минут):**

1. На iPhone: Настройки → [своё имя] — проверить, что **двухфакторная
   аутентификация включена** (без неё enrollment не пройдёт).
2. Там же → «Имя, номера телефонов, e-mail»: **имя и фамилия латиницей,
   как в документах** — именно это станет публичным именем разработчика;
   поправить ДО оплаты.
3. Регион аккаунта — ОАЭ, эмиратская карта привязана и рабочая.

**Оформление (рекомендуемый путь — приложение Apple Developer):**

1. App Store → установить приложение **Apple Developer** → войти своим
   Apple ID → вкладка Account → **Enroll Now**.
2. Тип — **Individual / Sole Proprietor**. Данные: имя как в документах,
   адрес в ОАЭ, телефон.
3. Если попросит подтвердить личность — сфотографировать документ прямо
   в приложении (штатный шаг, не ошибка).
4. Согласиться с Apple Developer Program License Agreement → оплатить
   $99/год (цену в AED покажет перед оплатой; списание через App Store,
   картой из Apple ID).
5. Ждать письмо «Welcome to the Apple Developer Program» — обычно от
   минут до 48 часов. Дольше 48 ч / «purchase pending» → написать в
   Developer Support (developer.apple.com/contact — чат отвечает быстро).

Запасной путь: developer.apple.com/enroll в браузере (оплата картой на
сайте) — тот же результат.

**Если «Contact Us to Continue / There may be an issue with your
account»** (упёрлись 31.08.2026 на Mac, вебе и iPhone): известная
особенность шага Enroll. **Ответ Developer Support по нашему кейсу
20000152393606 (02.09.2026): код страны ДОВЕРЕННОГО НОМЕРА телефона
(2FA) должен совпадать с регионом Apple Account** — у нас регион ОАЭ, а
доверенный номер был российский (+7). Лечение: Настройки → [имя] → Вход
и безопасность → Доверенные номера → добавить +971, российский убрать
(хотя бы на время enrollment) → подождать 10–15 минут → Enroll Now
заново с iPhone. Не помогло — ответить на письмо Apple (кейс открыт).
Остальные шаги, от простого к тяжёлому:

1. Попробовать с **iPhone** (приложение Apple Developer) — чаще всего
   решает именно смена устройства; помогает и выход/вход в приложении.
2. account.apple.com: имя латиницей как в документах, дата рождения,
   регион ОАЭ, действующая Visa/MC с адресом в ОАЭ (лучше уже
   использовавшаяся в App Store), Apple ID на e-mail, 2FA включена.
   Подождать 10–15 минут, повторить с iPhone.
3. Браузер: developer.apple.com/enroll в Safari (не приватное окно).
4. developer.apple.com/contact → Membership and Account → Program
   Enrollment → Phone/e-mail: флажок на аккаунте снимают вручную, могут
   попросить фото документа (штатно). Если укажут на платёж — другая
   эмиратская карта.

**Сразу после активации (15 минут):**

1. Войти на **appstoreconnect.apple.com** тем же Apple ID — убедиться,
   что консоль открывается.
2. App Store Connect → Business (Agreements) → запустить **Paid
   Applications**: эмиратский IBAN + SWIFT, валюта выплат, налоговая
   форма **W-8BEN** (см. раздел «Стратегия» — с продаж в витрине США
   удержание 30%, у ОАЭ нет договора с США). Проверка небыстрая —
   потому и первым делом. Как только договор станет Active — подать
   заявку в **App Store Small Business Program** (developer.apple.com →
   Small Business Program): комиссия Apple **15% вместо 30%** при
   выручке до $1 млн/год; действует со следующего месяца после
   одобрения, поэтому тоже заранее.
3. Xcode → Settings → Accounts → добавить Apple ID → появится команда
   «<Имя Фамилия> (Individual)». **Team ID** из неё → в
   `ios/Config/Local.xcconfig` (`DEV_TEAM`) — с этого момента подпись
   перестаёт быть 7-дневной.
4. Дальше — чек-лист «Sign in with Apple — включение после оплаты» в
   `SETUP.md`, затем «Стратегия» ниже (TestFlight → платный релиз).

## Стратегия: TestFlight → платный релиз

1. **Внутреннее тестирование** (сразу после первой загрузки сборки):
   App Store Connect → TestFlight → Internal Testing → добавить себя
   (Apple ID аккаунта). До 100 тестеров, без ревью, билд доступен через
   минуты. Обязательные поля: Test Information → What to Test.
2. **Внешнее тестирование** (друзья/гольф-партнёры, до 10 000): группа
   External Testing → публичная ссылка-приглашение. Первый билд проходит
   **Beta App Review** (~сутки, мягче обычного ревью) — Review Notes из
   §3 подходят и туда. Билды TestFlight живут 90 дней.
3. Во время обкатки: собрать фидбек (TestFlight → Feedback), закрыть
   находки, прогнать чек-лист живой проверки Sign in with Apple
   (SETUP.md) и приёмку часов на поле.
4. **Релиз платным**: выбрать цену (Pricing and Availability → Price
   Schedule; у Apple фиксированные тиры, напр. Tier 1 ≈ $0.99 / Tier 5 ≈
   $4.99 — для нишевой спортивной утилиты разумный коридор $2.99–4.99),
   убедиться, что Paid Applications Agreement в статусе Active, и
   Submit for Review (§5).

Факты, на которых построен пакет: bundle `com.dzhambulat.smartgolfcaddy`,
watch-компаньон «Golf Caddy» (`WKCompanionAppBundleIdentifier` указывает
на основной bundle), iPhone-only (`TARGETED_DEVICE_FAMILY: 1`), только
HTTPS (`ITSAppUsesNonExemptEncryption: false`), аналитики/трекинга в iOS
нет (Firebase Auth/Firestore/Functions/App Check, Google Places, без
Analytics/Crashlytics/Sentry), юр. страницы живые.

---

## 1. Метаданные (скопировать в App Store Connect)

Primary language: **Russian**. Вторая локализация: **English (U.S.)**.

### Русский

| Поле | Значение |
|---|---|
| Name (до 30) | `Smart Golf Caddy` |
| Subtitle (до 30) | `Счёт, статистика, дальномер` |
| Category | Primary: **Sports**; Secondary: Health & Fitness |
| Keywords (до 100 симв.) | `гольф,скоркарта,счёт,раунд,дальномер,гандикап,клюшки,статистика,поле,кэдди,гольфист` |
| Support URL | `https://smart-golf-caddy.web.app/support` |
| Marketing URL (необяз.) | `https://smart-golf-caddy.web.app` |
| Privacy Policy URL | `https://smart-golf-caddy.web.app/privacy` |
| Copyright | `© 2026 <Имя Фамилия латиницей>` ← ВПИСАТЬ |

**Promotional text (до 170, можно менять без ревью):**

> Считайте удары прямо с запястья, смотрите дистанцию до грина и
> получайте итоги раунда на почту. Играйте с друзьями — живой лидерборд
> и матч-плей.

**Description (до 4000):**

> Smart Golf Caddy — карманный кэдди для ваших раундов: счёт, клюшки,
> дистанции и статистика без бумажных скоркарт.
>
> НА ПОЛЕ
> • Счёт по лункам в пару касаний: удары, клюшки, штрафы
> • GPS-дальномер: дистанция до грина и автоматический замер длины
>   ваших ударов
> • Работает без связи — удары сохранятся и синхронизируются сами
> • Apple Watch: записывайте удары с запястья, телефон остаётся в кармане
>
> ИГРА С ДРУЗЬЯМИ
> • Совместный раунд по коду или QR — без регистрации партнёров вручную
> • Живой лидерборд и матч-плей (AS, 2 UP, 3&2)
> • Хост может вести счёт за всю группу
> • Итоги раунда приходят каждому игроку на почту
>
> ПОСЛЕ РАУНДА
> • История раундов и скоркарты
> • Статистика: скоринг, гандикап, любимые клюшки, дальность ударов
> • Своя сумка: до 14 клюшек по правилам, метры или ярды
>
> ПОЛЯ
> • Поиск гольф-полей рядом с вами или по названию
> • Пары и дистанции лунок настраиваются под конкретное поле
>
> Интерфейс на русском и английском. Вход через Apple или Google —
> без паролей. Данные раунда принадлежат вам: аккаунт и всё связанное
> с ним можно удалить в один тап из профиля.

**What's New (версия 1.0.0):**

> Первый релиз: счёт и клюшки по лункам, GPS-дальномер, офлайн-режим,
> Apple Watch, совместные раунды с живым лидербордом, статистика и
> итоги на почту.

### English (U.S.)

| Field | Value |
|---|---|
| Name | `Smart Golf Caddy` |
| Subtitle | `Scores, stats & rangefinder` |
| Keywords | `golf,scorecard,caddie,rangefinder,handicap,stats,clubs,course,tee,round,watch` |
| Support URL | `https://smart-golf-caddy.web.app/support` |
| Privacy Policy URL | `https://smart-golf-caddy.web.app/privacy` |

**Promotional text:**

> Score every stroke right from your wrist, see the distance to the
> green, and get round summaries by email. Play with friends — live
> leaderboard and match play.

**Description:**

> Smart Golf Caddy is a pocket caddie for your rounds: scores, clubs,
> distances and stats — no more paper scorecards.
>
> ON THE COURSE
> • Score every hole in a couple of taps: strokes, clubs, penalties
> • GPS rangefinder: distance to the green plus automatic measurement
>   of your shot length
> • Works offline — shots are stored and sync automatically
> • Apple Watch companion: record shots from your wrist, phone stays
>   in your pocket
>
> PLAY WITH FRIENDS
> • Shared rounds via code or QR — no manual player setup
> • Live leaderboard and match play (AS, 2 UP, 3&2)
> • The host can keep score for the whole group
> • Every player gets the round summary by email
>
> AFTER THE ROUND
> • Round history and scorecards
> • Stats: scoring, handicap, favourite clubs, shot distances
> • Your own bag: up to 14 clubs per the rules, meters or yards
>
> COURSES
> • Find golf courses near you or by name
> • Hole pars and distances adjust to the course you play
>
> Interface in English and Russian. Sign in with Apple or Google — no
> passwords. Your data stays yours: delete your account and everything
> tied to it in one tap from the profile.

**What's New (1.0.0):**

> First release: per-hole scores and clubs, GPS rangefinder, offline
> mode, Apple Watch companion, shared rounds with a live leaderboard,
> stats and email summaries.

---

## 2. Декларация приватности (App Privacy)

Отвечать ровно так; всё «Data Linked to You», трекинга нет.

**“Do you or your third-party partners collect data from this app?” → Yes.**

| Тип данных | Собирается | Linked to user | Tracking | Цель |
|---|---|---|---|---|
| Contact Info → Name | Да (профиль из Apple/Google) | Да | Нет | App Functionality |
| Contact Info → Email Address | Да (вход, письма с итогами) | Да | Нет | App Functionality |
| Location → Precise Location | Да (поиск полей, дальномер; координаты гринов сохраняются в профиле поля) | Да | Нет | App Functionality |
| User Content → Other User Content | Да (раунды, счёт, клюшки) | Да | Нет | App Functionality |
| Identifiers → User ID | Да (Firebase uid) | Да | Нет | App Functionality |

Всё остальное (Health, Financial, Browsing, Diagnostics, Purchases,
Contacts, Photos…) — **не собирается**. В iOS-приложении нет
Analytics/Crashlytics/Sentry — Diagnostics честно «нет».

**“Do you use data for tracking?” → No** (ничего не уходит брокерам
данных/в рекламные сети; ATT-запрос не нужен).

Третьи стороны-обработчики (для privacy policy уже указаны): Firebase
(Google) — auth/база/функции, Google Places — поиск полей, Resend —
доставка писем.

**Age rating:** по опроснику всё «None/No» → **4+**. Вопрос про
user-generated content: контент виден только участникам приватного
раунда по коду-приглашению, публичной ленты/поиска чужого контента нет.

---

## 3. Review Notes + демо-доступ (ловушка №1 подачи)

В приложении НЕТ входа по паролю — только Sign in with Apple / Google.
Заводить «демо-аккаунт с логином-паролем» не на что. Правильный путь:

1. В App Review Information → Sign-In Information поставить галку
   «Sign-in required», в поле Notes объяснить (текст ниже).
2. Ревьюер входит своим Sign in with Apple — аккаунт создаётся сам,
   весь функционал доступен сразу, контента-пейволла нет.
3. Запасной вариант (если ревью попросит именно credentials): завести
   свежий Google-аккаунт `smartgolfcaddy.review@gmail.com`, отключить
   2FA-сюрпризы (Google может блокировать вход с незнакомого
   устройства — поэтому вариант запасной, а не основной).

**Notes for Review (вставить как есть):**

> Sign-in: the app has no password accounts — authentication is only
> via Sign in with Apple or Google. Please use Sign in with Apple: a
> fresh account is created automatically and every feature is available
> immediately (paid-upfront app, no in-app purchases, no content gating).
>
> Quick tour: tap "Начать новый раунд" (Start new round) → pick or
> skip a course → record strokes per hole with the club picker. GPS
> distance to the green appears on the hole screen once location
> permission is granted (works best outdoors). "Присоединиться к игре"
> (Join a game) joins a shared round by a 6-character code. Round
> summary emails are sent after finishing a round.
>
> Apple Watch companion mirrors the active round and records shots from
> the wrist; it requires an active round started on the iPhone.
>
> Account deletion: Profile → «Удалить аккаунт» (Delete account) —
> removes the profile, rounds and green marks, revokes the Sign in with
> Apple token (TN3194), then deletes the Firebase Auth record.

---

## 4. Скриншоты

Обязателен один набор iPhone (мы iPhone-only). Снимать в симуляторе
**iPhone 16 Pro Max** (⌘S), загрузится как 6.9″ (актуальный требуемый
размер подтвердить в Media Manager → View All Sizes). Для watch-версии —
набор Apple Watch (симулятор Ultra 2/49 mm). Локализованные наборы:
русские скрины для ru, английские для en (язык переключается в Профиле).

Порядок (первые 2–3 видны в поиске — самое сильное вперёд):

1. **Экран лунки** — счёт, клюшки, дистанция до грина (главная ценность).
2. **Лидерборд** группового раунда (2–3 игрока, матч-статус).
3. **Итоги раунда** — скоркарта с цветами birdie/par/bogey.
4. **Статистика профиля** — гандикап, любимые клюшки.
5. **Watch: экран лунки** — счёт + дистанция с запястья.
6. **Моя сумка** (опционально).

Данные для скринов: раунд на реальном названии поля, русские имена
игроков, счёт с birdie/par/bogey вперемешку (не все пары).

---

## 5. Пошагово в App Store Connect (после оплаты)

1. developer.apple.com → Identifiers: App ID `com.dzhambulat.smartgolfcaddy`
   уже будет создан на шаге Sign in with Apple (SETUP.md). Туда же —
   watch bundle id (`…smartgolfcaddy.watchkitapp`, проверить фактический
   в Xcode после xcodegen).
2. App Store Connect → My Apps → «+» → New App: платформа iOS, имя
   `Smart Golf Caddy`, primary language Russian, bundle id, SKU
   `smart-golf-caddy-ios`.
2а. Сразу же: Business → Agreements → **Paid Applications** — принять
   договор, заполнить банк и налоговые формы (проверка Apple занимает
   от дней до недель; должно стать Active ДО платного релиза, TestFlight
   этого не ждёт).
3. Поднять версию: `ios/project.yml` → `CFBundleShortVersionString: "1.0.0"`
   (+ `CFBundleVersion` наращивать на каждую загрузку) → `cd ios && xcodegen`.
4. Xcode → Product → Archive → Distribute → TestFlight. Экспортная
   декларация не спросится (`ITSAppUsesNonExemptEncryption: false` уже в
   Info.plist).
5. Прогнать TestFlight на своём iPhone + часах (внутреннее тестирование,
   до 100 устройств, ревью не нужно).
6. Заполнить: метаданные (§1), App Privacy (§2), Review Notes (§3),
   скриншоты (§4), Age Rating, Pricing (платное — тир из раздела
   «Стратегия», Paid Applications Agreement должен быть Active),
   Availability.
7. В анкете «Digital Services Act» (для ЕС): платное приложение =
   **Trader** — публичные верифицированные контакты на витрине ЕС
   (либо исключить страны ЕС из Availability).
8. Submit for Review. Типовой срок — 1–2 дня; отказ чаще всего по §3
   (вход) или приватности — оба закрыты этим пакетом.

## 6. Что заполнено в коде заранее

- `ITSAppUsesNonExemptEncryption: false` — project.yml (эта подготовка).
- `TARGETED_DEVICE_FAMILY: "1"` (iPhone-only) — project.yml (эта
  подготовка): без него просились бы iPad-скриншоты.
- Иконка 1024 px — есть в Assets.
- Тексты разрешений локализованы (InfoPlist.strings, ru/en, обе цели).
- Удаление аккаунта (5.1.1(v)), приватные страницы, Sign in with Apple —
  готовы (см. чек-лист подачи в tasks/todo.md).

## 7. Открытые места (вписать перед подачей)

- [ ] Решить цену (тир $2.99–4.99 — стартовая рекомендация; см.
      «Стратегия») и список стран (ЕС → статус Trader; РФ → оплата
      фактически только со счёта оператора).
- [ ] Paid Applications Agreement: эмиратский банк (IBAN, AED/USD) +
      W-8BEN (запустить сразу после оплаты аккаунта — проверка
      небыстрая; с продаж в витрине США удержание 30% — договора
      ОАЭ–США нет).
- [ ] Copyright: имя-фамилия латиницей (§1).
- [ ] Запасной Google-демо-аккаунт — завести, если хочется (§3).
- [ ] Юр. вычитка privacy/terms человеком (GDPR/152-ФЗ) — в списке
      владельца.
- [ ] Свой домен в Resend + регистрация у Apple — иначе итоговые письма
      не дойдут пользователям «Скрыть e-mail» (описано в SETUP.md).
