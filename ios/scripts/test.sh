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
xcodegen
exec xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" test "$@"
