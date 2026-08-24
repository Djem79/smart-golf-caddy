#!/bin/bash
# Каноничный запуск тестов iOS-приложения. Инкапсулирует обязательные
# env-переменные: DerivedData вне iCloud (артефакты в ~/Documents портит
# File Provider). Firestore линкуется ТОЛЬКО в app-таргет: source-сборка
# (FIREBASE_SOURCE_FIRESTORE) создавала вторую копию FirebaseCore и роняла
# приложение (FIRIllegalStateException на Firestore.firestore()).
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${DD:-$HOME/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local}"
SIM_NAME="${SIM_NAME:-iPhone 17}"
WATCH_SIM_NAME="${WATCH_SIM_NAME:-Apple Watch Series 11 (46mm)}"
xcodegen
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" test "$@"
# Watch companion (Phase 3c): SmartGolfCaddyWatchTests — smoke-тест,
# подтверждающий, что общий домен (Models/) линкуется и исполняется на
# watchOS.
exec xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddyWatch \
  -destination "platform=watchOS Simulator,name=$WATCH_SIM_NAME" \
  -derivedDataPath "$DD" test
