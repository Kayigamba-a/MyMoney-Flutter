$ErrorActionPreference = "Stop"
flutter create .
flutter pub get
flutter analyze
flutter test
Write-Host "Checks finished. Run: flutter run -d chrome"
