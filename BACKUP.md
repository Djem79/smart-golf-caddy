# Smart Golf Caddy — Backup & Recovery

Полное руководство по бэкапу и восстановлению. Установлено 2026-05-19
при выпуске v1.0.0.

## Что забэкаплено и как это работает

| Слой | Где хранится | Retention | Что защищает |
|---|---|---|---|
| **Код приложения** | Git tag `v1.0.0` + GitHub Release | вечно | Откат к любой ранее зафиксированной версии |
| **Functions secrets** (`RESEND_API_KEY`) | GCP Secret Manager, auto-versioned | вечно | Случайная ротация / удаление ключа |
| **Hosting (frontend bundle)** | Firebase auto rolling-history | ~10 последних релизов | Откат недавнего деплоя одним кликом |
| **Firestore (PITR)** | Cloud-managed, привязан к БД | **7 дней** | Точечный откат на любой момент с точностью до минуты — от accidental deletes / порчи данных |
| **Firestore (daily snapshots)** | Cloud-managed | **98 дней** | Долгосрочные инциденты, которые обнаружены через недели |

## Как восстановить

### Откат кода

```bash
cd "/Users/dzhambulat/Documents/Smart golf caddy"
source ~/.nvm/nvm.sh

# Посмотреть доступные теги
git tag -l

# Откатить рабочую копию
git checkout v1.0.0

# Передеплоить всё, что было в этой версии
npm run build
firebase deploy --only hosting
cd functions && npm run build && cd ..
firebase deploy --only functions,firestore
```

### Откат hosting (без редеплоя)

Firebase Console → Hosting → Release history → найти нужную версию →
кнопка **«Rollback»**. Применится мгновенно.

### Восстановление Firestore (точечный момент, PITR)

⚠️ **Restore создаёт НОВУЮ базу**, не перезаписывает default.

```bash
# Найти доступные timestamp'ы
firebase firestore:databases:list

# Восстановить состояние на конкретный момент в новую базу
gcloud firestore databases restore \
  --source-database=projects/smart-golf-caddy/databases/(default) \
  --destination-database=default-restored-$(date +%Y%m%d) \
  --backup-time=2026-05-19T20:00:00Z
```

Затем в коде приложения временно переключить `firebase.ts` на новую
базу (через `getFirestore(app, 'default-restored-…')`), проверить
данные, при необходимости перелить нужные документы обратно в
`default`.

### Восстановление Firestore (из daily snapshot)

Firebase Console → Firestore Database → **Disaster Recovery** →
**«View all backups»** → выбрать snapshot → **Restore** → имя новой
базы. Дальше — как с PITR.

## Что хранится в каждом резервном слое

### Git tag `v1.0.0`

- Полный исходный код (web app + functions)
- Firestore rules + indexes
- SETUP.md, BACKUP.md, README, CLAUDE.md
- tasks/ (история спринтов)
- ❌ НЕТ: node_modules, .env.local, dist, functions/lib, RESEND ключи

### GCP Secret Manager (Functions secrets)

- `RESEND_API_KEY` — версионируется автоматически при каждом
  `firebase functions:secrets:set RESEND_API_KEY`
- Старые версии помечаются disabled, не удаляются
- Откат: `firebase functions:secrets:enable RESEND_API_KEY:N`

### Firestore PITR

- Все коллекции (`users`, `rounds`, `userQuota`)
- Любой момент времени с точностью до 1 минуты в окне 7 дней
- Включается раз — потом сама поддерживает скользящее окно

### Firestore Daily Backups

- Полные снимки БД, по одному в день
- Хранятся 98 дней (выбранный вами retention)
- Список доступных бэкапов: Disaster Recovery → View all backups

## Стоимость

Все компоненты бэкапа сейчас в пределах **<$1/мес** на наших
объёмах данных (десятки KB):

- PITR: бесплатно (входит в Firestore базовый тариф)
- Daily backups: $0.18/GB/мес × несколько KB ≈ $0.00 в нашем случае
- Hosting history: бесплатно
- Secret Manager: бесплатно для 6 active версий
- GitHub: бесплатный план достаточен

С ростом пользователей самая дорогая статья — daily backups (98 дней
× размер БД). При 1 GB данных = ~$1.50/мес. До этого момента бэкап
платный, но копеечный.

## Что НЕ забэкаплено и не должно быть

- **Firebase Auth users** — управляется Google, есть свой механизм
  recovery. При желании можно экспортировать вручную через
  `firebase auth:export`.
- **Places API key** — генерируется в Google Cloud Console, можно
  пересоздать в любой момент (HTTP-referrer привязка остаётся).
- **Resend API key** — хранится у Resend; ротация делается одной
  командой `firebase functions:secrets:set RESEND_API_KEY` + redeploy.

## Регулярные проверки

Раз в квартал стоит:

1. Зайти в **Disaster Recovery → View all backups** и убедиться,
   что новые snapshots создаются ежедневно.
2. Проверить, что `firebase functions:secrets:access RESEND_API_KEY`
   возвращает рабочий ключ.
3. Создать тестовый раунд → удалить → восстановить через PITR в
   новую БД, чтобы убедиться, что recovery flow работает.

## Triage: что делать в инциденте

| Сценарий | Действие |
|---|---|
| Случайно удалил раунд | PITR-restore в новую БД, скопировать документ обратно |
| Plr исследовал коллекцию `users` целиком | PITR-restore в новую БД, сверить, мигрировать |
| Старый код вернулся в Hosting | Console → Hosting → Rollback на нужную версию |
| Cloud Function крашится | `firebase functions:log` → откатить через `git checkout <prev-tag> && firebase deploy --only functions` |
| Resend ключ скомпрометирован | Resend dashboard → revoke; сгенерировать новый; `firebase functions:secrets:set RESEND_API_KEY`; `firebase deploy --only functions` |
| Полная потеря Firebase project | Из git репо: новый Firebase project → `firebase use <new>` → deploy всё; daily backup из Disaster Recovery → restore в новую БД |
