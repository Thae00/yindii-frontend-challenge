# Rescu — Flutter Developer Assessment

Welcome! **Rescu** is a mini surplus-food marketplace: users browse discounted
end-of-day deals from nearby stores, add them to a bag, and pick them up during
the store's pickup window. It is a scaled-down version of the codebase you
would work on if you join us, using the same stack and conventions: **GetX**
(state, DI, routing), layer-first structure, hand-written JSON models,
`flutter_map`, and paginated lists.

The app runs fully offline against a simulated backend
(`lib/service/fake_api_service.dart`) with realistic latency and intermittent
failures — no API keys or accounts needed. See `README.md` for setup.

Deadline: One week. You do not need to finish
everything — see [How we grade](#how-we-grade).

---

## Ground rules

1. **AI tools are allowed and expected.** Use Cursor, Copilot, Claude, ChatGPT,
   whatever you like. We care about how _well_ you use them. You own every
   line you submit: in the follow-up interview we will pick lines from your
   diff and ask you to explain them.
2. **Do not modify** `lib/service/fake_api_service.dart` or anything in
   `assets/data/`. That is "the backend" — you can read it to learn the API
   contract, but pretend you can't deploy changes to it.
3. **Do not upgrade** Flutter or any package. Toolchain is pinned:
   **Flutter 3.27.0**, **Java 17** (for Android builds). If you are using a physical
   iPhone device with iOS 26 for debugging, you can use flutter version **3.38.10** to
   support debug run.
4. **Commit as you go.** One logical change per commit, with messages that
   tell the story ("Fix X because Y", not "wip"). Your commit history is part
   of the assessment. Add ticket name prefix in your commit message, e.g "[RES-101] fixed logic"
5. Note roughly how long you spent, honestly, in `solutions.md`.

---

## Part A — Bug tickets

These are real tickets from our team, written the way we receive them:
symptoms only. For each one you take on: **reproduce it, find the root cause,
fix it properly, and write up the diagnosis** in `solutions.md`.

A fix that merely hides the symptom (swallowing the error, adding a
try/catch, forcing a rebuild, etc.) scores worse than a correct diagnosis
with no fix at all.

### RES-101 · Search shows results for the wrong query

Type a word quickly in search — for example "sushi", letter by letter.
Frequently the final results do not match what is in the text box: correct
results appear briefly, then get replaced by results for an earlier, shorter
query. Team reproduces this most attempts. Users report "search is drunk".

### RES-102 · Crash after leaving My orders

Open **My orders** while there is an order with an upcoming pickup, then
navigate back. Within a couple of seconds the app crashes in debug builds with
`setState() called after dispose()`.

### RES-103 · Requests pile up the longer you browse

After opening several deal pages, every tap on "Add to bag" triggers a burst
of `GET /deals/:id` requests — one for _each deal viewed earlier in the
session_, even for screens that were closed long ago. The app gets slower
and chattier the longer the session. Watch the console logs while browsing
to see it (every simulated request is logged).

### RES-104 · Duplicate deals in the home feed

Scroll to the bottom of the home feed so the next page starts loading, then
quickly pull down to refresh while it is still loading. Intermittently the
feed ends up with duplicated cards, or more items than the catalog contains.

### RES-105 · Home feed is janky and memory keeps climbing

On mid-range Android devices the home feed drops frames noticeably while
scrolling, and memory grows the further you scroll until the OS kills the app.
DevTools shows the entire feed rebuilding continuously during scroll, and the
image cache ballooning. There is more than one contributing cause — we expect
you to find and explain them, with before/after evidence from DevTools
(screenshots or numbers in `solutions.md`).

### RES-106 · Wrong pickup times; "Pickup today" filter misses deals

Multiple user complaints: a bakery that opens **06:00–09:30** shows
"Pick up 23:00 – 02:30" on its cards, and several stores with pickup slots
today never appear when the **Pickup today** filter is on. Some users showed
up at closed stores. The backend team insists their data is correct and
points out the API sends standard ISO-8601 UTC instants, like every API we
integrate with.

### RES-107 · Deep link opens to a crash

Marketing sends push notifications that deep-link to deals, e.g.
`rescu://open/deal?id=42&source=push`. Opening such a link crashes with
`type 'Null' is not a subtype of type 'DealModel'`. Opening the same deal
from the home feed works fine.

Repro options:

- In-app: Home → overflow menu (⋮) → **Simulate deep link…**
- Android: `adb shell am start -a android.intent.action.VIEW -d "rescu://open/deal?id=42&source=push" dev.rescu.rescu`

Requirement: the link must land the user on a fully working deal page (deal
42 exists in the catalog). Showing an error/fallback screen instead is not an
acceptable resolution for this ticket.

---

## Part B — Features

Same expectations as production code: correct, performant, and reviewed by
you before submission.

### F-1 · Live flash-sale countdowns

Flash deals (`flashSaleEndsAt` on the model) currently show a static
"Ends soon" badge. Replace it with a **live countdown** (`mm:ss`, or
`hh:mm:ss` above an hour) everywhere the deal appears: flash rail, home feed
cards, and the details screen.

Requirements:

- When a countdown reaches zero: the card switches to a disabled "Expired"
  state, the deal can no longer be added to the bag, and if it is already in
  the bag it is removed with a visible notice.
- The home feed must stay smooth with 100+ visible countdowns. We will
  profile your implementation with DevTools; per-second rebuilds must be
  scoped to the text that actually changes — not whole cards, not the whole
  list.

### F-2 · Impression tracking

Product wants view analytics on deal cards. Using `AnalyticsService`:

- Log a `deal_impression` event when a deal card has been **≥50% visible for
  at least 1 continuous second**. Properties: `deal_id`, `source`
  (`home_feed`, `flash_rail`, or `search`), `position` (index in its list).
- At most **once per deal per app session**, across all screens.
- Do not send events one by one: batch them and deliver via
  `FakeApiService.sendAnalyticsBatch` when either 10 events have accumulated
  or 15 seconds have passed since the first unsent event — whichever comes
  first.
- Scrolling performance must not regress.
- The `visibility_detector` package is already in `pubspec.yaml`; using it is
  allowed but not required.

Verify your events on the **Analytics debug** screen (Home → ⋮ → Analytics
debug).

### F-3 · Stock reservations with optimistic UI

Right now the bag is purely local, so two users can "add" the last bag and
one of them finds out only at pickup. The backend already exposes
reservations (see `FakeApiService.reserveDeal` / `releaseReservation`, and
`reservationId` on checkout): a reservation holds stock for **5 minutes** and
intermittently fails with a 409 when stock is contended.

Build reservation support into the bag:

- Adding to the bag reserves stock. The UI must respond **optimistically**
  (instant feedback), then reconcile: if the reservation fails, the item is
  rolled back out of the bag with a clear, non-technical message.
- Each bag line shows how long its reservation has left.
- Removing a line (or reducing quantity) releases/adjusts the hold.
- Checkout passes reservation ids; handle the `410 reservation expired`
  rejection gracefully.
- **Deliberately underspecified:** what should happen when a reservation
  expires while the user is still in the app (or mid-checkout)? Decide the
  product behaviour yourself, implement it, and justify the decision in
  `solutions.md`. There is no single right answer — there are wrong ones.

---

## Part C — Written deliverables

Add a **`solutions.md`** at the repo root containing:

1. **Per ticket/feature you worked on:**
   - Root cause (for bugs) — what was actually wrong, not just what you changed.
   - Why your fix is the right one; at least one alternative you considered
     and rejected, and why.
   - Edge cases you thought about (and which ones you decided not to handle).
2. **AI usage log:**
   - Which tools you used and for what.
   - At least **two concrete examples where an AI suggestion was wrong or
     misleading**, how you caught it, and what you did instead.
3. **Design questions** (short answers, a paragraph each):
   - Q1: In this codebase, what is the difference between a `GetxController`'s
     lifecycle and a widget `State`'s lifecycle? Name one bug from Part A
     that exists because of confusion between the two.
   - Q2: When does wrapping a large subtree in a single `Obx` hurt you? How
     do you decide how tightly to scope reactivity?
   - Q3: How would you write an automated test that would have caught
     RES-106 before release? What (if anything) would you change in the code
     to make such a test possible?
4. **Time spent**, roughly, and what you would do next with one more day.

---

## How we grade

- **Diagnosis quality over volume.** Five tickets root-caused correctly with
  clean fixes beat all seven patched superficially. Same for features: a
  complete, profiled F-1 beats three half-done features.
- **Performance awareness.** We open your branch in DevTools.
- **Decision-making.** The underspecified parts are deliberate; we read your
  reasoning as carefully as your code.
- **Process.** Commit history, honesty about what is unfinished, and the AI
  usage log.

## Submission

1. Push your solution — **with full commit history** — to a **public** git
   repository (GitHub/GitLab/Bitbucket).
2. Make sure `solutions.md` is at the repo root.
3. Reply to the assessment email with the repository link.

Good luck — and enjoy.
