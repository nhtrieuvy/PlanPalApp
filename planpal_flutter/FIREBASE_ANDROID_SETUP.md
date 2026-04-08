# Firebase Android Setup

This project currently uses the Android package:

- `com.example.planpal_flutter`

Current debug signing fingerprints on this machine:

- `SHA-1`: `F5:FF:78:F3:5D:B9:7D:A2:C4:05:F6:BD:A8:05:D7:A2:02:F6:7F:FC`
- `SHA-256`: `4B:28:93:E5:31:EA:E5:FA:F3:63:FB:85:1D:06:61:F5:8D:04:22:03:54:60:DC:1E:EA:53:D0:3C:06:2A:2A:A7`

## What must match

The following values must all refer to the same Firebase Android app:

- Android `applicationId`: `com.example.planpal_flutter`
- Android `namespace`: `com.example.planpal_flutter`
- Firebase Android app package name: `com.example.planpal_flutter`
- `android/app/google-services.json`
- `lib/firebase_options.dart`

## Firebase Console steps

1. Open Firebase Console and select the project used by PlanPal Android.
2. Open `Project settings` -> `Your apps` -> Android app.
3. Verify the Android package name is exactly `com.example.planpal_flutter`.
4. Add both fingerprints above to the Android app.
5. Download a fresh `google-services.json`.
6. Replace `android/app/google-services.json` with the downloaded file.
7. Run `flutterfire configure` or regenerate `lib/firebase_options.dart` so it matches the same Firebase project.

## Google Cloud checks

1. Open the linked Google Cloud project for the same Firebase project.
2. Verify `Firebase Cloud Messaging API` is enabled.
3. Verify `Firebase Installations API` is enabled.
4. Check API key restrictions for the Firebase Web API key from `google-services.json`.
5. Do not reuse the Firebase Web API key as a Google Maps Android API key.

## Google Maps key

This repo now expects a dedicated Google Maps Android key to be provided separately.

Set one of the following before building Android:

- `android/local.properties`
- Gradle property `GOOGLE_MAPS_ANDROID_API_KEY`
- Environment variable `GOOGLE_MAPS_ANDROID_API_KEY`

Example in `android/local.properties`:

```properties
sdk.dir=C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
GOOGLE_MAPS_ANDROID_API_KEY=your-android-maps-key
```

## Local debug run

Use local backend and keep Firebase Messaging enabled:

```powershell
flutter run -d emulator-5554 --dart-define=PLANPAL_BASE_URL=http://10.0.2.2:8000 --dart-define=PLANPAL_ENABLE_PUSH=true
```

If you need to debug the app without FCM while the Firebase project is being fixed:

```powershell
flutter run -d emulator-5554 --dart-define=PLANPAL_BASE_URL=http://10.0.2.2:8000 --dart-define=PLANPAL_ENABLE_PUSH=false
```
