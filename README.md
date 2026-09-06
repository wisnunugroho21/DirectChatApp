# TMS Connect — Flutter migration

The converted application is entirely in this `New` directory. `Legacy` is unchanged.

- `flutter_app/`: Flutter UI and client services, with Android, iOS, web and Windows runners.
- `backend/`: ASP.NET Core 10 REST API, SignalR hub, MongoDB persistence and notification delivery. There are no Razor pages, WebViews, or server-rendered frontend assets.
- `Configure-WebPush.ps1`: generates the public Firebase configuration used by the browser service worker.

## Run locally

Install Flutter (validated with 3.41.6 / Dart 3.11.4), .NET 10 SDK and MongoDB. Keep the committed Flutter `pubspec.lock`; Firebase and secure-storage dependencies are pinned for compatibility with this Flutter SDK.

From `New/backend`:

```powershell
dotnet restore
dotnet run --urls http://localhost:5000
```

The default database is `ChatApp_2`, matching Legacy. For a fresh database, set `$env:MongoDbSettings__DatabaseName = 'TmsConnect'` before starting the backend. MongoDB must be running on port 27017.

In another terminal, from `New/flutter_app`:

```powershell
flutter pub get
flutter run -d chrome --web-port=5173 --dart-define=API_URL=http://localhost:5000
```

The API allows the web origin `http://localhost:5173`. Add other exact frontend origins to `Cors:Origins` when changing ports or deploying.

Other targets:

```powershell
# Windows (Visual Studio C++ desktop tools required)
flutter run -d windows --dart-define=API_URL=http://localhost:5000

# Android emulator: 10.0.2.2 reaches the host computer
flutter run -d <android-device-id> --dart-define=API_URL=http://10.0.2.2:5000

# Web release
flutter build web --dart-define=API_URL=https://api.example.com
```

For a physical device, use a reachable backend hostname/IP instead of localhost. Use a trusted HTTPS endpoint for release builds and iOS. Android permits local HTTP only in the debug manifest. Android minimum SDK is 24; iOS minimum is 15. Build iOS on macOS using Xcode.

## Converted features

| Legacy feature | Flutter implementation |
| --- | --- |
| Login and registration | Validated Flutter forms, JSON API, username/email login, profile fields |
| Session | Bearer token stored with flutter_secure_storage; sign in again after the 12-hour session expires |
| Chat list and contacts | Search, All/Unread filters, unread badges, direct conversations |
| Messages | SignalR delivery, paginated history, presence, live read receipts, reconnect and refresh |
| Attachments | Native file picker, authenticated downloads, safe image previews, 25 MB limit |
| Voice notes | Microphone permission, recording, cancel/send, authenticated audio playback |
| Voice/video calls | WebRTC offer/answer/ICE, incoming accept/decline, mute, camera toggle, mobile speaker control, timeout |
| Call history | Incoming/outgoing, audio/video, status, time and duration |
| Notifications | Optional Firebase registration, token refresh, foreground-device binding, notification tap recovery |
| Leave chat | Remove a conversation from the current user's list |
| Layout | Two-pane desktop/web layout and single-pane mobile navigation |

The legacy group-creation controls had no corresponding group API. This migration implements the working direct-chat functionality; it does not invent group messaging.

## Existing data and passwords

The MongoDB collections and DTO IDs remain compatible. Copy the legacy attachment directory to the new backend's configured `FileStorage:RootPath` if reusing its database; attachment metadata contains relative paths.

The actual Legacy attachment service stores files on disk, despite its old S3 configuration. This backend preserves the working disk-storage implementation and removes the unused S3 package.

New registrations use ASP.NET Identity password hashing. Existing plaintext passwords are rejected by default. To migrate an existing database after taking a backup, temporarily enable:

```powershell
$env:Auth__AllowLegacyPlaintextPasswords = 'true'
dotnet run --urls http://localhost:5000
```

Each successful legacy login replaces that user's plaintext password with a hash. Disable this setting once migration is complete. The original Legacy login code cannot authenticate an account after its password has been migrated; use a separate database copy if both applications need to remain usable.

Login returns ASP.NET's protected opaque bearer token, not a JWT. API calls use `Authorization: Bearer <token>`; browser SignalR WebSockets can pass `access_token`. Logout clears the client token and unregisters enabled push for that device. Tokens are not individually revoked server-side before expiry.

## Backend configuration

Use environment variables or `dotnet user-secrets` from `backend/`:

