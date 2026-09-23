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

### RES-102 · Crash after leaving My orders

- **Root cause:** `_PickupCountdownState` (in `pickup_countdown.dart`) started
  a `Timer.periodic(const Duration(seconds: 1), ...)` in `initState()` but
  never stored a reference to it and never overrode `dispose()`. When the
  user navigated back from **My orders**, the widget (and its `State`) was
  disposed, but the timer kept firing every second regardless. On its next
  tick, the callback called `setState(() {})` on a `State` that no longer
  had a mounted widget, throwing `setState() called after dispose()` —
  within a couple of seconds, matching the reported symptom. This only
  showed up for orders with an upcoming pickup because `PickupCountdown` is
  only rendered when `showCountdown: true` (active orders); past orders show
  a plain status `Text` instead and never start a timer.

- **Fix:** Store the timer in a `Timer? _timer` field, and override
  `dispose()` to call `_timer?.cancel()` before `super.dispose()`. Also
  added a `mounted` check inside the timer callback as defense-in-depth, in
  case a tick and disposal ever race on the same frame.

- **Why this fix (and what alternative was rejected):** This is the standard
  fix for any periodic `Timer` owned by a `StatefulWidget` — cancel it in
  `dispose()`, symmetric with where it's created in `initState()`. Considered
  moving the countdown state into the `OrdersController` (a `GetxController`)
  instead, driven by `onClose()`, but rejected it: a `GetxController` here is
  scoped to the whole orders screen/list, not to one tile, so a single timer
  per controller updating every order row would still need per-row diffing
  logic to avoid rebuilding the entire list every second — more complex for
  no real benefit when each tile already owns its own lightweight timer.

- **Edge cases considered / not handled:** Rapid navigate-away-and-back is
  covered since each new `PickupCountdown` instance gets its own fresh timer
  independent of any prior instance's disposal. Not handled: no attempt to
  pause/resume the timer on app lifecycle changes (e.g. backgrounding) since
  a `setState` call while the app is backgrounded doesn't crash and the
  displayed countdown will simply catch up to the correct value on the next
  visible tick — not worth the added complexity for this ticket's scope.

### RES-103 · Requests pile up the longer you browse

- **Root cause:** `DealDetailsController.onInit()` calls
  `ever(cartService.itemCount, (_) => _recheckAvailability())` every time a
  deal details page is opened, registering a new GetX `Worker` listener on
  `cartService.itemCount`. `CartService` is a `GetxService` that "lives for
  the whole session" (permanent singleton), so its `itemCount` observable
  persists for the app's lifetime. `DealDetailsController` never overrides
  `onClose()`, so the `ever()` worker is never cancelled when the controller
  is disposed — it keeps listening indefinitely. Each deal page visited adds
  one more permanent listener on `itemCount`. Any cart change (e.g. tapping
  "Add to bag") fires `itemCount`'s listeners, so every deal ever viewed in
  the session triggers its own `dealRepo.fetchById(deal.id)` call
  (`GET /deals/:id`) — one request per previously-viewed deal, all at once,
  growing with every additional deal opened.

- **Fix:** Capture the `Worker` returned by `ever()` in a field
  (`Worker? _cartWorker`) and cancel it in an added `onClose()` override
  (`_cartWorker?.dispose()`). This ties the listener's lifetime to the
  controller's lifetime, so leaving a deal page removes its listener from
  `cartService.itemCount` and no leaked listeners accumulate across the
  session.

- **Why this fix (and what alternative was rejected):** Considered removing
  the `ever()` re-check entirely and instead re-fetching availability only
  when the user re-opens or resumes the deal page (e.g. in `didPopNext` or
  on cart-screen return). Rejected because it would delay the "never show
  stale availability" guarantee the original code was written for — the
  worker itself is the correct pattern, it just needs a matching
  `onClose()`. This fix keeps the intended behavior (live re-check on any
  cart change) while fixing the actual bug, which is a missing disposal, not
  a wrong approach.

- **Edge cases considered / not handled:** Repeated open/close of the same
  deal page no longer accumulates duplicate listeners for that deal, since
  each controller instance's own worker is disposed with it. Not handled:
  no de-duplication if two *simultaneously open* deal pages exist for the
  same deal id (e.g. via two navigation stacks) — out of scope since the
  app's navigation doesn't currently allow that, and it's an existing
  constraint unrelated to this leak.
