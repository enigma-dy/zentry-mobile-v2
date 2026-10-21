# Google sign-in deployment setup

The application code sends a Google ID token to `POST /api/v1/auth/google`.
The backend validates its signature, issuer, expiry, and audience before issuing
Zentry access and refresh tokens.

## Google Cloud configuration

1. Configure the OAuth consent screen in Google Cloud Console.
2. Create an Android OAuth client for package `com.zentry.predict` using the
   SHA-1 and SHA-256 fingerprints for every debug and release signing key.
3. Create a Web application OAuth client. This is the server client ID used as
   the ID-token audience.
4. For iOS, create an iOS OAuth client and complete the URL-scheme setup from
   the `google_sign_in_ios` package documentation.

## Flutter `.env`

```env
GOOGLE_CLIENT_ID=<ios-client-id-when-needed>
GOOGLE_SERVER_CLIENT_ID=<web-server-client-id>.apps.googleusercontent.com
```

Android normally derives its Android client from the package name and signing
certificate. `GOOGLE_SERVER_CLIENT_ID` must be the Web client ID.

## Backend `.env`

```env
GOOGLE_CLIENT_IDS=<web-server-client-id>.apps.googleusercontent.com
```

Multiple accepted audiences can be comma-separated. Restart the backend after
changing this value and rebuild the Flutter app after changing its `.env`.

## Release requirement

The Android release build must use a private production signing key. Register
that key's SHA-1 and SHA-256 fingerprints with the Android OAuth client before
publishing. The current project still uses the debug signing configuration for
release builds and must be changed before production distribution.
