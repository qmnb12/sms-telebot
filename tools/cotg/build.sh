#!/usr/bin/env bash
# Build SMS Telebot for an ARM64 Android phone from Termux / Code On The Go.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
cd "$PROJECT_ROOT"

command -v flutter >/dev/null 2>&1 || fail "Flutter is not installed. See https://github.com/retired64/flutter-for-termux"
command -v java >/dev/null 2>&1 || fail "Java is not installed. Install OpenJDK 17 or 21."
command -v keytool >/dev/null 2>&1 || fail "keytool is missing. Install an OpenJDK package that includes keytool."

FLUTTER_ROOT="${FLUTTER_ROOT:-}"
if [[ -z "$FLUTTER_ROOT" ]]; then
  for candidate in "$TERMUX_PREFIX/opt/flutter" "$HOME/flutter" "$HOME/.fvm/versions/3.32.8"; do
    if [[ -f "$candidate/packages/flutter_tools/gradle/build.gradle.kts" ]]; then FLUTTER_ROOT="$candidate"; break; fi
  done
fi
if [[ -z "$FLUTTER_ROOT" ]]; then
  FLUTTER_BIN="$(readlink -f "$(command -v flutter)" 2>/dev/null || command -v flutter)"
  [[ "$FLUTTER_BIN" == */bin/flutter ]] && FLUTTER_ROOT="${FLUTTER_BIN%/bin/flutter}"
fi
[[ -n "$FLUTTER_ROOT" && -f "$FLUTTER_ROOT/packages/flutter_tools/gradle/build.gradle.kts" ]] || fail "Set FLUTTER_ROOT to the Flutter SDK directory."

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$ANDROID_SDK_ROOT" ]]; then
  for candidate in "$TERMUX_PREFIX/opt/android-sdk" "$HOME/Android/Sdk" "$HOME/android-sdk"; do
    if [[ -d "$candidate/platforms" || -d "$candidate/build-tools" ]]; then ANDROID_SDK_ROOT="$candidate"; break; fi
  done
fi
[[ -n "$ANDROID_SDK_ROOT" && -d "$ANDROID_SDK_ROOT" ]] || fail "Set ANDROID_SDK_ROOT (or ANDROID_HOME) to your Android SDK."

export FLUTTER_ROOT ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
note "Flutter / Java versions"
flutter --version | head -n 3
java -version 2>&1 | head -n 1

PROJECT_CONFIG="$TERMUX_PREFIX/share/flutter/flutter_project_config.sh"
if [[ -f "$PROJECT_CONFIG" ]]; then
  note "Applying Termux Android toolchain settings"
  bash "$PROJECT_CONFIG" "$PROJECT_ROOT"
fi

cat > android/local.properties <<PROPERTIES
sdk.dir=$ANDROID_SDK_ROOT
flutter.sdk=$FLUTTER_ROOT
PROPERTIES

KEY_PROPERTIES="android/key.properties"
LOCAL_KEYSTORE="android/app/cotg-local-test.jks"
if [[ ! -f "$KEY_PROPERTIES" ]]; then
  note "Creating a local test signing key"
  STORE_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  keytool -genkeypair -noprompt -keystore "$LOCAL_KEYSTORE" -storepass "$STORE_PASSWORD" -keypass "$STORE_PASSWORD" -alias sms-telebot-local -dname "CN=SMS Telebot Local Test" -keyalg RSA -keysize 2048 -validity 10000
  cat > "$KEY_PROPERTIES" <<PROPERTIES
storePassword=$STORE_PASSWORD
keyPassword=$STORE_PASSWORD
keyAlias=sms-telebot-local
storeFile=cotg-local-test.jks
PROPERTIES
  unset STORE_PASSWORD
fi

note "Resolving Flutter packages"
flutter pub get
note "Building ARM64 release APK"
flutter build apk --release --target-platform android-arm64

APK_SOURCE="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$APK_SOURCE" ]] || fail "APK not found at $APK_SOURCE"
APK_OUTPUT="build/cotg/sms-telebot-arm64-release.apk"
mkdir -p "$(dirname "$APK_OUTPUT")"
cp "$APK_SOURCE" "$APK_OUTPUT"

DOWNLOADS_DIR="$HOME/storage/shared/Download"
if [[ -d "$DOWNLOADS_DIR" && -w "$DOWNLOADS_DIR" ]]; then
  cp "$APK_OUTPUT" "$DOWNLOADS_DIR/sms-telebot-arm64-release.apk"
  printf '\nAPK copied to: %s/sms-telebot-arm64-release.apk\n' "$DOWNLOADS_DIR"
fi
printf '\nBUILD SUCCESSFUL\nAPK: %s/%s\n' "$PROJECT_ROOT" "$APK_OUTPUT"
printf 'Signed with your configured key or the local test key.\n'
