# ap_python_launcher_app

Flutter web UI for the AP Python Launcher.

## Getting Started

Fetch dependencies:

```bash
flutter pub get
```

Set up the pre-commit hook:

```bash
dart run tool/setup_git_hooks.dart
```

## Run

```bash
flutter run -d web-server --web-port 14500
```

## Test

```bash
flutter test
```

## Build (web)

```bash
flutter build web
```


## Optional login (OIDC)

This UI supports optional login:

- Public (no login required): viewing available apps and reconnecting to locally persisted running jobs.
- Protected (login required): launching a new job and ending a job.

The frontend determines login state via [`GET /auth/status`](../ap-python-launcher-service/src/auth/mod.rs:1) (no redirects).

### Backend endpoints

Public:

- `GET /apps`
- `GET /launch/{launchId}`
- `POST /launch/status`
- `GET /auth/status`

Protected (requires `ap_session` cookie):

- `POST /launch`
- `DELETE /launch/{launchId}`

### Cookies + CORS

The backend uses a session cookie (`ap_session`). For cross-origin usage (frontend and backend on different origins), the backend must be configured for credentialed requests:

- Cookie must be `SameSite=None; Secure`.
- CORS must allow credentials and explicitly allow the frontend origin.

### API base URL

The frontend uses [`Config.apiBaseUrl`](lib/config.dart:1) / `API_BASE_URL` to locate the backend.

- When `API_BASE_URL` is empty, the app assumes the backend is served from the same origin.
- When `API_BASE_URL` is set to a different origin, the backend must support cookies + CORS as described above.
