// ios/SmartGolfCaddy/Models/Localization/Strings.swift
// T4 (iOS localization): the iOS counterpart of src/i18n/ru.ts + en.ts.
// One nominal `Strings` type, two memberwise-initialized instances (`.ru`,
// `.en`) — a missing or extra field in either is a compiler error (Swift's
// synthesized initializer requires every argument), the same safety net
// `typeof ru` gives the web dictionary via `tsc`. Keys are grouped and
// named to match the web dictionary where the same concept exists (see
// src/i18n/en.ts) — this is what "паритет формулировок" means in practice.
// iOS-only concerns (accessibility labels, alert bodies) get their own
// keys alongside.
//
// Read access: Views read through `@Environment(LocaleManager.self)` for
// reactive updates (see ViewModels/LocaleManager.swift). Everything else
// (ViewModels, Models, Services) reads `AppLocaleStore.strings` — a plain
// thread-safe global — since most of those aren't MainActor-isolated.
import Foundation

struct Strings {
    struct Common {
        let cancel: String
        let retry: String
        let goHome: String
        let loading: String
        let delete: String
        let you: String
        let host: String
        let unknown: String
        let missingCustomClub: String
        let metersShort: String
        let yardsShort: String
        let km: String
        let par: String
        let playersEven: String
        // Отображаемое имя для Players.deletedMarker (и старого литерала
        // «Удалённый игрок», который несут раунды, обезличенные до появления
        // маркера) — см. Players.displayName(_:) в Models/Round.swift.
        // SYNC (формулировка, не хранимое значение): src/i18n/ru.ts+en.ts
        // common.deletedPlayerName, functions/src/i18n/ru.ts+en.ts
        // deletedPlayerName.
        let deletedPlayerName: String
        let fallbackName: String
        let loadProfileError: String
        let holesWord: PluralForms
        let playersWord: PluralForms
        let clubsWord: PluralForms
        let tee: Tee

        struct Tee {
            let pro: TeeInfo
            let men: TeeInfo
            let senior: TeeInfo
            let ladies: TeeInfo
        }
        struct TeeInfo {
            let label: String
            let description: String
        }
    }

    struct Auth {
        let tagline: String
        let signInWithGoogle: String
        let noPresenterError: String
        let missingTokenError: String
        // Sign in with Apple: надпись самой кнопки не переводим (её даёт
        // системный SignInWithAppleButton) — эти строки только для ошибок.
        let accountExistsError: String
        let appleSignInError: String
    }

    struct Home {
        let welcomeUppercase: String
        let startNewRound: String
        let quickStart: String
        let joinGame: String
        let loadError: String
        let recentRounds: String
        let resumeUppercase: String
        let signOutAria: String
        let playedOf: (_ played: Int, _ total: Int) -> String
    }

    struct BottomNav {
        let rounds: String
        let history: String
        let profile: String
    }

    struct CourseSearch {
        let title: String
        let searchPlaceholder: String
        let manualEntry: String
        let useQuery: (_ query: String) -> String
        let searchingNearby: String
        let noResults: String
        let courseFallbackName: String
        let errors: Errors

        struct Errors {
            let apiKeyMissing: String
            let network: String
            let denied: String
            let quota: String
            let invalid: String
        }
    }

    struct RoundSetup {
        let title: String
        let creating: String
        let startRound: String
        let courseNameSectionHeader: String
        let courseNamePlaceholder: String
        let changeCourse: String
        let holesSectionHeader: String
        let teeSectionHeader: String
        let modeSectionHeader: String
        let soloTitle: String
        let soloDesc: String
        let groupTitle: String
        let groupDesc: String
        let groupHint: String
        let formatSectionHeader: String
        let strokeTitle: String
        let strokeDesc: String
        let matchTitle: String
        let matchDesc: String
        let matchHint: String
        let createError: String
    }

    struct GroupLobby {
        let title: String
        let loading: String
        let loadError: String
        let startError: String
        let leaveError: String
        let codeCardTitle: String
        let codeAccessibleLabel: (_ code: String) -> String
        let copied: String
        let tapToCopy: String
        let scanQr: String
        let qrCodeAria: String
        let copyLink: String
        let players: String
        let starting: String
        let startRoundButton: (_ count: Int, _ word: String) -> String
        let waitingHost: String
        let leaveLobby: String
        let leaveConfirmTitle: String
        let leaveConfirmHost: String
        let leaveConfirmGuest: String
        let leave: String
        let stay: String
        let you: String
    }

    struct History {
        let title: String
        let loadError: String
        let empty: String
    }

    struct HoleTracker {
        let loadError: String
        let holeTitle: (_ current: Int, _ total: Int) -> String
        let holeTitleNoTotal: (_ current: Int) -> String
        let leaderboardAria: String
        let finishConfirmTitle: String
        let finish: String
        let continueEditing: String
        let finishConfirmPartial: (_ played: Int, _ total: Int) -> String
        let finishConfirmComplete: String
        let markGreenHint: String
        let offlineNotice: String
        let editParAria: (_ par: Int) -> String
        let distanceShort: String
        let editDistanceAria: (_ meters: Int) -> String
        let teeAria: (_ label: String) -> String
        let courseNotIdentified: String
        let toGreen: (_ distance: String) -> String
        let greenNotMarked: String
        let onGreenButton: String
        let markGreenAria: String
        let playerSwitch: String
        let hostScoresOthers: String
        let yourShots: String
        let shotsOf: (_ name: String) -> String
        let shotsUppercase: String
        let shotSeries: String
        let gpsReady: String
        let gpsWaiting: String
        let clubPickerUppercase: String
        let prev: String
        let next: String
        let finishGame: String
        let finishWaitHost: String
        let finishEarly: String
        let saveShotError: String
        let finishRoundError: String
        let loadGreenMarksError: String
        let markGreenLoadingError: String
        let markGreenSaveError: String
        let editHoleTitle: (_ holeNumber: Int) -> String
        let editHoleHint: String
        let parUppercase: String
        let distanceMetersUppercase: String
        let distanceError: String
        let saving: String
        let save: String
        let holeSaveError: String
    }

