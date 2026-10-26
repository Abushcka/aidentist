# AI Dentist — мобильные приложения (Android, iPhone, iPad)

Нативные оболочки над панелью клиники. При первом запуске приложение спрашивает название клиники
(например `stomatolog` → `https://stomatolog.147-224-205-88.sslip.io`) и дальше открывает её сразу.
Вход, расписание, пациенты — всё то же, что в браузере: обновления панели на сервере появляются в приложении
без переустановки.

## Скачать
Последняя версия: https://github.com/Abushcka/aidentist/releases/latest

| Файл | Для чего |
|---|---|
| `AI-Dentist.apk` | Android-телефоны и планшеты — установить напрямую |
| `AI-Dentist-iOS.ipa` | iPhone и iPad — через Sideloadly / AltStore |
| `AI-Dentist-GooglePlay.aab` | для будущей публикации в Google Play |

Прямая ссылка на APK (можно отправить сотрудникам в WhatsApp/Telegram):
https://github.com/Abushcka/aidentist/releases/latest/download/AI-Dentist.apk

## Установка на Android
1. Открыть ссылку на APK на телефоне → «Скачать».
2. Открыть скачанный файл. Телефон попросит разрешить «Установку неизвестных приложений» для браузера — разрешить.
3. «Установить». Если Play Защита предупредит — «Подробнее» → «Всё равно установить».
4. Обновление: так же скачать новый APK и установить поверх — данные и вход сохранятся.

## Установка на iPhone / iPad (без App Store)
Apple разрешает ставить приложения не из App Store только с подписью Apple ID. Файл `.ipa` собран без подписи —
её добавляет программа при установке.

**Sideloadly (Mac или Windows):**
1. Скачать Sideloadly с sideloadly.io, подключить iPhone/iPad кабелем, на устройстве нажать «Доверять».
2. Перетащить `AI-Dentist-iOS.ipa` в Sideloadly, ввести свой Apple ID, нажать Start.
3. На устройстве: Настройки → Основные → VPN и управление устройством → ваш Apple ID → «Доверять».
4. iOS 16+: Настройки → Конфиденциальность и безопасность → Режим разработчика → включить, перезагрузить.

Ограничения бесплатного Apple ID: подпись действует **7 дней** (потом переподписать в Sideloadly или включить
авто-обновление в AltStore), не более 3 таких приложений на устройстве.
С платным аккаунтом Apple Developer ($99/год) подпись живёт год, можно раздавать через TestFlight
и затем опубликовать в App Store — проект к этому готов.

**Без установки файла** (работает сразу на любом iPhone/iPad): открыть адрес клиники в Safari →
«Поделиться» → «На экран “Домой”». Это та же панель как приложение (PWA).

## Как пользоваться
- Сменить клинику: кнопка «Сменить клинику» на заставке при запуске; на Android — также кнопка «Назад» → «Сменить клинику»;
  на iPhone/iPad — встряхнуть устройство.
- PDF смет и файлы пациентов открываются в отдельном окне (можно сохранить или переслать).
- WhatsApp, Telegram и телефонные номера открываются в своих приложениях.
- iPhone/iPad: потянуть страницу вниз — обновить.

## Устройство проекта
```
shared/launcher/     экран выбора клиники (общий для Android и iOS)
android/             Android (Java, без сторонних библиотек), applicationId kg.aidentist.app
ios/                 iOS + iPadOS (Swift, WKWebView), проект генерирует XcodeGen из ios/project.yml
art/make_icons.py    иконки из static/icons/icon-512.png панели
.github/workflows/   сборка в GitHub Actions на каждый push в ветку mobile-app → GitHub Releases
```
Короткие названия клиник превращаются в адрес по `BASE_DOMAIN` в `shared/launcher/index.html`.
Если у платформы появится свой домен — поменять там и выпустить новую версию (полный адрес можно вводить и сейчас).

## Сборка
Автоматически: любой push в `mobile-app` → GitHub Actions → новый выпуск в Releases (~10 мин).
Ошибки сборки дублируются в ветку `ci-logs`.

Секреты репозитория (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`. Сам ключ хранится у владельца
(`DentCRM/mobile-signing/` на Mac). **Ключ нельзя терять** — без него не выпустить обновление и не обновить приложение в Google Play.

Вручную на Mac с Xcode: `brew install xcodegen && cd ios && xcodegen generate && open AIDentist.xcodeproj`,
выбрать свою команду (Apple ID) в Signing & Capabilities и запустить на подключённом iPhone/iPad.

## Публикация в магазинах (позже)
- **Google Play**: аккаунт разработчика ($25 один раз) → загрузить `AI-Dentist-GooglePlay.aab`, политика
  конфиденциальности (ссылка), описание и скриншоты.
- **App Store**: Apple Developer Program ($99/год) → в Xcode Archive → App Store Connect → TestFlight → проверка.
  Apple строго смотрит на «сайт в обёртке»: к публикации стоит добавить нативные функции
  (push-уведомления о записях, Face ID для входа) — это следующий шаг.
