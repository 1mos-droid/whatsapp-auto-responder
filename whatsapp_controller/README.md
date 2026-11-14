# Responder Control

Flutter dashboard for the WhatsApp Auto Responder backend. See the [project setup and API documentation](../README.md) for installation, connection settings, supported chat IDs, and operational limits.

```sh
flutter pub get
flutter run
```

Use **Connection settings** to enter the backend URL and control API key for this session. Personal builds can also use `--dart-define=CONTROL_API_URL=...` and `--dart-define=CONTROL_API_KEY=...`. Never distribute a build containing your private key. Android development builds support local HTTP; release builds require HTTPS.

```sh
flutter analyze
flutter test
```
