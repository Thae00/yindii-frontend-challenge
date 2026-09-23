# Rescu

A mini surplus-food marketplace used as our Flutter hiring assessment.

**Start with [`PROBLEM.md`](PROBLEM.md)** — it contains the tasks, rules, and
submission instructions.

## Requirements

| Tool | Version |
|---|---|
| Flutter | **3.27.0** (exactly — a `.fvmrc` is included if you use [fvm](https://fvm.app)) |
| Java | **17** (required for the Android build) |

The app targets Android and iOS. No API keys, accounts, or backend needed —
the app runs against a bundled simulated backend.

## Setup

```bash
# with fvm (recommended)
fvm install 3.27.0
fvm use 3.27.0
fvm flutter pub get
fvm flutter run

# or with a system Flutter 3.27.0
flutter pub get
flutter run
```

Verify your toolchain with `flutter --version` and `java -version` before
reporting build issues.

## Project structure

```
lib/
  main.dart            app entry + dependency injection
  app_config.dart      theme
  model/               hand-written JSON models
  service/             app-wide GetX services (fake API, cart, analytics)
  repository/          data access on top of the fake API
  routes/              GetX named routes
  binding/             per-route dependency bindings
  middleware/          route middlewares
  feature/<name>/      screen + controller + widgets per feature
  feature/shared_widget/  shared UI components
assets/data/           seed data for the simulated backend
```

## Useful while working

- **Console logs**: every simulated API call and analytics event is logged —
  keep the console open.
- **Analytics debug screen**: Home → overflow menu (⋮) → *Analytics debug*.
- **Deep links**: Home → ⋮ → *Simulate deep link…*, or on Android:

  ```bash
  adb shell am start -a android.intent.action.VIEW \
    -d "rescu://open/deal?id=42&source=push" dev.rescu.rescu
  ```
