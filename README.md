# 📚 SmartDoc

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com/)
[![Gemini API](https://img.shields.io/badge/Google_Gemini-4285F4?style=for-the-badge&logo=google&logoColor=white)](https://aistudio.google.com/)

**SmartDoc** is an AI-powered document learning and management application designed to elevate your reading and research experience. 
Organize your PDFs into custom categories, securely store your reading progress, and leverage the power of Google's Gemini AI to instantly summarize documents and ask questions about your content.

---

## ✨ Features

* 🤖 **Ask AI & Summarize**: Instantly summarize large PDFs and interact with your documents using the integrated Google Gemini AI.
* 📁 **Smart Organization**: Automatically scan your device for documents, or manually organize them into custom and default categories.
* 📖 **Advanced PDF Viewer**: Read your documents seamlessly with a robust PDF viewer powered by Syncfusion.
* 🔊 **Text-to-Speech (TTS)**: Listen to your documents on the go with built-in TTS capabilities.
* 🔐 **Secure Authentication**: Cloud-synced user profiles using Firebase Authentication.
* 🌗 **Dynamic Theming**: Beautifully crafted Light and Dark modes.
* ☁️ **Cloud Sync**: Firebase Firestore integration for seamless cross-device category and progress syncing.

## 🛠️ Technology Stack

* **Framework**: [Flutter](https://flutter.dev/)
* **Language**: Dart
* **Backend**: Firebase (Auth, Firestore, Storage)
* **AI Engine**: Google Gemini API (`generativelanguage.googleapis.com`)
* **Local Database**: SQLite (`sqflite`) for lightning-fast on-device document indexing.
* **Key Packages**: `syncfusion_flutter_pdfviewer`, `flutter_dotenv`, `http`, `flutter_tts`

## 🚀 Getting Started

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

### Prerequisites

* Flutter SDK (>=3.4.0)
* Android Studio / Xcode
* Firebase Project Setup
* Gemini API Key

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Nitin-kanojiya26/SmartDoc.git
   cd SmartDoc
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Environment Setup**
   You need a Google Gemini API Key to use the AI features.
   * Go to [Google AI Studio](https://aistudio.google.com/) and grab an API key.
   * Create a file named `.env` in the root of the project.
   * Add your API key to the `.env` file:
     ```env
     GEMINI_API_KEY=your_actual_api_key_here
     ```

4. **Run the App**
   ```bash
   flutter run
   ```

---

## 🔒 Security

* **API Keys**: API keys are securely managed via the `flutter_dotenv` package. **Never commit your `.env` file to version control.** It is already included in the `.gitignore`.
* **Firebase**: Firebase configurations are securely loaded on initialization.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! 
Feel free to check [issues page](https://github.com/Nitin-kanojiya26/SmartDoc/issues).

## 📝 License

This project is open-source and available to use for educational and personal purposes.
