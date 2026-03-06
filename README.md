# PlayerV - Modern Music Player

A beautiful, cross-platform music player with a clean interface and powerful features.

## 🎵 What is PlayerV?

PlayerV is a modern music player built with Flutter that works seamlessly on Android, iOS, Windows, macOS, and Linux. It automatically scans your system's music folder, organizes your library, and provides an intuitive interface to enjoy your music collection.

## ✨ Key Features

### 🎨 Beautiful Design
- Modern Material 3 interface with smooth animations
- Dark/Light theme support
- Responsive layout for all screen sizes
- Stunning playlist collages and cover art display

### 📱 Easy to Use
- **Auto-scan**: Finds all music files on your device automatically
- **Smart Search**: Real-time search for songs, artists, and albums
- **Quick Access**: Favorites and playlists for your most-loved tracks
- **Smooth Playback**: High-quality audio with gapless playback

### 🎼 Library Management
- **System Playlists**: Smart playlists (Trending, Recent, Favorites)
- **Custom Playlists**: Create and manage your own playlists
- **Grid View**: Customizable card sizes and grid layouts
- **Cover Art**: Automatic extraction of album artwork

### 🎯 Player Features
- Mini-player for quick controls
- Full-screen player with lyrics support
- Play/Pause, Next/Previous, and shuffle controls
- Progress bar and time display
- Volume control

## 🚀 Get Started

### Prerequisites
- Flutter 3.4.0+ installed on your system
- For mobile: Android/iOS device or emulator
- For desktop: Windows 10+, macOS 10.15+, or Linux (Ubuntu 18.04+)

### Installation
1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/PlayerV.git
   cd PlayerV
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # For Android
   flutter run

   # For Windows
   flutter run -d windows

   # For macOS
   flutter run -d macos

   # For Linux
   flutter run -d linux
   ```

## 🛠️ Build for Production

```bash
# Android APK
flutter build apk --release

# Windows EXE
flutter build windows --release

# macOS App
flutter build macos --release

# Linux AppImage
flutter build linux --release
```

## 📱 How to Use

1. **First Launch**: Click "Scan Music" to detect your music library
2. **Browse**: Navigate through Home, Favorites, and Playlists
3. **Play**: Click any song card to start playback
4. **Search**: Use the search bar to find specific tracks
5. **Create Playlists**: Click "New List" to create custom playlists

## 🎨 Customization

- **Theme**: Toggle between dark and light modes
- **Grid Settings**: Adjust card size and grid count
- **Search**: Real-time filtering of your library

## 📄 Technical Details (Appendix)

### 🛠️ Technologies
- **Flutter 3.4.0+** - UI framework
- **Dart** - Programming language
- **audioplayers** - Audio playback
- **sqflite** - Local database
- **provider** - State management
- **path_provider** - File system access

### 📁 Project Structure
```
lib/
├── main.dart              # App entry point
├── models/               # Data models
├── pages/                # Screen widgets
├── services/             # Business logic
└── widgets/              # Reusable components
```

### 📱 Platform Support
- **Android**: API 21+
- **iOS**: 13.0+
- **Windows**: 10+
- **macOS**: 10.15+
- **Linux**: Ubuntu 18.04+

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

## 📞 Support

For issues or feature requests, please create a GitHub issue.

---

Enjoy your music with PlayerV! 🎶