    struct Leaderboard {
        let navTitle: String
        let loadError: String
        let lobbyNotStarted: String
        let roundFinished: String
        let match1v1Suffix: String
        let matchStatusUppercase: String
        let leading: (_ name: String) -> String
        let matchDecided: String
        let playedRemaining: (_ played: Int, _ remaining: Int) -> String
        let columnPlayer: String
        let columnToPar: String
        let noPlayers: String
        let you: String
        let strokesShortDot: String
    }

    struct RoundResults {
        let title: String
        let loadError: String
        let loading: String
        let newRound: String
        let matchPlayUppercase: String
        let yourResultUppercase: String
        let strokesShortDot: String
        let winnerUppercase: String
        let leaderboardSectionTitle: String
        let clubsTitle: String
        let clubsForPlayer: (_ name: String) -> String
        let avgAbbrev: String
        let scorecardTitle: String
        let holeColumnHeader: String
        let strokesRowHeader: String
    }

    struct JoinGame {
        let navTitle: String
        let heading: String
        let subtitle: String
        let codeAria: String
        let codeLengthError: String
        let lobbyNotFound: String
        let joinError: String
        let connecting: String
        let join: String
    }

    struct MyBag {
        let title: String
        let saving: String
        let reorderDone: String
        let reorder: String
        let addClub: String
        let bagComposition: String
        let ruleHint: String
        let freeSlots: (_ n: Int) -> String
        let metersFull: String
        let yardsFull: String
        let nameFieldPlaceholderCustom: String
        let nameFieldPlaceholderModel: String
        let distanceAria: (_ clubLabel: String, _ unit: String) -> String
        let metersWord: String
        let yardsWord: String
        let enableAria: (_ label: String) -> String
        let newClubTitle: (_ categoryLabel: String) -> String
        let newClubNamePlaceholder: String
        let distanceMetersPlaceholder: String
        let distanceYardsPlaceholder: String
        let add: String
        let saveError: String
    }

    struct Profile {
        let title: String
        let loadError: String
        let statsTitle: String
        let roundsLabel: String
        let avgShotsLabel: String
        let bestScoreLabel: String
        let bestVsParLabel: String
        let noStatsYet: String
        let distributionTitle: String
        let overAllHoles: (_ n: Int, _ word: String) -> String
        let playedHolesWord: PluralForms
        let worseLabel: String
        let handicapTitle: String
        let handicapBest8: (_ n: Int) -> String
        let handicapAvg: (_ n: Int, _ word: String) -> String
        let roundsWord: PluralForms
        let handicapEmpty: String
        let favoriteClubsTitle: String
        let favoriteClubsEmpty: String
        let shotsWord: PluralForms
        let language: String
        let myBagLink: String
        let clubsCountAndUnit: (_ count: Int, _ clubsWord: String, _ unit: String) -> String
        let legalPrivacy: String
        let legalTerms: String
        let legalSupport: String
        let signOut: String
        let signOutError: String
        let deleteAccount: String
        let deleteAccountConfirmTitle: String
        let deleteAccountConfirmBody: String
        let deleteAccountError: String
        // TN3194: отзыв токена Apple перед удалением не прошёл — аккаунт
        // намеренно не тронут.
        let appleRevokeError: String
    }

    struct Diagnostics {
        let checkNotRun: String
        let checkButton: String
        let unexpectedResponse: (_ raw: String) -> String
        let channelOk: String
        let appCheckRejected: String
        let errorPrefix: (_ message: String) -> String
    }

    struct Clubs {
        let categoryWood: String
        let categoryIron: String
        let categoryWedge: String
        let categoryPutter: String
        let missingCustom: String
    }

    struct Geolocation {
        let permissionDenied: String
        let positionUnavailable: String
    }

    struct RoundsService {
        let corruptedRoundData: String
    }

    // T5 (watch localization): strings used ONLY on the watch screen (hole
    // tracker, club picker, sync indicators, "no round" placeholder). Keys
    // that already exist verbatim elsewhere (common.par, common.metersShort/
    // yardsShort, common.missingCustomClub, holeTracker.holeTitleNoTotal,
    // holeTracker.toGreen) are reused directly from the watch views instead
    // of being duplicated here — same one-dictionary rule as the rest of
    // this file.
    struct Watch {
        let shotsOnHoleAria: (_ count: Int, _ word: String) -> String
        let shotsWord: PluralForms
        let removeShotAria: String
        let addShotAria: String
        let notSynced: (_ count: Int) -> String
        let syncFailed: String
        let syncFailedAria: String
        /// VoiceOver-only (task 6, второй заход): экран показывает флажок +
        /// «—» без слов, но незрячему пользователю нужна причина, а не
        /// тире. Видимого текста для этого состояния нет — только этот
        /// ключ.
        let distanceUnavailableAria: String
        let roundNotStarted: String
        let startOnPhone: String
        let staleShotNotSaved: (_ holeNumber: Int) -> String
        let staleRoundFinished: String
        let staleShotNotSavedAria: (_ holeNumber: Int) -> String
        let gotIt: String
    }

