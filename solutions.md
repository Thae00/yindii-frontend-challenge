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

### RES-104 · Duplicate deals in the home feed

- **Root cause:** `refreshDeals()` and `loadMore()` in `HomeController` both
  mutate shared state (`deals`, `_page`, `_totalPages`) with no coordination
  between them. `_isFetchingMore` only guards `loadMore()` against itself —
  it has no effect on `refreshDeals()`. If the user scrolls to the bottom
  (triggering `loadMore()`, which increments `_page` and awaits page N) and
  then quickly pulls to refresh before that finishes, `refreshDeals()` resets
  `_page` to 1 and replaces the list (`deals.assignAll(...)`). When the
  earlier, now-stale `loadMore()` request resolves afterward, it blindly
  appends its (now out-of-sync) page onto the just-refreshed list
  (`deals.addAll(...)`), producing duplicated cards or more items than the
  catalog contains — intermittently, since it depends on the two requests'
  latencies overlapping.

- **Fix:** Added an `int _epoch` counter. `refreshDeals()` increments it and
  captures its own `myEpoch`; if `_epoch` has changed by the time its
  response arrives (a newer refresh started), it discards its own result
  instead of applying it. `loadMore()` captures the epoch value in effect
  when it starts; if the epoch has changed by the time its response arrives
  (a refresh happened while it was in flight), it discards the page instead
  of appending it. This makes only the most recently *started* refresh's
  result ever land, and prevents any in-flight `loadMore()` page from being
  appended on top of a list a newer refresh has since replaced — regardless
  of which response arrives first.

- **Why this fix (and what alternative was rejected):** Considered simply
  disabling pull-to-refresh while `_isFetchingMore` is true (block the
  gesture instead of guarding the race). Rejected because it changes user-
  facing behavior for a case the ticket doesn't ask to prevent — the user
  should be able to refresh at any time; the fix should make that safe, not
  restrict it. The epoch-guard approach fixes the race without taking away
  the ability to refresh while a page is loading.

- **Edge cases considered / not handled:** Two or more rapid consecutive
  pull-to-refresh calls are handled correctly — only the last one's result
  is ever applied.

### RES-105 · Home feed is janky and memory keeps climbing

- **Root cause(s):** Three contributing causes, all in `home_screen.dart` /
  `the_network_image.dart`:
  1. The entire `Scaffold` (AppBar, list, FAB) was wrapped in a single
     top-level `Obx` that only needed to react to `scrollOffset`, which
     updates on every scroll pixel. This forced a full widget-tree rebuild
     on every scroll tick — matching DevTools' "entire feed rebuilding
     continuously during scroll".
  2. The deal list used `ListView(children: [...])` (eager, non-lazy)
     instead of a lazy builder, so every card ever loaded via pagination
     stayed built and in memory, growing unbounded as the feed paginated.
  3. `TheNetworkImage` passed no `memCacheWidth`/`memCacheHeight` to
     `CachedNetworkImage`, so images were decoded at their full source
     resolution regardless of the ~160dp display size, ballooning the
     image cache — matching DevTools' "image cache ballooning" symptom.

- **Fix:**
  1. Replaced the single top-level `Obx` with several narrowly-scoped ones
     (AppBar shadow line, FAB visibility, flash-deals section, filter chip),
     so only the widget that actually depends on a changed value rebuilds.
  2. Replaced the `ListView` with `CustomScrollView` + `SliverList.builder`,
     so only visible (+ nearby) cards are built and disposed as the user
     scrolls.
  3. Added `memCacheWidth`/`memCacheHeight` to `CachedNetworkImage`,
     computed from the widget's actual display size scaled by device pixel
     ratio, with the screen width as a fallback cap when width is unbounded
     (e.g. a full-width card using `double.infinity`).

