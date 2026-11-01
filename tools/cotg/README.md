# Building SMS Telebot with Code On The Go

SMS Telebot is a **Flutter application with Kotlin Android components**. Code On The Go can edit the project, but plain Gradle alone cannot compile the Dart sources: Flutter and Dart are required.

## ARM64 phone workflow (Termux)

1. Install Termux, then install basic tools:

   ```sh
   pkg update && pkg upgrade
   pkg install git python openjdk-21
   ```

2. Install Flutter and the Android SDK using the community [Flutter for Termux](https://github.com/retired64/flutter-for-termux) project. This is a third-party ARM64 port, not an official Flutter host installation; review its current requirements and limitations.

3. Check the toolchain and accept Android SDK licenses:

   ```sh
   flutter doctor -v
   flutter doctor --android-licenses
   ```

4. Clone this repository or open your existing checkout in Code On The Go:

   ```sh
   git clone https://github.com/qmnb12/sms-telebot.git
   cd sms-telebot
   ```

5. Use Code On The Go to edit Dart files under `lib/` and Kotlin files under `android/app/src/main/kotlin/`. For Android/Gradle-specific editing, open the `android/` subfolder as an Android project. Use Termux for the Flutter build; a plain `assembleDebug` task is not sufficient.

6. Build an installable ARM64 release APK:

   ```sh
   bash tools/cotg/build.sh
   ```

The script detects Flutter and Android SDK paths, writes ignored `android/local.properties`, applies the Termux toolchain helper if installed, resolves packages and builds the APK. If no `android/key.properties` exists, it creates a local test signing key that is never committed.

## Output

```text
build/cotg/sms-telebot-arm64-release.apk
```

If Termux shared storage is enabled and Downloads is writable, it also copies the APK to `~/storage/shared/Download/`.

## Optional SDK path overrides

```sh
export FLUTTER_ROOT="$PREFIX/opt/flutter"
export ANDROID_SDK_ROOT="$PREFIX/opt/android-sdk"
bash tools/cotg/build.sh
```

## Signing safety

- `cotg-local-test.jks`, `android/key.properties`, and `android/local.properties` are local-only and ignored by Git.
- The generated key is for local testing only, not Play Store publishing.
- Use your own protected keystore and signing config for production releases.

The repository remains pinned to Flutter 3.32.8 in `.fvmrc`; the pubspec SDK range accepts Flutter 3.32.8 through Flutter 3.x. JDK 17 or 21 is suitable for the Android build. This phone script targets ARM64 only.
