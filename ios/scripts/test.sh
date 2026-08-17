#!/bin/bash
# Каноничный запуск тестов iOS-приложения. Инкапсулирует обязательные
# env-переменные: FIREBASE_SOURCE_FIRESTORE (firebase-ios-sdk#14464) и
# DerivedData вне iCloud (артефакты в ~/Documents портит File Provider).
set -euo pipefail
cd "$(dirname "$0")/.."
export FIREBASE_SOURCE_FIRESTORE=1
DD="${DD:-$HOME/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local}"
SIM_NAME="${SIM_NAME:-iPhone 17}"
xcodegen
exec xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" test "$@"
