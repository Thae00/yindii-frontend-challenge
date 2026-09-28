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

---

## Part B — Features

### F-1 · Live flash-sale countdowns

- **Approach:** Created a reusable `FlashCountdownBadge` (StatefulWidget)
  that owns a single `Timer.periodic(1s)`, cancelled in `dispose()` (the
  RES-102 lesson applied deliberately here), and renders `mm:ss` /
  `h:mm:ss`. It calls `onExpired` exactly once, deferred via
  `addPostFrameCallback`, when the countdown reaches zero. This one widget
  is reused in all three required places: the flash rail
  (`flash_deals_section.dart`), home feed cards (`deal_card.dart`, replacing
  the old static "FLASH SALE" badge), and the deal details screen. Each
  card/rail-item that shows a flash deal was converted to (or already
  extracted into) its own small `StatefulWidget` holding an `_expired`
  bool, so that on expiry the card greys out (`Opacity` + disabled `onTap`/
  `IgnorePointer`-equivalent), shows "Unavailable"/"Expired", and — if the
  deal was already in the cart — removes it via `CartService.remove()` and
  shows a snackbar ("Removed from bag — the flash sale ended"). The details
  screen's "Add to bag" button disables and relabels to "No longer
  available" the same way, via an `isFlashExpired` observable on
  `DealDetailsController`.

- **Performance notes (100+ visible countdowns, scoped rebuilds):** Verified
  with DevTools Rebuild Stats (debug mode) over a 10-second window with the
  home feed static (not scrolling): `FlashCountdownBadge` and its internal
  `Container`/`Text` were the only widgets rebuilding (Overall counts in
  the 16-80 range across the two flash-rail/feed instances present), while
  `DealCard`, `Card`, `ListView`/`SliverList`, and `Scaffold` showed zero
  rebuilds in the same window — confirming the per-second tick only
  rebuilds the badge itself, never the surrounding card or list. The FPS
  reading during that same capture (16 FPS) is not meaningful on its own,
  since the Rebuild Stats instrumentation itself adds overhead to frame
  timing (the same caveat noted for RES-105) — the rebuild-count table, not
  the FPS number, is the relevant evidence here.

- **Edge cases considered / not handled:** A deal whose `flashSaleEndsAt`
  is already in the past when the card first builds starts in the expired
  state immediately (no full countdown-then-expire flash), computed once in
  `initState`/the wrapper's field initializer rather than waiting for the
  first tick. Cart removal only fires if the specific expired deal is
  actually present in the cart, so unrelated cart items are never touched
  (confirmed manually: two ordinary items stayed in the bag after a third,
  flash-sale item expired and was removed). Not handled: cart contents are
  in-memory only (`CartService` "lives for the whole session," unrelated to
  this feature), so a hot **restart** (not reload) clears the whole cart —
  this is pre-existing app behavior, not something F-1 introduced or needs
  to fix, but worth noting since it can look like an expiry-removal bug
  during manual testing if a hot restart happens between adding an item and
  it expiring.

### F-2 · Impression tracking

- **Approach:** Two layers, because "has *this card* been visible long
  enough" is per-widget state, while "at most once per deal" and "batch the
  delivery" are session-wide.
  - `ImpressionDetector` (new widget, `shared_widget/impression_detector.dart`)
    wraps a card in `VisibilityDetector` (already in `pubspec.yaml`). When
    `visibleFraction >= 0.5` it starts a 1s `Timer` (only if one isn't
    already running); if the fraction drops below 0.5 the timer is
    cancelled, so the second has to be *continuous*. When the timer
    completes it calls the service once and sets a `_fired` flag so later
    visibility callbacks for that card instance are ignored.
  - `ImpressionTrackingService` (new permanent `GetxService`) keeps a
    `Set<int>` of deal ids already recorded (`Set.add` returning `false` is
    the whole dedupe, across every screen and source) and a pending batch.
    The batch is sent through `FakeApiService.sendAnalyticsBatch` when it
    reaches 10 events or 15s after the *first* unsent event, whichever
    comes first. The 15s `Timer` is only created when the batch goes from
    empty to non-empty, not re-armed on every add; re-arming would let a
    steady trickle of impressions postpone the flush forever.
  - `AnalyticsService.logEvent('deal_impression', {deal_id, source,
    position})` is still called immediately, one event at a time. The
    "don't send one by one" rule is about the `sendAnalyticsBatch` delivery;
    the debug screen is an in-memory view that should show events as they
    happen, so it is not delayed until a flush.
  - Wired into `DealCard` (home feed and search share it) and
    `_FlashRailCard`, with `source` = `home_feed` / `search` / `flash_rail`
    and `position` = list index.