    let common: Common
    let auth: Auth
    let home: Home
    let bottomNav: BottomNav
    let courseSearch: CourseSearch
    let roundSetup: RoundSetup
    let groupLobby: GroupLobby
    let history: History
    let holeTracker: HoleTracker
    let leaderboard: Leaderboard
    let roundResults: RoundResults
    let joinGame: JoinGame
    let myBag: MyBag
    let profile: Profile
    let diagnostics: Diagnostics
    let clubs: Clubs
    let geolocation: Geolocation
    let roundsService: RoundsService
    let watch: Watch
}

extension Strings {
    /// T5 (watch localization): the watch has no LocaleManager (MainActor,
    /// iOS-only ViewModels/ — not linked into the watch target, see
    /// project.yml sources) and doesn't mutate the process-wide
    /// AppLocaleStore.current — its "current language" is a pure function of
    /// the latest snapshot from the phone (see WatchRoundViewModel.locale),
    /// so views recompute Strings straight from that value on every render
    /// instead of reading a mutable global. Mirrors the `current == .ru ?
    /// .ru : .en` ternary already used in AppLocaleStore.strings /
    /// LocaleManager.t.
    static func resolved(_ locale: AppLocale) -> Strings {
        locale == .ru ? .ru : .en
    }
}

extension Strings {
    static let ru = Strings(
        common: Common(
            cancel: "Отмена",
            retry: "Повторить",
            goHome: "На главную",
            loading: "Загрузка...",
            delete: "Удалить",
            you: "Вы",
            host: "Хост",
            unknown: "Неизвестно",
            missingCustomClub: "Клюшка",
            metersShort: "м",
            yardsShort: "я",
            km: "км",
            par: "Пар",
            playersEven: "Игроки на равных",
            deletedPlayerName: "Удалённый игрок",
            fallbackName: "Голфер",
            loadProfileError: "Не удалось загрузить профиль — проверьте сеть",
            holesWord: PluralForms(one: "лунка", few: "лунки", many: "лунок"),
            playersWord: PluralForms(one: "игрок", few: "игрока", many: "игроков"),
            clubsWord: PluralForms(one: "клюшка", few: "клюшки", many: "клюшек"),
            tee: Common.Tee(
                pro: Common.TeeInfo(label: "Pro", description: "Чемпионские · +10%"),
                men: Common.TeeInfo(label: "Мужские", description: "Стандартные"),
                senior: Common.TeeInfo(label: "Сеньорские", description: "Чуть ближе · −10%"),
                ladies: Common.TeeInfo(label: "Женские", description: "Ближе всего · −20%")
            )
        ),
        auth: Auth(
            tagline: "Трекинг гольф-раундов",
            signInWithGoogle: "ВОЙТИ ЧЕРЕЗ GOOGLE",
            noPresenterError: "Не найден корневой экран для входа",
            missingTokenError: "Google не вернул токен — попробуйте ещё раз",
            accountExistsError: "Этот адрес уже привязан к другому способу входа. Войдите тем способом, которым регистрировались",
            appleSignInError: "Не удалось войти через Apple — попробуйте ещё раз"
        ),
        home: Home(
            welcomeUppercase: "ДОБРО ПОЖАЛОВАТЬ",
            startNewRound: "Начать новый раунд",
            quickStart: "Быстрый старт без выбора поля",
            joinGame: "Присоединиться к игре",
            loadError: "Не удалось загрузить раунды",
            recentRounds: "Последние раунды",
            resumeUppercase: "ПРОДОЛЖИТЬ РАУНД",
            signOutAria: "Выйти",
            playedOf: { played, total in "Пройдено \(played) из \(total)" }
        ),
        bottomNav: BottomNav(rounds: "Раунды", history: "История", profile: "Профиль"),
        courseSearch: CourseSearch(
            title: "Поиск полей",
            searchPlaceholder: "Поиск полей или городов",
            manualEntry: "Указать поле вручную / пропустить",
            useQuery: { query in "Использовать «\(query)»" },
            searchingNearby: "Ищем поля рядом...",
            noResults: "Поля не найдены. Попробуйте другой запрос или укажите поле вручную.",
            courseFallbackName: "Поле для гольфа",
            errors: CourseSearch.Errors(
                apiKeyMissing: "API ключ Google Places не настроен",
                network: "Нет связи с серверами Google",
                denied: "Доступ к Places API (New) запрещён",
                quota: "Превышен лимит запросов к Places API",
                invalid: "Некорректный запрос к Places API"
            )
        ),
        roundSetup: RoundSetup(
            title: "Настройка раунда",
            creating: "Создаём...",
            startRound: "Начать раунд",
            courseNameSectionHeader: "НАЗВАНИЕ ПОЛЯ",
            courseNamePlaceholder: "Например: Гольф клуб Москва",
            changeCourse: "Сменить поле",
            holesSectionHeader: "КОЛИЧЕСТВО ЛУНОК",
            teeSectionHeader: "ТИИ (ОТКУДА ИГРАЕМ)",
            modeSectionHeader: "РЕЖИМ ИГРЫ",
            soloTitle: "Соло",
            soloDesc: "Только вы",
            groupTitle: "Группа",
            groupDesc: "С друзьями",
            groupHint: "После создания раунда вы получите код, чтобы пригласить друзей",
            formatSectionHeader: "ФОРМАТ ИГРЫ",
            strokeTitle: "Stroke",
            strokeDesc: "Общий счёт по ударам",
            matchTitle: "Match",
            matchDesc: "2 игрока · по лункам",
            matchHint: "Match play считается по победам в каждой лунке. Лучше всего работает 1 на 1.",
            createError: "Не удалось создать раунд. Попробуйте ещё раз."
        ),
        groupLobby: GroupLobby(
            title: "Лобби группы",
            loading: "Загрузка лобби...",
            loadError: "Не удалось загрузить лобби. Возможно, вы не участник этого раунда или пропала связь.",
            startError: "Не удалось запустить раунд. Попробуйте ещё раз.",
            leaveError: "Не удалось выйти из лобби. Обновите экран и попробуйте ещё раз.",
            codeCardTitle: "Код лобби",
            codeAccessibleLabel: { code in "Код лобби \(code), тап чтобы скопировать" },
            copied: "Скопировано",
            tapToCopy: "Тап чтобы скопировать",
            scanQr: "Или отсканируйте QR",
            qrCodeAria: "QR-код для входа в лобби",
            copyLink: "Скопировать ссылку",
            players: "Игроки",
            starting: "Запускаем...",
            startRoundButton: { count, word in "Начать раунд (\(count) \(word))" },
            waitingHost: "Ожидаем хоста...",
            leaveLobby: "Покинуть лобби",
            leaveConfirmTitle: "Покинуть лобби?",
            leaveConfirmHost: "Вы хост — без вас раунд не запустится. Лобби останется доступным по коду, но другим игрокам придётся ждать.",
            leaveConfirmGuest: "Вы выйдете из этого лобби. Можно вернуться по коду.",
            leave: "Покинуть",
            stay: "Остаться",
            you: "Вы"
        ),
        history: History(
            title: "История раундов",
            loadError: "Не удалось загрузить историю",
            empty: "Нет завершённых раундов"
        ),
        holeTracker: HoleTracker(
            loadError: "Не удалось загрузить раунд. Проверьте связь.",
            holeTitle: { current, total in "Лунка \(current) / \(total)" },
            holeTitleNoTotal: { current in "Лунка \(current)" },
            leaderboardAria: "Турнирная таблица",
            finishConfirmTitle: "Закончить игру?",
            finish: "Завершить",
            continueEditing: "Продолжить",
            finishConfirmPartial: { played, total in
                "Вы прошли \(played) из \(total) лунок. Пройденные удары попадут в итоги, незавершённые лунки — без ударов."
            },
            finishConfirmComplete: "Раунд будет записан в историю. Изменить удары после этого нельзя.",
            markGreenHint: "Отметьте грин, когда дойдёте — со следующего раунда покажем дистанцию",
            offlineNotice: "Нет сети — удары сохранятся автоматически",
            editParAria: { par in "Изменить пар лунки (сейчас \(par))" },
            distanceShort: "Дист.",
            editDistanceAria: { meters in "Изменить дистанцию лунки (сейчас \(meters) метров)" },
            teeAria: { label in "Тии: \(label)" },
            courseNotIdentified: "Укажите название поля, чтобы отмечать грины",
            toGreen: { distance in "До грина: \(distance)" },
            greenNotMarked: "Грин не отмечен",
            onGreenButton: "Я НА ГРИНЕ",
            markGreenAria: "Отметить грин текущей лунки",
            playerSwitch: "Игрок (тап для переключения)",
            hostScoresOthers: "Счёт за других ведёт хост",
            yourShots: "Ваши удары",
            shotsOf: { name in "Удары: \(name)" },
            shotsUppercase: "УДАРЫ",
            shotSeries: "Серия ударов",
            gpsReady: "GPS готов — дистанции пишутся",
            gpsWaiting: "Ждём GPS — дистанции не пишутся",
            clubPickerUppercase: "ВЫБОР КЛЮШКИ",
            prev: "Пред.",
            next: "Дальше",
            finishGame: "Закончить игру",
            finishWaitHost: "Завершит хост",
            finishEarly: "Закончить игру досрочно",
            saveShotError: "Не удалось сохранить удар.",
            finishRoundError: "Не удалось завершить раунд. Попробуйте ещё раз.",
            loadGreenMarksError: "Не удалось загрузить метки грина.",
            markGreenLoadingError: "Раунд ещё загружается — попробуйте через секунду.",
            markGreenSaveError: "Не удалось сохранить метку грина.",
            editHoleTitle: { holeNumber in "Параметры лунки \(holeNumber)" },
            editHoleHint: "Подгоните под реальное поле — изменение видно всем игрокам.",
            parUppercase: "ПАР",
            distanceMetersUppercase: "ДИСТАНЦИЯ, МЕТРОВ",
            distanceError: "Дистанция должна быть 50–700 метров",
            saving: "Сохраняем...",
            save: "Сохранить",
            holeSaveError: "Не удалось сохранить параметры лунки."
        ),
        leaderboard: Leaderboard(
            navTitle: "Таблица",
            loadError: "Не удалось загрузить таблицу. Проверьте связь.",
            lobbyNotStarted: "Лобби (ещё не начали)",
            roundFinished: "Раунд завершён",
            match1v1Suffix: " · Match 1 v 1",
            matchStatusUppercase: "MATCH STATUS",
            leading: { name in "Ведёт: \(name)" },
            matchDecided: "Матч решён",
            playedRemaining: { played, remaining in "Сыграно: \(played) · Осталось: \(remaining)" },
            columnPlayer: "Игрок",
            columnToPar: "К пару",
            noPlayers: "Игроков пока нет",
            you: "вы",
            strokesShortDot: "удар."
        ),
        roundResults: RoundResults(
            title: "Итоги раунда",
            loadError: "Не удалось загрузить итоги. Проверьте связь.",
            loading: "Загрузка результатов...",
            newRound: "Новый раунд",
            matchPlayUppercase: "MATCH PLAY",
            yourResultUppercase: "ВАШ РЕЗУЛЬТАТ",
            strokesShortDot: "уд.",
            winnerUppercase: "ПОБЕДИТЕЛЬ",
            leaderboardSectionTitle: "Таблица",
            clubsTitle: "Клюшки",
            clubsForPlayer: { name in "Клюшки · \(name)" },
            avgAbbrev: "ср.",
            scorecardTitle: "Скоркарта",
            holeColumnHeader: "Лунка",
            strokesRowHeader: "Удары"
        ),
        joinGame: JoinGame(
            navTitle: "Присоединиться",
            heading: "Введите код лобби",
            subtitle: "Хост в своём приложении видит 6-значный код или QR",
            codeAria: "Код лобби",
            codeLengthError: "Код должен содержать 6 символов",
            lobbyNotFound: "Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое.",
            joinError: "Не удалось присоединиться. Проверьте интернет и попробуйте снова.",
            connecting: "Подключаемся...",
            join: "Присоединиться"
        ),
        myBag: MyBag(
            title: "Моя сумка",
            saving: "Сохранение...",
            reorderDone: "Готово",
            reorder: "Порядок",
            addClub: "Добавить клюшку",
            bagComposition: "Состав сумки",
            ruleHint: "До 14 клюшек по правилам",
            freeSlots: { n in "Свободных слотов: \(n)" },
            metersFull: "Метры",
            yardsFull: "Ярды",
            nameFieldPlaceholderCustom: "Название",
            nameFieldPlaceholderModel: "Модель",
            distanceAria: { clubLabel, unit in "Дистанция \(clubLabel), \(unit)" },
            metersWord: "метры",
            yardsWord: "ярды",
            enableAria: { label in "Включить \(label) в сумку" },
            newClubTitle: { categoryLabel in "Новая клюшка · \(categoryLabel)" },
            newClubNamePlaceholder: "Название (например: Stealth 2 HD)",
            distanceMetersPlaceholder: "Дистанция, метров",
            distanceYardsPlaceholder: "Дистанция, ярды",
            add: "Добавить",
            saveError: "Не удалось сохранить изменения"
        ),
        profile: Profile(
            title: "Профиль",
            loadError: "Не удалось загрузить статистику",
            statsTitle: "Статистика",
            roundsLabel: "РАУНДОВ",
            avgShotsLabel: "СР. УДАРЫ",
            bestScoreLabel: "ЛУЧШИЙ СЧЁТ",
            bestVsParLabel: "BEST VS PAR",
            noStatsYet: "Сыграйте первый раунд, чтобы увидеть статистику.",
            distributionTitle: "Распределение по лункам",
            overAllHoles: { n, word in "За все \(n) \(word)" },
            playedHolesWord: PluralForms(one: "сыгранную лунку", few: "сыгранных лунки", many: "сыгранных лунок"),
            worseLabel: "Хуже",
            handicapTitle: "Гандикап",
            handicapBest8: { n in "по лучшим 8 из \(n) раундов · WHS-метод (без course rating / slope)" },
            handicapAvg: { n, word in "по \(n) \(word), среднее × 0.96" },
            roundsWord: PluralForms(one: "раунду", few: "раундам", many: "раундам"),
            handicapEmpty: "Сыграйте минимум 3 раунда — рассчитаем по WHS (best 8 из последних 20 × 0.96).",
            favoriteClubsTitle: "Любимые клюшки",
            favoriteClubsEmpty: "Статистика появится после первых ударов.",
            shotsWord: PluralForms(one: "удар", few: "удара", many: "ударов"),
            language: "Язык",
            myBagLink: "МОЯ СУМКА",
            clubsCountAndUnit: { count, clubsWord, unit in "\(count) \(clubsWord) · \(unit)" },
            legalPrivacy: "Политика конфиденциальности",
            legalTerms: "Условия использования",
            legalSupport: "Поддержка",
            signOut: "Выйти из аккаунта",
            signOutError: "Не удалось выйти — попробуйте ещё раз",
            deleteAccount: "Удалить аккаунт",
            deleteAccountConfirmTitle: "Удалить аккаунт?",
            deleteAccountConfirmBody: """
            Профиль, статистика и метки гринов удаляются навсегда. Ваши \
            соло-раунды будут удалены. В совместных раундах вместо вашего \
            имени останется «Удалённый игрок» — счёт партнёров не \
            пострадает. Это действие необратимо.
            """,
            deleteAccountError: "Не удалось удалить аккаунт. Проверьте соединение и попробуйте ещё раз.",
            appleRevokeError: "Не удалось отозвать доступ Apple. Аккаунт не удалён — попробуйте ещё раз."
        ),
        diagnostics: Diagnostics(
            checkNotRun: "Проверка связи не запускалась",
            checkButton: "Проверить связь с сервером",
            unexpectedResponse: { raw in "Неожиданный ответ: \(raw)" },
            channelOk: "Сервер отвечает, App Check пропускает. Канал работает.",
            appCheckRejected: "App Check отклонил вызов — зарегистрируйте debug token в консоли Firebase",
            errorPrefix: { message in "Ошибка: \(message)" }
        ),
        clubs: Clubs(
            categoryWood: "Драйвер и вуды",
            categoryIron: "Айроны",
            categoryWedge: "Вейджи",
            categoryPutter: "Паттер",
            missingCustom: "Клюшка"
        ),
        geolocation: Geolocation(
            permissionDenied: "Доступ к геолокации запрещён. Разрешите его в Настройках.",
            positionUnavailable: "Не удалось определить местоположение"
        ),
        roundsService: RoundsService(corruptedRoundData: "Данные раунда повреждены"),
        watch: Watch(
            shotsOnHoleAria: { count, word in "На лунке: \(count) \(word)" },
            shotsWord: PluralForms(one: "удар", few: "удара", many: "ударов"),
            removeShotAria: "Убрать удар",
            addShotAria: "Добавить удар",
            notSynced: { count in "Не синхронизировано: \(count)" },
            syncFailed: "Не удалось синхронизировать",
            syncFailedAria: "Не удалось синхронизировать удары этой лунки",
            distanceUnavailableAria: "Дистанция до грина недоступна",
            roundNotStarted: "Раунд не начат",
            startOnPhone: "Начните раунд на телефоне",
            staleShotNotSaved: { holeNumber in "Лунка \(holeNumber): удар не сохранён" },
            staleRoundFinished: "Раунд уже завершён",
            staleShotNotSavedAria: { holeNumber in "Удар на лунке \(holeNumber) не сохранён — раунд уже завершён" },
            gotIt: "Понятно"
        )
    )