- `MongoDbSettings__ConnectionString`, `MongoDbSettings__DatabaseName`
- `FileStorage__RootPath` (default `storage/attachments`), `FileStorage__MaxFileSizeMb`
- `Cors__Origins__0`
- `Firebase__CredentialsPath` or `Firebase__CredentialsJson`
- `WebRtc__IceServers__1__Urls`, `WebRtc__IceServers__1__Username`, `WebRtc__IceServers__1__Credential`

Only STUN is preconfigured. Supply valid TURN credentials for calls across restrictive networks. The old TURN credentials and Firebase service-account configuration were deliberately not copied.

Serve the API behind HTTPS with WebSocket proxy support, persist ASP.NET Data Protection keys across restarts, and persist/back up the attachment directory and MongoDB. The inherited presence tracker is in-memory and assumes a single backend instance. Configure a shared presence strategy and SignalR backplane before scaling out.

## Firebase setup

Messaging and calls work without Firebase. Select **Enable notifications** in the app menu after configuring Firebase. `--dart-define=ENABLE_PUSH=true` enables initialization after sign-in automatically.

1. Backend: supply Firebase Admin service-account credentials using secrets/environment variables.
2. Android: register the final application ID in Firebase and place its `google-services.json` in `flutter_app/android/app/`. The Gradle Google Services plugin is applied when this file exists.
3. iOS: add `GoogleService-Info.plist` to the Runner target in Xcode, enable Push Notifications and Background Modes/Remote notifications, and upload an APNs authentication key in Firebase.
4. Web: fill the public `Firebase:Web` fields in backend settings, including `VapidKey`. Run `./Configure-WebPush.ps1` from `New`, then rebuild Flutter web. The generated JS contains only public web configuration, never an Admin credential.

Firebase's setup requirements are documented in [receiving messages in Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages). Web push requires HTTPS or localhost and a browser with notification support. Windows push is not implemented by Firebase Messaging; Windows receives messages and calls while connected through SignalR.

Incoming background calls use an OS notification that opens the Flutter call screen. This is not an OS CallKit/full-screen call integration. Notification delivery, especially to terminated apps, remains subject to platform restrictions. The app checks current server-side ringing state when reopened so expired calls cannot be accepted from stale notification data.

## API contract

- `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`
- `GET /api/users`
- `GET /api/conversations`, `POST /api/conversations/direct/{username}`
- `GET /api/conversations/{id}/messages?limit=50&before=<UTC timestamp>`
- `POST /api/conversations/{id}/read`, `DELETE /api/conversations/{id}`
- `POST /api/attachments/conversations/{id}` (multipart field `file`), `GET /api/attachments/{id}`
- `GET /api/calls`, `GET /api/calls/ringing`, `POST /api/calls/{id}/decline`
- `GET /api/push/config`, `POST /api/push/devices`, `DELETE /api/push/devices`
- `GET /api/webrtc/config`, `GET /health`
- SignalR at `/chatHub`: `SendMessage`, `MarkRead`, `BindDevice`, `UnbindDevice`, `CallUser(username, Audio|Video)`, `AcceptCall`, `RejectCall`, `EndCall`, `SendOffer`, `SendAnswer`, `SendIceCandidate`.

All chat APIs require authentication. Attachment access and conversation history verify membership. The decline endpoint requires the authenticated recipient; FCM tokens are not login credentials.

## Verification

```powershell
# From New/backend
dotnet build

# From New/flutter_app
flutter analyze
flutter test
flutter build web
```

For the opt-in live integration test, start the backend with an isolated validation database:

```powershell
# New/backend
$env:MongoDbSettings__DatabaseName = 'TmsFlutterMigrationValidation'
dotnet run --urls http://localhost:5057

# New/flutter_app, another terminal
flutter test test/backend_integration_test.dart --dart-define=RUN_BACKEND_TESTS=true --dart-define=API_URL=http://localhost:5057
```

The live test creates three synthetic accounts and checks registration/login, SignalR delivery, message history, unauthorized history/attachment access, read receipts, upload/download, video call signaling/history and leaving a conversation. It retains synthetic records in the validation database and small test attachments; it does not touch `ChatApp_2`.

Passed during conversion: .NET build, Flutter analyzer, four Flutter unit/widget tests, the live MongoDB/API/SignalR integration test, Flutter web release build, and Android debug APK build. The web login screen was also visually checked in a browser. The Android APK is at `flutter_app/build/app/outputs/flutter-apk/app-debug.apk` and targets the emulator backend address `http://10.0.2.2:5000`. Real camera/microphone media, TURN traversal, Firebase delivery and iOS/Windows native packaging require configured target devices and were not end-to-end verified.



