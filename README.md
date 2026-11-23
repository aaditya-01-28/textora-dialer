# Textora Dialer — Sales Telephony Companion

<div align="center">
  <img src="https://crm.textorasms.com/logo.png" alt="Textora Technologies" width="220" />
  <p><strong>Official Android Sales Telephony & CRM Companion for Textora Technologies Pvt Ltd</strong></p>
  <p><em>Seamless SIM Dialing, Post-Call Disposition, Real-Time CRM Sync & WhatsApp Automation</em></p>
</div>

---

## 📌 Overview

**Textora Dialer** is a dedicated Flutter Android companion app designed for enterprise tele-sales representatives at **Textora Technologies**. It bridges native SIM smartphone telephony directly with the **Textora Engage Cloud CRM**, allowing representatives to conduct cold calling, capture call durations, record outcomes, schedule product demos, and dispatch customized WhatsApp introductions with zero telephony costs.

---

## ⚡ Key Features

### 1. 📞 1-Tap SIM Calling & Duration Tracking
- Dial leads directly via the smartphone's native SIM without telecom PBX overhead.
- Background lifecycle observer that detects call completion and tracks talk-time duration from the Android `CallLog` provider.

### 2. 🔒 Mandatory, Non-Dismissible Post-Call Disposition
- When returning to the app after a call, the **Call Completed** dialog appears automatically.
- Protected by `PopScope` and modal barriers (`isDismissible: false`, `enableDrag: false`) — sales reps cannot dismiss the dialog without logging an outcome.
- Requires discussion notes/remarks before saving to ensure data integrity in CRM reporting.

### 3. 📅 Callback & Demo Scheduling
- **Callback**: Embedded date and time picker (`dd-mm-yyyy hh:mm AM/PM`) with automatic reminder generation in the CRM agenda.
- **Demo Scheduled**: Select date/time, attach Decision Maker name, and include Google Meet link.
- **Already Using Filter**: Distinguish between *Our Service* vs. *Competitor / Other Company Service*.

### 4. 💬 Dynamic Personalized WhatsApp Pitch
- One-click launch of WhatsApp Web or mobile app with official Textora CPaaS intro messages.
- **Auto-Personalized**: Injects logged-in rep's name, email, direct phone number, and prospective contact name dynamically.
- Outlines core services: *Business WhatsApp API*, *Virtual WhatsApp*, *RCS Messaging*, *Transactional SMS*, *Promotional SMS*, *Voice SMS*, and *Website Development*.

### 5. 🔄 Offline Queue & Automatic Sync
- Calls logged with low or no connectivity are safely queued in AES-256 encrypted local storage.
- Automatically flushes and syncs offline records to `https://crm.textorasms.com/api/calls` once internet connectivity is restored.

### 6. 🚀 Built-In In-App Update Engine
- Queries `/api/app/version` on launch to verify build number against the CRM server.
- Prompts reps with changelog release notes and enables 1-tap download and installation of new APK updates directly inside the app.

---

## 🛠️ Tech Stack & Dependencies

| Layer | Technology |
|---|---|
| **Framework** | Flutter 3.x / Dart (Null Safe) |
| **Storage** | `flutter_secure_storage` (AES-256 Encrypted via Android KeyStore) |
| **Networking** | `http` (Bearer Token Authentication & Silent Refresh) |
| **Telephony** | `call_log`, `url_launcher`, Android Platform Channels |
| **Updater** | `package_info_plus`, `open_filex`, `path_provider` |
| **Backend CRM** | Textora Engage Next.js REST API (`crm.textorasms.com`) |

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.19+ or higher)
- Android Studio / Android SDK (Platform 34 / Java 17)
- Physical Android phone with active SIM card (USB debugging enabled)

### Local Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/aaditya-01-28/textora-dialer.git
   cd textora-dialer
   ```

2. **Install Flutter packages:**
   ```bash
   flutter pub get
   ```

3. **Run on a connected Android device:**
   ```bash
   flutter run
   ```

4. **Build Production Release APK:**
   ```bash
   flutter build apk --release
   ```
   The generated APK will be located at:
   `build/app/outputs/flutter-apk/app-release.apk`

---

## 📱 Android Permissions

The app requires standard telephony companion permissions declared in `android/app/src/main/AndroidManifest.xml`:
* `READ_CALL_LOG` & `WRITE_CALL_LOG`: Track call duration and status for CRM logging.
* `CALL_PHONE`: Trigger native SIM phone calls.
* `REQUEST_INSTALL_PACKAGES`: Enable the in-app auto-update engine.
* `INTERNET` & `ACCESS_NETWORK_STATE`: Secure communication with Textora CRM.

---

## 📄 License & Ownership

Copyright © 2026 **Textora Technologies Pvt Ltd**. All Rights Reserved.  
Proprietary software developed for internal enterprise sales operations.