    static let en = Strings(
        common: Common(
            cancel: "Cancel",
            retry: "Retry",
            goHome: "Go home",
            loading: "Loading...",
            delete: "Delete",
            you: "You",
            host: "Host",
            unknown: "Unknown",
            missingCustomClub: "Club",
            metersShort: "m",
            yardsShort: "yd",
            km: "km",
            par: "Par",
            playersEven: "Players are even",
            deletedPlayerName: "Removed player",
            fallbackName: "Golfer",
            loadProfileError: "Couldn't load your profile — check your connection",
            holesWord: PluralForms(one: "hole", few: "holes", many: "holes"),
            playersWord: PluralForms(one: "player", few: "players", many: "players"),
            clubsWord: PluralForms(one: "club", few: "clubs", many: "clubs"),
            tee: Common.Tee(
                pro: Common.TeeInfo(label: "Pro", description: "Championship · +10%"),
                men: Common.TeeInfo(label: "Men's", description: "Standard"),
                senior: Common.TeeInfo(label: "Senior", description: "A bit closer · −10%"),
                ladies: Common.TeeInfo(label: "Ladies'", description: "Closest · −20%")
            )
        ),
        auth: Auth(
            tagline: "Track your golf rounds",
            signInWithGoogle: "SIGN IN WITH GOOGLE",
            noPresenterError: "Couldn't find a root screen to sign in from",
            missingTokenError: "Google didn't return a token — try again",
            accountExistsError: "This email is already linked to a different sign-in method. Sign in the way you originally registered",
            appleSignInError: "Couldn't sign in with Apple — try again"
        ),
        home: Home(
            welcomeUppercase: "WELCOME",
            startNewRound: "Start new round",
            quickStart: "Quick start without picking a course",
            joinGame: "Join a game",
            loadError: "Couldn't load rounds",
            recentRounds: "Recent rounds",
            resumeUppercase: "CONTINUE ROUND",
            signOutAria: "Sign out",
            playedOf: { played, total in "Played \(played) of \(total)" }
        ),
        bottomNav: BottomNav(rounds: "Rounds", history: "History", profile: "Profile"),
        courseSearch: CourseSearch(
            title: "Find a course",
            searchPlaceholder: "Search courses or cities",
            manualEntry: "Enter a course manually / skip",
            useQuery: { query in "Use \"\(query)\"" },
            searchingNearby: "Finding nearby courses...",
            noResults: "No courses found. Try another search or enter a course manually.",
            courseFallbackName: "Golf course",
            errors: CourseSearch.Errors(
                apiKeyMissing: "Google Places API key is not configured",
                network: "Can't reach Google's servers",
                denied: "Access to Places API (New) denied",
                quota: "Places API request limit exceeded",
                invalid: "Invalid Places API request"
            )
        ),
        roundSetup: RoundSetup(
            title: "Round setup",
            creating: "Creating...",
            startRound: "Start round",
            courseNameSectionHeader: "COURSE NAME",
            courseNamePlaceholder: "E.g. Moscow Golf Club",
            changeCourse: "Change course",
            holesSectionHeader: "NUMBER OF HOLES",
            teeSectionHeader: "TEE (WHERE YOU PLAY FROM)",
            modeSectionHeader: "GAME MODE",
            soloTitle: "Solo",
            soloDesc: "Just you",
            groupTitle: "Group",
            groupDesc: "With friends",
            groupHint: "Once the round is created you'll get a code to invite friends",
            formatSectionHeader: "FORMAT",
            strokeTitle: "Stroke",
            strokeDesc: "Total strokes",
            matchTitle: "Match",
            matchDesc: "2 players · by hole",
            matchHint: "Match play is scored by holes won. Works best 1v1.",
            createError: "Couldn't create the round. Try again."
        ),
        groupLobby: GroupLobby(
            title: "Group lobby",
            loading: "Loading lobby...",
            loadError: "Couldn't load the lobby. You may not be a member of this round, or the connection dropped.",
            startError: "Couldn't start the round. Try again.",
            leaveError: "Couldn't leave the lobby. Refresh and try again.",
            codeCardTitle: "Lobby code",
            codeAccessibleLabel: { code in "Lobby code \(code), tap to copy" },
            copied: "Copied",
            tapToCopy: "Tap to copy",
            scanQr: "Or scan the QR code",
            qrCodeAria: "QR code to join the lobby",
            copyLink: "Copy link",
            players: "Players",
            starting: "Starting...",
            startRoundButton: { count, word in "Start round (\(count) \(word))" },
            waitingHost: "Waiting for the host...",
            leaveLobby: "Leave lobby",
            leaveConfirmTitle: "Leave the lobby?",
            leaveConfirmHost: "You're the host — the round can't start without you. The lobby stays open by code, but other players will have to wait.",
            leaveConfirmGuest: "You'll leave this lobby. You can rejoin with the code.",
            leave: "Leave",
            stay: "Stay",
            you: "You"
        ),
        history: History(
            title: "Round history",
            loadError: "Couldn't load history",
            empty: "No finished rounds yet"
        ),
        holeTracker: HoleTracker(
            loadError: "Couldn't load the round. Check your connection.",
            holeTitle: { current, total in "Hole \(current) / \(total)" },
            holeTitleNoTotal: { current in "Hole \(current)" },
            leaderboardAria: "Leaderboard",
            finishConfirmTitle: "Finish the game?",
            finish: "Finish",
            continueEditing: "Continue",
            finishConfirmPartial: { played, total in
                "You've played \(played) of \(total) holes. Recorded strokes will count toward the totals; unplayed holes get no strokes."
            },
            finishConfirmComplete: "The round will be saved to history. You won't be able to change strokes after this.",
            markGreenHint: "Mark the green when you get there — we'll show distance from your next round",
            offlineNotice: "Offline — strokes will save automatically",
            editParAria: { par in "Change hole par (currently \(par))" },
            distanceShort: "Dist.",
            editDistanceAria: { meters in "Change hole distance (currently \(meters) meters)" },
            teeAria: { label in "Tee: \(label)" },
            courseNotIdentified: "Enter a course name to mark greens",
            toGreen: { distance in "To green: \(distance)" },
            greenNotMarked: "Green not marked",
            onGreenButton: "I'M ON THE GREEN",
            markGreenAria: "Mark the green for this hole",
            playerSwitch: "Player (tap to switch)",
            hostScoresOthers: "The host scores for others",
            yourShots: "Your strokes",
            shotsOf: { name in "Strokes: \(name)" },
            shotsUppercase: "STROKES",
            shotSeries: "Stroke sequence",
            gpsReady: "GPS ready — distances recorded",
            gpsWaiting: "Waiting for GPS — distances not recorded",
            clubPickerUppercase: "PICK A CLUB",
            prev: "Prev.",
            next: "Next",
            finishGame: "Finish game",
            finishWaitHost: "Host will finish",
            finishEarly: "Finish game early",
            saveShotError: "Couldn't save the stroke.",
            finishRoundError: "Couldn't finish the round. Try again.",
            loadGreenMarksError: "Couldn't load green marks.",
            markGreenLoadingError: "The round is still loading — try again in a second.",
            markGreenSaveError: "Couldn't save the green mark.",
            editHoleTitle: { holeNumber in "Hole \(holeNumber) settings" },
            editHoleHint: "Match it to the real course — the change is visible to every player.",
            parUppercase: "PAR",
            distanceMetersUppercase: "DISTANCE, METERS",
            distanceError: "Distance must be 50–700 meters",
            saving: "Saving...",
            save: "Save",
            holeSaveError: "Couldn't save the hole settings."
        ),
        leaderboard: Leaderboard(
            navTitle: "Standings",
            loadError: "Couldn't load the leaderboard. Check your connection.",
            lobbyNotStarted: "Lobby (not started yet)",
            roundFinished: "Round finished",
            match1v1Suffix: " · Match 1 v 1",
            matchStatusUppercase: "MATCH STATUS",
            leading: { name in "Leading: \(name)" },
            matchDecided: "Match decided",
            playedRemaining: { played, remaining in "Played: \(played) · Remaining: \(remaining)" },
            columnPlayer: "Player",
            columnToPar: "To par",
            noPlayers: "No players yet",
            you: "you",
            strokesShortDot: "str."
        ),
        roundResults: RoundResults(
            title: "Round results",
            loadError: "Couldn't load the results. Check your connection.",
            loading: "Loading results...",
            newRound: "New round",
            matchPlayUppercase: "MATCH PLAY",
            yourResultUppercase: "YOUR RESULT",
            strokesShortDot: "str.",
            winnerUppercase: "WINNER",
            leaderboardSectionTitle: "Leaderboard",
            clubsTitle: "Clubs",
            clubsForPlayer: { name in "Clubs · \(name)" },
            avgAbbrev: "avg.",
            scorecardTitle: "Scorecard",
            holeColumnHeader: "Hole",
            strokesRowHeader: "Strokes"
        ),
        joinGame: JoinGame(
            navTitle: "Join",
            heading: "Enter the lobby code",
            subtitle: "The host sees a 6-character code or QR in their app",
            codeAria: "Lobby code",
            codeLengthError: "The code must be 6 characters",
            lobbyNotFound: "No lobby found with that code. Check the code or ask the host to create a new one.",
            joinError: "Couldn't join. Check your connection and try again.",
            connecting: "Connecting...",
            join: "Join"
        ),
        myBag: MyBag(
            title: "My bag",
            saving: "Saving...",
            reorderDone: "Done",
            reorder: "Reorder",
            addClub: "Add club",
            bagComposition: "Bag composition",
            ruleHint: "Up to 14 clubs by the rules",
            freeSlots: { n in "Free slots: \(n)" },
            metersFull: "Meters",
            yardsFull: "Yards",
            nameFieldPlaceholderCustom: "Name",
            nameFieldPlaceholderModel: "Model",
            distanceAria: { clubLabel, unit in "Distance \(clubLabel), \(unit)" },
            metersWord: "meters",
            yardsWord: "yards",
            enableAria: { label in "Enable \(label) in the bag" },
            newClubTitle: { categoryLabel in "New club · \(categoryLabel)" },
            newClubNamePlaceholder: "Name (e.g. Stealth 2 HD)",
            distanceMetersPlaceholder: "Distance, meters",
            distanceYardsPlaceholder: "Distance, yards",
            add: "Add",
            saveError: "Couldn't save the changes"
        ),
        profile: Profile(
            title: "Profile",
            loadError: "Couldn't load stats",
            statsTitle: "Stats",
            roundsLabel: "ROUNDS",
            avgShotsLabel: "AVG. STROKES",
            bestScoreLabel: "BEST SCORE",
            bestVsParLabel: "BEST VS PAR",
            noStatsYet: "Play your first round to see stats.",
            distributionTitle: "Hole result distribution",
            overAllHoles: { n, word in "Across all \(n) \(word)" },
            playedHolesWord: PluralForms(one: "hole played", few: "holes played", many: "holes played"),
            worseLabel: "Worse",
            handicapTitle: "Handicap",
            handicapBest8: { n in "Best 8 of \(n) rounds · WHS method (no course rating / slope)" },
            handicapAvg: { n, word in "Across \(n) \(word), average × 0.96" },
            roundsWord: PluralForms(one: "round", few: "rounds", many: "rounds"),
            handicapEmpty: "Play at least 3 rounds — we'll calculate it via WHS (best 8 of the last 20 × 0.96).",
            favoriteClubsTitle: "Favorite clubs",
            favoriteClubsEmpty: "Stats will show up after your first strokes.",
            shotsWord: PluralForms(one: "stroke", few: "strokes", many: "strokes"),
            language: "Language",
            myBagLink: "MY BAG",
            clubsCountAndUnit: { count, clubsWord, unit in "\(count) \(clubsWord) · \(unit)" },
            legalPrivacy: "Privacy Policy",
            legalTerms: "Terms of Use",
            legalSupport: "Support",
            signOut: "Sign out",
            signOutError: "Couldn't sign out — try again",
            deleteAccount: "Delete account",
            deleteAccountConfirmTitle: "Delete account?",
            deleteAccountConfirmBody: """
            Your profile, stats, and green marks are deleted permanently. \
            Your solo rounds will be deleted. In shared rounds, your name \
            is replaced with "Removed player" — your partners' scores are \
            unaffected. This action cannot be undone.
            """,
            deleteAccountError: "Couldn't delete the account. Check your connection and try again.",
            appleRevokeError: "Couldn't revoke Apple access. The account was not deleted — try again."
        ),
        diagnostics: Diagnostics(
            checkNotRun: "Connection check hasn't run yet",
            checkButton: "Check server connection",
            unexpectedResponse: { raw in "Unexpected response: \(raw)" },
            channelOk: "Server responding, App Check passing. Channel works.",
            appCheckRejected: "App Check rejected the call — register the debug token in Firebase console",
            errorPrefix: { message in "Error: \(message)" }
        ),
        clubs: Clubs(
            categoryWood: "Driver & woods",
            categoryIron: "Irons",
            categoryWedge: "Wedges",
            categoryPutter: "Putter",
            missingCustom: "Club"
        ),
        geolocation: Geolocation(
            permissionDenied: "Location access denied. Enable it in Settings.",
            positionUnavailable: "Couldn't determine your location"
        ),
        roundsService: RoundsService(corruptedRoundData: "Round data is corrupted"),
        watch: Watch(
            shotsOnHoleAria: { count, word in "On this hole: \(count) \(word)" },
            shotsWord: PluralForms(one: "stroke", few: "strokes", many: "strokes"),
            removeShotAria: "Remove stroke",
            addShotAria: "Add stroke",
            notSynced: { count in "Not synced: \(count)" },
            syncFailed: "Couldn't sync",
            syncFailedAria: "Couldn't sync this hole's strokes",
            distanceUnavailableAria: "Distance to green unavailable",
            roundNotStarted: "No round in progress",
            startOnPhone: "Start a round on your phone",
            staleShotNotSaved: { holeNumber in "Hole \(holeNumber): stroke not saved" },
            staleRoundFinished: "Round already finished",
            staleShotNotSavedAria: { holeNumber in "Stroke on hole \(holeNumber) not saved — round already finished" },
            gotIt: "Got it"
        )
    )
}