- **Side effect to be aware of:** `DealCard.source` used to default to
  `'home'`. It is also the `source` query param passed to
  `Routes.dealRoute`, so it now defaults to `'home_feed'` to match the
  impression spec, which also changes the `source` on `deal_details_view`
  events from `home` to `home_feed`. That is visible in the F-3 logs
  (`deal_details_view {deal_id: 1, source: home_feed}`). Nothing else reads
  that value.

- **Why this fix (and what was rejected):**
  - Doing the visibility timing inside the singleton service (a
    `Map<int, Timer>` per deal id) was rejected: the same deal can be on
    screen in two lists at once, each with its own geometry and its own
    dwell clock, and the service only needs to know whether an impression
    already fired. Both widgets run their own timer; the first to finish
    wins and the second is a no-op at the `Set`.
  - Counting `VisibilityDetector` callbacks as "one second" was rejected:
    its callbacks are throttled (default 500ms) and best-effort, so their
    count is not wall-clock time. It is used only for the ≥50% signal; the
    one second comes from an explicit `Timer`.

- **Scrolling performance:** `ImpressionDetector` never calls `setState`; it
  only starts/cancels a `Timer`, so it does not rebuild the card it wraps.
  Once `_fired` is set, further callbacks return immediately. **No frame
  timing or DevTools numbers were captured for F-2**, so this is a design
  argument, not a measurement.

- **Edge cases:** A card that never reaches 50% never fires. A dip below 50%
  resets the dwell. The same deal in two lists is deduped by the `Set`. A
  failed `sendAnalyticsBatch` is logged and dropped (no retry/outbox): the
  fake backend has nothing to retry into, and the debug-screen record is
  independent of delivery. That would be the first thing to change against
  a real backend.

#### F-2 verification (Android device, console logs)

`sendAnalyticsBatch` logs `POST /analytics/batch` *after* its own simulated
150–500ms latency, so with a 15s window the log line should land at
`first event + 15s + 150…500ms`. Observed:

| Batch | First unsent event | Flush logged | Gap | Over deadline | Events |
|---|---|---|---|---|---|
| 1 | 22:02:47.362 | 22:03:02.651 | 15.289s | +289ms | 2 |
| 2 | 22:03:34.738 | 22:03:50.172 | 15.434s | +434ms | 2 |
| 3 | 22:13:49.403 | 22:14:04.576 | 15.173s | +173ms | 9 |
| 4 | 22:19:17.035 | 22:19:32.313 | 15.278s | +278ms | 6 |

All four overshoots are inside the 150–500ms latency band, so the timer
fires 15s after the *first* event of each batch. Batch 3 had 9 events (one
short of the count trigger), so it went out on the window, not the count.

- **Dedupe (same screen):** after `deal_id` 1–4 had fired, scrolling down
  past position ~19 and back up to the top produced no second impression
  for `deal_id` 1, 2, 3 (reported from watching the console; the pasted log
  excerpts contain each of these ids once).
- **Sources and properties:** `home_feed` (positions 0–19), `flash_rail`
  (`deal_id: 5`, position 1) and `search` (positions 2–15) all appeared
  with the expected `deal_id`/`source`/`position` shape.

**Not verified (do not read the above as covering these):**
- The 10-event count trigger: no batch of 10 was ever observed on device.
- Cross-screen dedupe (same deal id seen in two different lists): the
  home-feed and search runs I have logs for never overlapped on a deal id.
  It relies on the single session-wide `Set`, not on any test.
- The sub-threshold case (card visible < 1s → no event) was not captured
  in a log; it relies on the cancel-on-dip logic in `_onVisibilityChanged`.
- The `onClose()` best-effort flush of a partial batch.
- Scroll performance, as noted above.

### F-3 · Stock reservations with optimistic UI

