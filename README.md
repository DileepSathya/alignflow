# V-Clear Aligners

Flutter web and Android client with a FastAPI backend and a local PostgreSQL database. The original v3 demo remains in `demo_versions/v3`.

## One-time setup

1. Start PostgreSQL, create the `alignflow` database, and run `database/setup.sql` once. See [database/README.md](database/README.md).
2. Configure the PostgreSQL connection in `backend/.env` (use `backend/.env.example` as a guide).
3. Install Flutter and the Android SDK. Run `flutter doctor` to check the setup. If Flutter cannot find the SDK, point it to the SDK **root**, for example `flutter config --android-sdk 'D:\adroid_studio_sdk'`.
4. Use `backend/.venv312` for Python. The older `backend/.venv` is not the intended environment for this project.

The Flutter project already contains `web/` and `android/`; do not run `flutter create` for normal builds.

## Reset all application data

Stop the backend before resetting. From PowerShell, run the script with the backend's Python environment:

```powershell
cd D:\Aligner_company\backend
.\.venv312\Scripts\python.exe reset_data.py --confirm RESET-ALIGNFLOW-DATA
```

This permanently clears users, sessions, clinics, clinicians, patients, and patient-to-order links in the configured PostgreSQL database. It also clears orders, the order counter, and legacy GridFS files in the configured MongoDB database, then deletes uploaded files under the configured `DATA_DIR/orders` directory. Database tables and other collections remain. The script recreates the `admin` account with password `admin`, so change that password after signing in. It reads `DATABASE_URL`, `MONGODB_URL`, `MONGODB_DATABASE`, and `DATA_DIR` from `backend/.env`.

Back up both databases and uploaded files before running it if you need any of the data. The reset spans separate storage systems, so an interruption can leave a partial reset. If that happens, stop the backend and rerun the same command before creating new orders.

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

On the web, workspace sections and order details have their own URLs (for example, `/#/admin/users` and `/#/admin/orders/order/ORDER-ID`). Browser Back and Forward navigate between them, and a copied URL opens the same view after login. Flutter's hash URL format lets these links refresh on a static host without a server rewrite rule.

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

Build from the repository root. The script regenerates the browser and launcher icons from the Base64 logo in `flutter_app/lib/branding.dart`. Use `-Target web` for a web release.

```powershell
cd D:\Aligner_company
.\scripts\build_branded_app.ps1 -Target apk
```

Run `flutter pub get` first if you changed dependencies in `flutter_app/pubspec.yaml`. The build writes `flutter_app/build/app/outputs/flutter-apk/app-release.apk`. For successive distributed versions, increase the `version:` build number in `flutter_app/pubspec.yaml` (for example, `0.1.0+2`).

With the phone connected and listed by `adb devices`, update its installed app without clearing saved data:

