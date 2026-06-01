# ap_python_launcher_app

Flutter web UI for the AP Python Launcher.

## Getting Started

Install the pinned Flutter SDK via [FVM](https://fvm.app/) (see [`.fvmrc`](.fvmrc:1)), then fetch dependencies:

```bash
fvm flutter pub get
```

Set up the pre-commit hook:

```bash
dart run tool/setup_git_hooks.dart
```

## Run

```bash
fvm flutter run -d chrome
```

## Test

```bash
fvm flutter test
```

## Build (web)

```bash
fvm flutter build web
```
