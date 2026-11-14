# WhatsApp Auto Responder

A WhatsApp text assistant with a Flutter control dashboard. Replies are limited to explicitly allowed chats. The dashboard controls activation, reply instructions, and the allowlist, and reports the actual WhatsApp connection and delivery counters.

## Start the server

Use Node.js 22 or later and npm. Run one server process per WhatsApp session, on a persistent local filesystem.

```sh
npm ci
cp .env.example .env
```

If `.env` already exists, update it instead of replacing it. Set `GROQ_API_KEY` to your Groq key and `CONTROL_API_KEY` to a private random token. Generate a token with:

```sh
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

```sh
npm start
```

Scan the terminal QR code from WhatsApp → Linked devices. The server reuses the private `auth_info/` session on future starts. Keep that directory and `.env` out of source control and restrict access to the server account.

The API listens on `127.0.0.1:3000` by default. To use a physical phone on a trusted local network, explicitly set `HOST=0.0.0.0`, allow the port through your firewall, and use your computer's LAN address in the dashboard. For release builds and remote access, put the server behind HTTPS; keep its unencrypted port private. CORS is disabled unless `CONTROL_ALLOWED_ORIGINS` contains a comma-separated list of allowed browser origins. Native Flutter clients do not need CORS.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `GROQ_API_KEY` | Required | Groq inference credential |
| `CONTROL_API_KEY` | Required | Shared dashboard authentication token |
| `GROQ_MODEL` | `openai/gpt-oss-20b` | Groq chat model |
| `HOST` | `127.0.0.1` | Bind address |
| `PORT` | `3000` | Control API port |
| `LOG_LEVEL` | `info` | Pino logging level |
| `CONTROL_ALLOWED_ORIGINS` | Empty | Optional browser CORS allowlist |

The previous default, `llama-3.1-8b-instant`, was [retired for free and developer accounts](https://console.groq.com/docs/deprecations). The new default uses Groq's recommended replacement. Model availability depends on your account; override it when necessary.

## Start the dashboard

Use Flutter 3.41 or later with Dart 3.11 or later:

```sh
cd whatsapp_controller
flutter pub get
flutter run
```

Open **Connection settings** and enter the server address and `CONTROL_API_KEY`. These entries last for the current app session. On an Android emulator, the host computer is normally `http://10.0.2.2:3000`; the backend must bind to an address reachable from the emulator. A physical phone needs the computer's LAN address, not `localhost`.

Alternatively, configure a trusted personal build:

```sh
flutter run \
  --dart-define=CONTROL_API_URL=https://your-server.example \
  --dart-define=CONTROL_API_KEY=your-private-token
```

A key supplied through `--dart-define` is embedded in the application; do not distribute builds containing your private token. The Android build limits Gradle to a 1.5 GB heap and two workers, and compiles Kotlin in the same process to stay usable on smaller machines. Android debug builds permit local HTTP for development. Release builds require HTTPS. The main Android manifest includes internet permission. The Android project still uses the template application ID and debug signing for local release builds; configure your own application ID and production signing key before distributing it.

1. Confirm **WhatsApp connected** in the dashboard.
2. Add the full chat ID: contacts use `15551234567@s.whatsapp.net`, linked IDs use `123456789012345@lid`, and groups use a numeric ID ending in `@g.us` (some older group IDs include a hyphen). Use the chat's actual ID; do not guess a group ID from a phone number. Direct chats also match a verified alternate phone/linked ID supplied by Baileys, when available. Allowing a group member never allows the whole group.
3. Save the reply instructions.
4. Enable replies. An empty allowlist means nobody gets automated replies.

The dashboard refreshes every 20 seconds and supports manual refresh. Unsaved prompt edits survive refreshes. Writes lock controls until the result is known. If a request times out, refresh to check the saved state before trying again. Rotate the previously hardcoded control token if it was used anywhere; source code history and old builds can retain it.

## Reliability behavior

- Only live `notify` batches are eligible. Every message in a batch is considered. Own messages, history batches, non-text content, empty text, oversized text, and messages older than two minutes are ignored.
- Duplicate message IDs are suppressed for ten minutes within a running process, using a bounded cache. Group participant IDs are included in the key.
- Messages run sequentially per chat, with up to three chats processing concurrently and at most 100 queued or running replies. Excess work is dropped and counted as skipped. Work older than two minutes expires.
- Pending replies are checked again after inference and typing delay. Pausing, changing settings, removing access, replacing a connection, or shutting down cancels pending sends. A send already handed to WhatsApp cannot be recalled.
- AI requests have a 30-second timeout, one SDK retry, and a 2048-token output cap. Empty or failed completions send nothing. Presence failures do not prevent a valid reply. Uncertain WhatsApp sends are not automatically retried, to avoid duplicate deliveries.
- Configuration changes are validated, serialized, written to a private temporary file, flushed, and atomically renamed before success is returned. Failed saves keep the previous in-memory settings. Invalid existing configuration fails startup with a repair instruction; it is never silently replaced. Missing configuration starts paused with no allowed chats.
- Connections retry with exponential backoff up to 30 seconds. Logout, replacement by another session, invalid credentials, and forbidden sessions require operator attention instead of an endless reconnect loop. Termination signals cancel reconnects and pending sends.

`config.json` stores your settings and survives restarts. Back it up along with your session, and do not edit it while the server is running. It was tracked in the original repository: `.gitignore` does not untrack existing files, so avoid committing private prompts or chat IDs. Counters and duplicate suppression are in memory and reset on restart. Conversation history is not stored or sent to Groq; each reply uses the current instructions and incoming text only.

## Control API

All routes require `x-api-key: <CONTROL_API_KEY>`. Responses are JSON and must not be cached. Mutations return success only after persistence.

| Method | Route | JSON body |
| --- | --- | --- |
| GET | `/status` | None; returns settings and `runtime` |
| POST | `/toggle` | `{"isActive": true}` (explicit, idempotent state) |
| POST | `/prompt` | `{"newPrompt": "Be concise and helpful."}` |
| POST | `/chats/add` | `{"jid": "15551234567@s.whatsapp.net"}` |
| POST | `/chats/remove` | `{"jid": "15551234567@s.whatsapp.net"}` |

`runtime` includes `connection`, `reconnectAttempts`, `received`, `sent`, `failed`, `skipped`, and `pending`. Errors use `{"error":"..."}` with 400 for validation, 401 for authentication, 413 for size limits, and 500 for persistence errors. Prompt length is limited to 8000 characters and the allowlist to 1000 IDs. Clients using the old bodyless `/toggle` route must update to the explicit-state API.

## Verification

```sh
npm run check
npm test
npm audit --omit=dev
cd whatsapp_controller
flutter analyze
flutter test
```

Backend tests use temporary settings, fake WhatsApp sockets and inference, and a real loopback HTTP API. Dashboard tests cover authenticated requests, timeouts, error recovery, control locking, safe disposal, and preserving draft instructions. They do not send real WhatsApp messages or spend inference credits. GitHub Actions runs both suites.

## Operational limits

Baileys is an unofficial WhatsApp Web client; WhatsApp changes, account restrictions, session invalidation, network outages, and Groq rate limits can interrupt service. This project cannot promise uninterrupted operation, exactly-once delivery across crashes, or correct AI responses in every case. Use an account and contacts appropriate for automated replies, and validate generated answers for your intended use. Incoming text and your reply instructions are sent to Groq.

For a logged-out or invalid session, stop the server, back up `auth_info/`, move the old session aside, restart, and scan a new QR code. If a connection was replaced, stop the competing process before restarting. Protect the QR code and session files as account credentials.