```powershell
D:\adroid_studio_sdk\platform-tools\adb.exe install -r D:\Aligner_company\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

The Android SDK needs NDK `28.2.13676358`. It is installed in the current local SDK. `android/gradle.properties` disables Kotlin incremental compilation because this project's dependency cache is on `C:` and the project is on `D:`. The current release APK uses the template's debug signing key and is intended for local testing, not Play Store distribution.

## Accounts and current scope

The database setup seeds `admin` / `admin`. Change this password before sharing the app. This prototype stores passwords as plain text and uses HTTP on the local network; it is not ready for production credentials. The admin can create Marketing, Clinical CAD, Lab/Manufacturing, and QC users. Their team workspaces are planned for a later phase.


# Team configuration

Edit `backend/config.yaml` to change the team labels and their order in the admin user dropdown. Keep the IDs `marketing`, `scanner`, `planning`, and `production`: the API permissions and order workflow use these IDs. Restart the backend after editing the file. The built-in `admin` role is not a team option. Planning contains both Orders and QC; QC opens on the approval-pending queue.

On backend startup, existing users with the former `cad`, `lab`, and `qc` roles are migrated to `planning`, `production`, and `planning`, respectively. Existing QC issue records remain readable and resolvable.


## Scanner review and checklist configuration

The workflow is Marketing → Scanner review → Planning → Production/QC. Create
Scanner users from the Admin user screen. Scanner can upload missing files,
select existing order files, verify checklist items, request missing items from
Marketing, and approve a complete order for Planning. Marketing can upload and
update checklist evidence but cannot verify or approve it. Requests appear in the
order details; they do not send an email or an external notification.

Edit `backend/config.yaml` (`scanner_checklist`) to add/remove items or change
labels, mandatory flags, minimum file counts, allowed extensions, and text
support. IDs must be unique and stable. Restart the API after changes. Each order
stores a snapshot: later configuration edits apply only to new orders. The
initial checklist contains upper/lower STL, bite registration, five intraoral
photos, three extraoral photos, OPG X-ray, and treatment requirements.

Uploads alone do not complete review. Scanner must verify each mandatory item;
Admin may authorize individual exceptions with recorded reasons. Final approval
still belongs to Scanner. Replacing selected evidence clears verification and
any exception. Earlier checklist uploads remain stored, and the approved
checklist is locked. Planning API access and claiming are blocked until approval.

On API startup, the PostgreSQL role constraint is updated to include `scanner`.
On the first order-store access, existing unassigned `submitted` orders without
scanner approval move to Scanner review with the current checklist. Orders
already in Planning or later stages retain their existing workflow.



Swagger UI visual api calls http://127.0.0.1:8000/docs

## Docker installation

Build the release on a machine with Flutter and Docker running Linux containers.
From the repository root in PowerShell:

```powershell
.\scripts\build_docker.ps1
```

On a machine with the image loaded, start the full application:

create container

```powershell
docker run -d --name vclear --restart unless-stopped --stop-timeout 60 -p 127.0.0.1:8080:8000 -v vclear-data:/storage vclear-aligners:0.1.0
```
----------or----------
docker run -d --name vclear -p 8080:8000 vclear-aligners:0.1.0

stop container

doker stop <contrainerid>

start container
doker start <contrainerid>

Open <http://localhost:8080>. The initial login is `admin` / `admin`.
The web client and API share this port. For access from a phone on a trusted LAN,
publish the PC's LAN IP instead of `127.0.0.1` and enter `PC-IP:8080` in the Android app.
Change the seeded password before sharing access. The example serves HTTP.

PostgreSQL uses a private Unix socket. MongoDB listens on container loopback and
uses a password generated inside the volume. First startup creates the PostgreSQL
schema. MongoDB creates the order collection and indexes on first use. The
`vclear-data` volume holds both databases, their initialization state, and uploads.
Use `docker logs vclear` for startup diagnostics and `docker start vclear` to
restart a stopped installation. Use one running container per data volume.

**Share the image offline.** Run `docker save -o vclear-aligners-0.1.0.tar vclear-aligners:0.1.0`
and give the tar file to the recipient. They run `docker load -i vclear-aligners-0.1.0.tar`
and the startup command above. They need only Docker and a browser.
Each new volume starts a separate installation.

**Back up before upgrading.** From a writable directory, stop the application
and archive the complete volume so both databases and files are consistent:

```powershell
docker stop -t 60 vclear
docker run --rm --entrypoint tar -v vclear-data:/storage:ro -v "${PWD}:/backup" vclear-aligners:0.1.0 -czf /backup/vclear-data-backup.tar.gz -C /storage .
docker start vclear
```

Choose a new backup filename for each backup. The archive contains application
data and credentials. To restore, extract it into a new empty volume using
the same image version, then start a container with that volume:

```powershell
docker volume create vclear-restored
docker run --rm --entrypoint tar -v vclear-restored:/storage -v "${PWD}:/backup:ro" vclear-aligners:0.1.0 -xzf /backup/vclear-data-backup.tar.gz -C /storage
```

For a compatible application upgrade, stop the old container, remove the stopped
container with `docker rm vclear`, and repeat the startup command with the new
image tag and the original volume name. Database major-version changes require
their own migration. Existing Windows installation data requires a separate import.




how to publish in docker

docker login
docker tag vclear-aligners:0.1.0 <userid>/vclear-aligners:0.1.0
docker push <userid>/vclear-aligners:0.1.0

---- To pull the docker and run---


docker pull ds2205/vclear-aligners:0.1.0
docker run -d -p 8080:8000 ds2205/vclear-aligners:0.1.0