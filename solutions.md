# Solutions — Rescu Flutter Assessment

## Environment note

Before starting on the tickets, the pinned toolchain (Flutter 3.27.0, Java 17)
failed to build on a clean setup with:

```
Could not resolve all files for configuration ':path_provider_android:androidJdkImage'.
Failed to transform core-for-system-modules.jar ...
```

**Root cause:** the project's AGP version (`8.1.0` in `android/settings.gradle`)
is below the `8.2.1` threshold where this `jlink`/JDK-image transform bug is
fixed (known AGP issue, unrelated to which JDK is installed — confirmed on
JDK 17.0.14 here). `android-35` as a newer platform surfaces it reliably.

**Fix (build tooling only, no app code changed):**
- `android/settings.gradle`: AGP `8.1.0` → `8.3.0`
- `android/gradle/wrapper/gradle-wrapper.properties`: Gradle `8.3` → `8.4`
  (required minimum for AGP 8.3.0)

This does not touch Flutter version, pub packages, or app behavior — it only
lets the pinned Flutter/Java 17 combo compile on a current macOS + Android SDK
setup. Noting it here for transparency per the "toolchain is pinned" rule.

Anyone building on a recent Android Studio / SDK setup will likely hit this
regardless of machine.