- **Approach:** `CartService` now backs every bag line with a real
  reservation (`OrderRepo.reserve` / `releaseReservation`, which already
  wrapped `FakeApiService`), instead of being local-only state.
  - `add()`, `decrement()` and `remove()` change `items` / `itemCount`
    **synchronously first**, then reconcile with the backend without
    awaiting. Nothing in the UI waits on the network to show a line
    appearing, changing quantity or disappearing, and the existing call
    sites (`cartService.add(deal)` etc.) did not need to change.
  - `_reconcileLine()` is the only place that calls `reserveDeal`. It sets
    `CartItemModel.isReserving = true` (new field), requests a hold for the
    line's *current* quantity, and on success attaches the
    `ReservationModel`. On failure (409) it removes the whole line and shows
    a plain-language snackbar ("<name> just sold out — sorry! It has been
    removed from your bag") instead of the raw `ApiException` text.
  - While a line is `isReserving`, its +/− buttons are disabled and the
    Checkout button is disabled with a "Confirming stock for your bag…"
    note. Checkout would otherwise send `reservationId: null` for that line,
    and the fake backend only validates reservation ids it is given, so an
    unconfirmed line would be bought without ever holding stock. (I can't
    change the backend, so the guard is on the client.)
  - Race guard: a per-deal `_lineOpToken` counter is bumped on every
    add/quantity change/removal. Each reconcile remembers its token; if a
    newer operation has run by the time its response arrives, a late
    *success* is released straight away (so no orphaned 5-minute hold) and
    a late *failure* is ignored. Same idea as the `_epoch` guard from
    RES-104.
  - Reducing a quantity (not to zero) releases the old hold and reserves a
    new one for the new quantity, through the same path. The backend has
    only reserve/release, no partial adjust. Removing a line (or
    decrementing to zero) releases its hold.
  - Each line shows its remaining hold using `FlashCountdownBadge` from F-1,
    unchanged (it was already a generic `endsAt` countdown with `onExpired`).
    Bag rows are now keyed by deal id so a line's countdown stays attached
    to the right item when a line above it is removed.
  - Checkout: on `410` the controller calls
    `CartService.pruneExpiredReservations()` (re-checks each line's own
    `ReservationModel.isExpired`, since the response doesn't say which line)
    and shows one snackbar. A successful checkout calls
    `clearAfterCheckout()`, which deliberately does *not* release holds:
    they were just consumed by the order. The general `clear()` (unused
    today) does release, so a future "empty bag" button can't reuse the
    checkout path by mistake.
  - Interactions with earlier tickets: F-1's flash-expiry calls
    `CartService.remove()`, which now also releases the hold. RES-103's
    `ever(itemCount, …)` re-check fires on both the optimistic add and the
    rollback of a failed add, so a failed add causes two `GET /deals/:id`
    (visible in the log at 13:59:57). Bounded, and the worker is disposed
    with the controller, so this is not the RES-103 leak.

- **The underspecified part — a hold expires while the user is still in the
  app (or mid-checkout).** Decision: **auto-remove the line and tell the
  user** (`handleReservationExpired`, called from the line's countdown),
  the same behaviour F-1 already gives an expired flash sale (item dropped
  from the bag, snackbar explains). Reasons:
  - A line past its `expiresAt` no longer has stock behind it (checkout
    would answer `410`). Leaving it in the bag looking normal promises
    stock that isn't there.
  - It matches an existing pattern in this app, so a user who has seen a
    flash-sale item disappear with a notice already understands it.
  - Rejected: keep the line with a "renew" button. It adds a second
    interactive line state (held → expired → renewing → held) and re-opens
    the same stock race unless it is guarded as carefully as the first
    reservation. Reasonable follow-up if product wants it; not needed to
    ship this safely.
  - Rejected: do nothing until checkout. The ticket asks for a per-line
    countdown; a countdown that reaches 00:00 and changes nothing
    contradicts what the user is looking at.
  - Known costs of this choice: (1) if a countdown expiry and a checkout
    `410` coincide, the user sees two snackbars ("Hold expired", then
    "Some holds expired…"), which is a bit noisy. (2) The countdown only
    exists while the bag screen is mounted, so if a hold expires while the
    user is on another screen the line stays in `CartService.items` (and in
    the bag count) until the bag is next opened; the badge then sees an
    `endsAt` in the past and calls `onExpired` on the first frame. A
    session-level expiry timer in `CartService` would close that gap.
    (3) The badge ticks once a second, so for up to one second after real
    expiry the line can still be shown and tapped; that gap is the main
    case where `pruneExpiredReservations()` matters.

- **Why this design (and what was rejected):**
  - Reservation calls in `CartController` / `DealDetailsController` instead
    of `CartService` were rejected: `CartService` is the single source of
    truth, and both add paths (details "Add to bag", bag "+") need
    identical behaviour.
  - Making `add()` return a `Future` for callers to await was rejected: it
    breaks the "instant" feel at the call site and makes every caller
    responsible for the failure case. The rollback notice lives in one
    place.

- **Not handled / trade-offs:**
  - The release of the old hold and the reserve of the new one are issued
    together (not release-then-reserve), so they complete in either order
    (seen in the log). The fake backend never decrements on reserve, so this
    is harmless here; against a real backend with tight stock it could cause
    a spurious 409, and awaiting the release first would avoid that at the
    cost of latency.
  - The new-item branch of `add()` has no `quantityLeft` pre-check and the
    details screen doesn't disable "Add to bag" at 0 left, so a sold-out
    deal is added optimistically and then rolled back (observed: deal 6 at
    14:05:31 after its last unit had been bought). The 409 path handles it
    correctly, but a sold-out label would be nicer.
  - No automatic retry on 409 (the ticket says it fails intermittently);
    the user can tap "Add to bag" again. A failed `releaseReservation` is
    logged and ignored; the hold simply expires server-side after 5 minutes.

#### F-3 verification (Android device)

**Requirement status** (evidence is detailed below the table):

| Requirement | Status | Evidence |
|---|---|---|
| Add to bag reserves stock; UI updates optimistically | ✅ | console log + recording |
| Reservation fails (409) → line rolled back with a plain-language message | ✅ | console log + recording (random contention and real sold-out both seen) |
| Quantity ↑/↓ → old hold released, new one reserved | ✅ | console log |
| Removing a line → hold released | ✅ | console log |
| Each line shows its remaining hold time | ✅ | screenshot + recording |
| Hold expires while in the bag → line removed with a notice | ✅ | screenshot + recording |
| Checkout / +/− disabled while a line is still reserving | ✅ | recording (Add-to-bag path); "+/−" path reported by the author |
| Checkout success does not release the consumed holds | ✅ | console log + recording |
| Checkout `410` handled gracefully | ✅ | console log + recording; snackbar text, `pruneExpiredReservations()` and the race guard were tested separately by the author (see below) |

Evidence is the console log of one session (13:55–14:05) plus screenshots
and screen recordings taken during testing (not committed to the repo).
Three **test-only edits** were used and never committed: a 4s delay before
`reserve` in `_reconcileLine` (normal reserve latency is 350–1100ms, too
short to screenshot `isReserving`), and, in `fake_api_service.dart`, the
hold shortened from 5 minutes to 20s and the checkout latency raised to
10–10.5s (to hit `410` by hand).

**Console log (reservation bookkeeping, no test edits):**

| Time | Log | What it shows |
|---|---|---|
| 13:55:50 | `POST /reservations dealId=1` | add → hold (res_1) |
| 13:59:50 | `POST /reservations dealId=2` | add → hold (res_2) |
| 13:59:57 | `dealId=3` then `ERROR: reservation failed … 409 … someone grabbed the last one` | random contention (`_mutationCounter % 5 == 3`) → rollback; no reservation id consumed |
| 14:00:08 | `POST /reservations dealId=4` | res_3 |
| 14:01:32 / :33 | `DELETE res_2`, `POST dealId=2 qty=2` | "+" → old hold released, new one (res_4) |
| 14:01:36 / :37 | `DELETE res_3`, `POST dealId=4 qty=2` | "+" on another line (res_5) |
| 14:01:45 | `DELETE res_4`, `POST dealId=2 qty=1` | "−" → released and re-reserved at qty 1 (res_6) |
| 14:02:04 | `DELETE res_6` | line removed → hold released |
| 14:03:07 | `POST /checkout items=1` then `502 … card was not charged` | checkout failure; bag kept |
| 14:04:26 | `POST /checkout items=1` | retry succeeds |
| 14:04:55 | `POST /checkout items=1` (deal 6, res_7) | success |
| 14:05:31 | `dealId=6` → `409 Not enough stock left` | real sold-out → rollback |

Ids run res_1…res_7 with no gaps or duplicates, so no reservation was
orphaned or double-created by the quantity changes. No `DELETE
/reservations/…` follows either successful checkout (consumed holds are not
released).

**Screenshots / recordings:**
- *Optimistic add + `isReserving`* (with the 4s test delay): bag opened
  straight after "Add to bag" shows "Holding your item…", greyed +/−,
  "Confirming stock for your bag…" and a greyed Checkout; after the delay
  `Held for 04:57` and Checkout turns green. In normal use this window is
  only the 350–1100ms reserve latency.
- *409 rollback in the UI:* the line disappears and the snackbar reads
  "Couldn't hold this item — Last-call Bakery Bag just sold out — sorry! It
  has been removed from your bag."
- *Expiry while on the bag screen:* `Held for 00:01`, then the line is gone,
  "Your bag is empty", and "Hold expired — Chef's Thai Bundle's 5-minute
  hold ran out, so it was removed from your bag…".
- *Checkout success:* spinner, then "Order confirmed — Order #9102 — pick up
  soon!" and an empty bag.
- *Checkout `410`* (test edits: 20s hold, ~10s checkout latency): Checkout
  tapped at `00:05`. About 5s later the countdown reached zero mid-request
  and the line was removed with "Hold expired". About 10s after the tap the
  console printed `09:43:30.551 ERROR: checkout failed | ApiException(410):
  Reservation expired — stock was released`. The server checks expiry
  *after* its latency, so a tap only produces `410` when the remaining time
  is shorter than that latency; two earlier attempts tapped with 10s and
  16s left (latency ~6s) and both succeeded, as this predicts.

**Tested separately by the author (self-reported; no log or recording of
these runs is attached here, so treat them as the author's word rather than
evidence in this file):**
- The full text of the "Some holds expired…" snackbar after a `410`, and
  Checkout returning to its normal state afterwards.
- `pruneExpiredReservations()` removing a locally-expired line.
- The stale-result branches of the `_lineOpToken` guard under rapid taps.
- "+/−" greying Checkout while a line is reconciling.

**Not verified:**
- Deal 1 vanishing from the bag in the 13:55–14:05 log is consistent with
  expiry (hold ends ≈14:00:50 while the bag was open from 14:00:10) but the
  log can't show the snackbar, so that one is an inference; expiry itself is
  confirmed by the screenshots above.
- No automated tests were added, and `flutter analyze` output is not
  recorded here.

### F-3 addendum · Flash-sale items in the bag (deadline = hold OR sale end)

- **Problem found on review:** the bag showed `Held for 05:00` for every line,
  even a flash deal whose sale ended in 2 minutes. Flash expiry was only
  handled by `DealCard`, `_FlashRailCard` and `DealDetailsController`, i.e.
  only while one of those was mounted. On the bag screen none of them is, so
  the line stayed with a live-looking hold. The backend's `checkout` validates
  reservation ids only and never `flashSaleEndsAt`, so that line could also be
  bought at the flash price after the sale ended.
- **Fix:**
  - `CartItemModel.effectiveDeadline` = earlier of `reservation.expiresAt` and
    `deal.flashSaleEndsAt`; `endsByFlashSale` picks the label
    ("Flash sale ends in" vs "Held for") and colour.
  - `CartService` owns one `Timer` per line aimed at that deadline
    (`_scheduleDeadline`), so expiry no longer depends on any widget being
    mounted. It is set when a flash line is added (before the reservation
    returns), rescheduled when a reservation lands, and cancelled on every
    removal path and in `onClose`.
  - `handleLineExpired` replaces `handleReservationExpired`. Flash ended →
    remove and **release** the still-valid hold (frees stock at once). Hold
    ended → remove without release (already expired server-side). It is
    idempotent, so the timer and the bag badge can both fire and the user sees
    one notice.
  - `pruneFlashExpired()` runs at the start of `checkout()`; if it removes
    anything, checkout stops and asks the user to review the bag (the total
    changed) rather than continuing automatically.
  - `CartService.add()` and `DealModel.isFlashExpired` refuse to add a deal
    whose sale has ended (covers the bag's "+" button).
- **Rejected:** capping the reservation itself to the sale end. The backend
  fixes the hold at 5 minutes and cannot be changed, so the client aims at the
  earlier deadline instead.
- **Not handled:** a sale that ends *while* a checkout request is already in
  flight (the backend would still accept it; needs a server-side check).
  Device clock changes shift local deadlines; the server clock is the source
  of truth and no offset correction is applied. Not compiled or run in this
  environment (no Flutter SDK): needs `flutter analyze` and a manual run with a
  flash deal whose `flashSaleMinutes` is under 5.
