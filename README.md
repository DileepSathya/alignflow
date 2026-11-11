# AlignFlow

Flutter web and Android client with a FastAPI backend and a local PostgreSQL database. The original v3 demo remains in `demo_versions/v3`.

## One-time setup

1. Start PostgreSQL, create the `alignflow` database, and run `database/setup.sql` once. See [database/README.md](database/README.md).
2. Configure the PostgreSQL connection in `backend/.env` (use `backend/.env.example` as a guide).
3. Install Flutter and the Android SDK. Run `flutter doctor` to check the setup. If Flutter cannot find the SDK, point it to the SDK **root**, for example `flutter config --android-sdk 'D:\adroid_studio_sdk'`.
4. Use `backend/.venv312` for Python. The older `backend/.venv` is not the intended environment for this project.

The Flutter project already contains `web/` and `android/`; do not run `flutter create` for normal builds.

## Start the backend and web app

Double-click `run_application.bat` in the project root. It opens separate backend and Flutter web terminals. Keep both open while using the app. The web app opens in Chrome at <http://localhost:8080>; the API health check is <http://127.0.0.1:8000/health>. A `404` at the API root (`/`) is expected.

To start them manually, use two PowerShell windows:

```powershell
cd D:\Aligner_company\backend
.\.venv312\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```powershell
cd D:\Aligner_company\flutter_app
flutter pub get
flutter run -d chrome --web-port 8080
```

`0.0.0.0` lets devices on the local network reach the API. It is a listen address, not an address to enter in the app. To stop the app, close the two terminals or press Ctrl+C in each.

## Run on an Android phone over Wi-Fi

1. Start the backend on the PC using the batch file or the manual command above. The Flutter web terminal is not needed for the installed APK.
2. Put the phone and PC on the same reachable Wi-Fi network. Find the PC's Wi-Fi **IPv4 Address** with `ipconfig` in PowerShell. Allow inbound TCP port `8000` through Windows Firewall for the local/private network.
3. On the phone's login page, enter the PC address as `192.168.1.25:8000` (replace the example IP with your PC's address). The app saves this server address and checks `/health` before login. The phone connects to FastAPI; it does not connect directly to PostgreSQL.

For a USB debug run, enable USB debugging on the phone, approve the PC, and use:

```powershell
cd D:\Aligner_company\flutter_app
flutter devices
flutter run -d <device-id>
```

If you want the USB phone to reach the backend through `localhost:8000`, run `D:\adroid_studio_sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000` first. This forwarding works only while the phone is connected by USB; for a standalone APK, use the PC's Wi-Fi IP on the login page.

## Build and install an updated APK

After changing Flutter code, build a new APK from the Flutter project root:

```powershell
cd D:\Aligner_company\flutter_app
flutter build apk --release
```

Run `flutter pub get` first if you changed dependencies in `flutter_app/pubspec.yaml`. The build writes `flutter_app/build/app/outputs/flutter-apk/app-release.apk`. For successive distributed versions, increase the `version:` build number in `flutter_app/pubspec.yaml` (for example, `0.1.0+2`).

With the phone connected and listed by `adb devices`, update its installed app without clearing saved data:

```powershell
D:\adroid_studio_sdk\platform-tools\adb.exe install -r D:\Aligner_company\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

The Android SDK needs NDK `28.2.13676358`. It is installed in the current local SDK. `android/gradle.properties` disables Kotlin incremental compilation because this project's dependency cache is on `C:` and the project is on `D:`. The current release APK uses the template's debug signing key and is intended for local testing, not Play Store distribution.

## Accounts and current scope

The database setup seeds `admin` / `admin`. Change this password before sharing the app. This prototype stores passwords as plain text and uses HTTP on the local network; it is not ready for production credentials. The admin can create Marketing, Clinical CAD, Lab/Manufacturing, and QC users. Their team workspaces are planned for a later phase.