- **Before/after DevTools evidence:** Tested in debug mode (Rebuild Stats is
  unavailable in profile mode) for rebuild counts, and profile mode for
  frame timing and memory, scrolling from page 2 through page 5 (~20 second
  window, confirmed via matching console log timestamps and the Memory
  chart's x-axis on both runs) on an Android emulator (Pixel 8 API,
  arm64):
  - **`DealCard` instance count (strongest evidence)**: after scrolling
    through the full catalog (page 1→7, 122 deals — the fake API's entire
    dataset) and back up to the top, a Memory tab heap snapshot showed
    **2,460 live `DealCard` instances before the fix vs. a single-digit
    count after** (3-5 across repeated snapshots — filtered by class name in
    Profile Memory). The exact single-digit number varies slightly between
    snapshots depending on scroll position and viewport fit, which is
    expected for a lazily-built list; what matters is the two-orders-of-
    magnitude gap versus before. 2,460 ÷ 122 deals ≈ 20x — consistent
    with the top-level `Obx` re-running its builder (and thus reconstructing
    every `DealCard` in the list) on every scroll-pixel update, while the
    fixed version's single-digit count matches what's actually visible on
    screen at once via `SliverList.builder`'s lazy building. This is a
    two-orders-
    of-magnitude difference, well outside any run-to-run noise, and directly
    confirms the Obx-scoping fix (cause #1) eliminated the excess rebuilds.
  - **UI-thread (rebuild) time improved clearly**: 0.7ms → 0.3ms per frame
    in the Performance tab's Frame Analysis tooltip — direct evidence the
    Obx-scoping fix reduced the work being done on the UI thread.
  - **Raster time, FPS average, and total heap size were statistically
    indistinguishable** between before and after at this test scale
    (Raster ~58ms and 13 FPS average in both runs; All Classes total size
    11.3 MB before vs 11.1 MB after; DealModel instance count/size
    identical at 34 / 2.7 KB in both, as expected since page count was the
    same). A ~20 second / 4-page scroll session is likely too short to
    reproduce the ticket's described symptom ("memory grows the further
    you scroll... until the OS kills the app") in either the before or
    after case — the memory chart is flat in both runs at this scale.
  - The persistently high Raster time in both runs (~58-60ms, far above
    the ~16ms budget for 60fps) suggests a GPU/raster-thread bottleneck
    (card shadows, `ClipRRect` antialiasing, shimmer gradients, or emulator
    software rendering) that is outside this fix's scope, since the fix
    specifically targets UI-thread rebuild cost, not raster/paint cost.
  - **Follow-up on a real device** (Pixel, arm64, scrolled to page 7):
    both before and after runs held a steady **58 FPS average**, with only
    occasional jank bars (a handful out of dozens of frames, e.g. one
    tooltip showed UI 2.5ms / Raster 16.8ms — just over the 16ms budget)
    rather than the near-constant jank seen on the emulator's
    12-13 FPS. This points to the emulator's software
    rendering as the likely cause of the raster-time bottleneck seen
    above, rather than an app-level issue within this fix's scope. Memory
    (Dart Heap 12.8 MB → 12.1 MB, External bytes 20.8 KB → 214.7 KB) was
    inconclusive in either direction on the real device too — both figures
    stayed in the KB range for external (image) bytes across ~30 loaded
    deals, which is far smaller than expected if full-resolution images
    were being decoded, suggesting this test dataset's source images are
    low-resolution enough that the `memCacheWidth`/`memCacheHeight` fix
    has little source resolution to cap in the first place. This test
    was not repeated enough times to rule out run-to-run GC noise as the
    explanation for the External-bytes increase.

- **Why this fix (and what alternative was rejected):** Considered leaving
  the `ListView` as-is and only fixing the `Obx` scoping, since the
  Rebuild Stats evidence for cause #1 is the strongest signal obtained.
  Rejected that narrower scope because causes #2 and #3 are directly
  supported by code inspection (eager list construction, missing memory
  cache bounds) even though a longer scroll session would be needed to
  show their effect conclusively in DevTools — the ticket explicitly
  expects multiple contributing causes to be found and fixed, not just the
  one with the clearest before/after numbers.

- **Edge cases considered / not handled:** `TheNetworkImage`'s cache-size
  calculation guards against `width`/`height` being `double.infinity` (used
  by full-width cards), falling back to screen width instead of crashing on
  `.round()` of an infinite value. Not handled/validated: a longer
  (multi-minute, 20+ page) scroll session to conclusively confirm the
  memory-growth fix and isolate the raster-time bottleneck — only tested up
  to page 5 due to time constraints; this is flagged as follow-up work
  rather than claimed as verified.

### RES-106 · Wrong pickup times; "Pickup today" filter misses deals

- **Root cause:** `PickupWindowModel` parses `start`/`end` from the API's
  ISO-8601 UTC strings via `DateTime.parse()`, which correctly produces UTC
  `DateTime` objects — but two getters then used those values without ever
  converting to local time:
  1. `label` formatted `start`/`end` directly with `DateFormat('HH:mm')`,
     which reads the `DateTime`'s raw hour/minute fields. For a UTC
     `DateTime`, those are the UTC hour/minute, not local — so a bakery
     open 06:00–09:30 local (Bangkok, UTC+7) displayed as "23:00 – 02:30"
     (the UTC equivalent), matching the reported symptom exactly.
  2. `isToday` compared `start.day` (the UTC day-of-month) directly against
     `DateTime.now().day` (the local device's day-of-month), with no month/
     year check either. Near local midnight, the UTC day and local day can
     differ by one — a deal whose local pickup is "today" can have a UTC
     `start.day` that reads as tomorrow or yesterday, causing it to be
     wrongly excluded from the "Pickup today" filter.
  `isOpenNow` was unaffected, since `DateTime.isAfter`/`isBefore` compare
  absolute instants regardless of which timezone the values are printed in.

- **Fix:** Call `.toLocal()` on `start`/`end` before reading any field from
  them. `label` now formats the local-converted times. `isToday` now
  converts `start` to local first, then compares year, month, and day all
  three against `DateTime.now()` (not just day-of-month), fixing both the
  midnight-boundary issue and the latent month/year gap in the original
  comparison.

- **Why this fix (and what alternative was rejected):** Considered having
  the fake API send local-time strings instead of UTC to sidestep the
  conversion entirely. Rejected because `fake_api_service.dart` and
  `assets/data/*` are explicitly off-limits per PROBLEM.md, and because
  "the backend sends UTC, the client displays local" is the correct,
  general pattern for a real API anyway — the bug was in the client's
  handling, not the API's data format (PROBLEM.md's own note that "the
  backend team insists their data is correct" supports this).

- **Edge cases considered / not handled:** The `isToday` fix's three-field
  comparison also fixes the latent bug where a deal on the same day-of-month
  in a different month or year would have incorrectly matched under the
  original single-field comparison, even though that wasn't the reported
  symptom. Not handled: no explicit test for a user changing their device's
  timezone while the app is running (e.g. mid-flight) — `DateTime.now()`
  and `.toLocal()` both read the device's current timezone setting live, so
  this should self-correct on the next rebuild, but it wasn't verified.

### RES-107 · Deep link opens to a crash

- **Root cause:** `DealDetailsController.onInit()` did
  `deal = Get.arguments as DealModel;`, assuming a full `DealModel` object is
  always passed as the route's `arguments`. That holds for in-app navigation
  (`deal_card.dart` and `flash_deals_section.dart` both call
  `Get.toNamed(..., arguments: deal)`), but a deep link
  (`rescu://open/deal?id=42&source=push`) only carries `id` as a query
  parameter — `_showDeepLinkDialog`'s `Get.toNamed(route)` call passes no
  `arguments` at all. So `Get.arguments` is `null` for a deep link open, and
  the cast throws `type 'Null' is not a subtype of type 'DealModel'` —
  matching the reported crash exactly. Opening from the home feed worked
  fine because that path always supplies the full object.

- **Fix:** `onInit` now checks whether `Get.arguments` is a `DealModel`; if
  so it's used directly (fast path, no fetch, same as before for in-app
  navigation). If not, it parses `Get.parameters['id']` and calls
  `dealRepo.fetchById(id)` to fetch the deal by id — the same pattern the
  fake API already supports and that `DealDetailsController` was already
  using for `_recheckAvailability()`. Since this fetch is async, `deal`
  became a nullable `Rxn<DealModel>` with `isLoading`/`loadFailed` flags, and
  `DealDetailsScreen`'s body/bottomSheet are now wrapped in `Obx` to show a
  loading spinner while fetching, an error view with a "Go back" action if
  the id is missing/invalid or the fetch fails, and the full deal page once
  loaded — satisfying the ticket's requirement that the link land on "a
  fully working deal page", not a fallback/error screen, for a valid id.

- **Why this fix (and what alternative was rejected):** Considered always
  ignoring `Get.arguments` and always fetching by id (simpler code, one
  path only). Rejected because that would add an unnecessary network
  round-trip and a loading flash for the common in-app-navigation case,
  where the full deal is already available locally — the dual-path
  approach keeps the fast path fast and only pays the fetch cost when the
  full object genuinely isn't available (deep link entry).

- **Edge cases considered / not handled:** An invalid or missing `id` query
  param (e.g. malformed deep link) shows the error view with a "Go back"
  button rather than crashing. While restructuring `onInit`'s worker setup
  for the async flow, also added the missing `onClose` override to dispose
  the `ever(cartService.itemCount, ...)` worker (the RES-103 leak) in this
  same file, since it was touched anyway — noted here since it's a second,
  related fix riding along in the same commit. Not handled: no retry
  button distinguishing "invalid id" from "network/fetch error" — both
  currently show the same generic error view and only offer "Go back",
  not a retry action.
