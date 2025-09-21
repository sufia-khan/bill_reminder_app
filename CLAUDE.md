# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter mobile application project called "projeckt_k" with Firebase integration. The project supports multiple platforms including Android, iOS, Web, Windows, macOS, and Linux.

## Development Commands

### Core Flutter Commands
- **Run app**: `flutter run`
- **Build for platform**: `flutter build <platform>` (apk, appbundle, ios, web, windows, macos, linux)
- **Run tests**: `flutter test`
- **Static analysis**: `flutter analyze`
- **Get dependencies**: `flutter pub get`
- **Hot reload**: `flutter hot reload` (during development)

### Platform-Specific Commands
- **Android**: `flutter build apk` or `flutter build appbundle`
- **iOS**: `flutter build ios`
- **Web**: `flutter build web`

## Architecture

### Project Structure
- `lib/` - Main source code directory
- `test/` - Test files
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` - Platform-specific configurations
- `firebase.json` - Firebase configuration for multi-platform deployment

### Firebase Integration
- **Project ID**: sub-manager-new
- **Services**: Firebase Core, Auth, Firestore
- **Configuration**: Multi-platform Firebase setup with separate app IDs per platform
- **Config file**: `lib/firebase_options.dart` contains Firebase initialization options

### Current Implementation
- Basic counter app template with Material Design theme
- Main app entry point: `lib/main.dart`
- Firebase integration configured but not yet implemented in app logic
- Standard Flutter testing setup with `flutter_test`

## Development Guidelines

### Testing
- Tests are located in `test/` directory
- Uses `flutter_test` package for widget testing
- Run tests with `flutter test`

### Code Quality
- Linting configured with `flutter_lints` package
- Analysis options in `analysis_options.yaml`
- Run static analysis with `flutter analyze`

### Dependencies
- Flutter SDK 3.9.2+
- Firebase packages: firebase_core, firebase_auth, cloud_firestore
- Material Design icons enabled
- Dependencies managed in `pubspec.yaml`

## Platform Support

The project is configured to build for:
- Android (APK and App Bundle)
- iOS
- Web
- Windows
- macOS
- Linux

Each platform has its own configuration directory with native build settings.