#!/bin/bash
# Каноничная выкладка в App Store Connect (TestFlight / App Store):
#   ./ios/scripts/release.sh            # архив + загрузка версии из project.yml
#   ./ios/scripts/release.sh --no-upload  # только архив (проверить локально)
#
# Перед запуском:
#   1. Поднять CFBundleVersion (build number) в ios/project.yml — у iOS И
#      у watch-таргета одинаково; одинаковый build number App Store Connect
#      отклоняет. CFBundleShortVersionString у обоих таргетов обязана
#      совпадать (companion).
#   2. Часы Mac должны быть точными (`sntp time.apple.com` ≈ 0): свежий
#      сертификат Apple Distribution с notBefore «из будущего» macOS бракует
#      как EXPIRED, и экспорт падает «Signing certificate is invalid».
#   3. В связке должен быть Apple Distribution с приватным ключом
#      (Xcode → Settings → Accounts → Manage Certificates → + → Apple
#      Distribution); Development-сертификата для экспорта недостаточно.
#   4. Запись приложения в App Store Connect с Bundle ID
#      com.dzhambulat.smartgolfcaddy (НЕ .web — это Services ID).
#
# DerivedData/архивы держим ВНЕ iCloud-папок (см. build.sh — File Provider
# портит артефакты codesign'а). Предупреждения «Upload Symbols Failed …
# dSYM for FirebaseFirestoreInternal/grpc/absl» — норма: это precompiled
# бинарники Firebase без dSYM, на приём сборки не влияют.
set -euo pipefail
cd "$(dirname "$0")/.."

DD="${DD:-$HOME/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local}"
VERSION=$(grep -m1 'CFBundleShortVersionString:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -m1 'CFBundleVersion:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
ARCHIVE="${ARCHIVE:-$HOME/Library/Developer/Xcode/Archives/SmartGolfCaddy-$VERSION-$BUILD.xcarchive}"
EXPORT="${EXPORT:-$HOME/Library/Developer/Xcode/Archives/export-$VERSION-$BUILD}"

echo "==> Smart Golf Caddy $VERSION ($BUILD)"
echo "==> clock offset vs time.apple.com:"
sntp time.apple.com 2>/dev/null | tail -1 || true

xcodegen
rm -rf "$ARCHIVE"
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -configuration Release -destination "generic/platform=iOS" \
  -derivedDataPath "$DD" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates archive | grep -E "error:|warning: .*entitle|ARCHIVE (SUCCEEDED|FAILED)"

echo "==> archive: $ARCHIVE"
plutil -extract ApplicationProperties.CFBundleShortVersionString raw "$ARCHIVE/Info.plist"
plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCHIVE/Info.plist"

if [[ "${1:-}" == "--no-upload" ]]; then
  echo "==> --no-upload: архив готов, загрузка пропущена"
  exit 0
fi

rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  | grep -v "^$" | grep -i -E "Progress|Uploaded|error:|EXPORT (SUCCEEDED|FAILED)" \
  | grep -v "Upload Symbols Failed"
