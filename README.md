# WhatsApp Auto Responder

A minimalist, high-performance WhatsApp auto-responder bot powered by the Groq Llama 3.1 AI model, accompanied by a Flutter control dashboard app.

## Project Structure

* **`/` (Root):** Node.js backend using `@whiskeysockets/baileys` to interface with WhatsApp Web, and Express to serve control APIs.
* **`/whatsapp_controller`:** Flutter application that interfaces with the Node.js control APIs to toggle status, update prompts, and manage whitelists.

---

## 1. Node.js Auto Responder Backend Setup

### Prerequisites
* Node.js (v18+)
* npm

### Installation
1. Install dependencies from the root directory:
   ```bash
   npm install
   ```
2. Create a `.env` file in the root directory:
   ```env
   GROQ_API_KEY=your_groq_api_key_here
   ```
3. Start the application:
   ```bash
   node index.js
   ```
4. Authenticate by scanning the QR code that prints in the terminal using your WhatsApp mobile app.

---

## 2. Flutter Dashboard Controller Setup

### Prerequisites
* Flutter SDK (3.x+)
* Dart SDK

### Installation
1. Navigate to the `whatsapp_controller` directory:
   ```bash
   cd whatsapp_controller
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. If running on a physical mobile device or emulator, verify the server IP address is configured correctly in `lib/api_service.dart`:
   ```dart
   final String baseUrl = "http://<YOUR_LOCAL_IP>:3000";
   ```
4. Start the application:
   ```bash
   flutter run
   ```

---

## Features

* **AI Replies:** Powered by `llama-3.1-8b-instant` through Groq Cloud.
* **Whitelisting:** Bot only responds to WhatsApp contacts/groups explicitly added to the whitelist.
* **Stealth Simulation:** Simulates human composing delay behavior before dispatching messages.
* **Dynamic Directives:** Update the system prompt instructions on the fly via the Flutter dashboard.
