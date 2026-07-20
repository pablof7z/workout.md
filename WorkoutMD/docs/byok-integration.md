# BYOK provider connection

Workout.md connects coach providers through BYOK's public-client OAuth flow. The app requests only
the selected provider scope (`key:openrouter` or `key:ollama`), uses an S256 PKCE challenge and a
fresh random `state`, and exchanges the returned authorization code at `https://byok.f7z.io/api/token`.

The BYOK client values are:

- Client ID: `com.workoutmd.prototype`
- App name: `Workout.md`
- Redirect URI: `workoutmd://byok`
- Registered URL scheme: `workoutmd`

The redirect URI must match these values exactly if BYOK begins enforcing a client registry. The
callback is accepted only when its scheme is `workoutmd`, its host is `byok`, and its `state` matches
the pending authorization.

BYOK intentionally returns the selected raw provider key. Workout.md writes that key and non-secret
connection metadata directly to the device-only Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
It must never be placed in `UserDefaults`, app logs, analytics, crash breadcrumbs, or committed files.
Users can reconnect or remove each provider in Settings → AI → Providers.
