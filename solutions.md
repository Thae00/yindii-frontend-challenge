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

---

## Part A — Bug tickets

### RES-101 · Search shows results for the wrong query

- **Root cause:** `SearchDealsController.onQueryChanged` fired a new
  `dealRepo.search(query)` call on every keystroke with no debounce and no
  guard on response order. `FakeApiService.searchDeals` deliberately gives
  **shorter queries higher latency** than longer ones
  (`broadness = max(0, 1200 - query.length * 280)`), so when typing fast
  (e.g. "sushi" letter by letter), the request for an early short prefix
  (e.g. "s") reliably *resolves after* the request for the final, longer
  query. `results.assignAll(found)` had no way to know a response was stale,
  so the late-arriving "s" results silently overwrote the correct "sushi"
  results already on screen — no crash, no error, just wrong data.

- **Fix:** Added a 300ms debounce (in `search_deals_controller.dart`) to cut
  down redundant calls, plus a monotonically increasing `_requestId` bumped
  on every new search. Each in-flight request captures the id it was issued
  with; when it resolves, it only applies `results.assignAll(found)` (or
  logs the error) if its id still matches the latest `_requestId` — otherwise
  it's discarded as stale. This guarantees only the most recently *issued*
  query's response can ever update the UI, regardless of arrival order.

- **Why this fix (and what alternative was rejected):** Considered
  cancelling the in-flight HTTP call directly (e.g. a `dio` `CancelToken`)
  instead of a sequence guard. Rejected because `FakeApiService` uses a
  plain `Future.delayed` internally and PROBLEM.md explicitly forbids
  modifying `fake_api_service.dart` — a cancel-token approach would need
  changes on the "backend" side to actually abort the delay. The sequence
  guard fixes the race entirely from the caller side, with no backend
  changes, and is the standard pattern for this kind of stale-response race.
  Debounce alone was also considered as a full fix and rejected: it reduces
  how often stale responses can occur but doesn't eliminate the race (two
  distinct debounced queries in a row can still race under variable latency),
  so it's kept only as a performance nicety, not the correctness fix.

- **Edge cases considered / not handled:** Clearing the search box mid-flight
  now correctly clears `results` and marks a stale in-flight response as
  discarded when it later resolves. Rapid clear → retype → clear cycles are
  covered by the same `_requestId` guard. Not handled: a dedicated "request
  timeout" UI state if the fake API's simulated latency were ever extended
  far beyond current bounds — out of scope since the ticket is specifically
  about correctness of displayed results, not latency UX.
