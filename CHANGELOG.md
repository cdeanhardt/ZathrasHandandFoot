# ZHF Change Log — by ActionVersionStamp

This file maps each `ActionVersionStamp` value (shown in the Action panel, defined in
`Global.-1.xml`, id `ActionVersionStamp`) to the change(s) stamped under it. The stamp is
bumped once per code-change request so the in-game value confirms which build is loaded.

Use this to answer "when/where did behavior X change?" — each entry names the file,
function, and intent so the change can be located and verified against current code.

> Note: a single published build (one Ctrl+Alt+S) may bundle several stamps' worth of
> edits. Entries are listed by the stamp value set when each change was made. Versions
> before v10 predate this log; their history is in git only.

---

## v16 — 2026-06-14
**Play Jokers before 2s when committing wilds.** `sortWilds` (`Global.-1.lua`) gained a
`jokersFirst` parameter. The wild-allocation gather in `evalWildAllocations` (`ZHF_Advisor.lua`)
now calls `sortWilds(wildCards, true)` so wilds are consumed Jokers-first — when a wild book
(or any meld) is completed, the Jokers go on the table and any wilds left HELD in hand are the
cheaper 2s (20 vs 50 pts), minimising end-of-hand penalty. The two DISCARD-fallback callers
(`evalDiscard` Rule 8) keep the default 2s-first order so a forced wild discard sheds a 2.
No change to the existing "hold wilds unless the wild book can be completed this turn" or the
"play only as many as needed (cap 7)" behaviour — those already matched the desired rule.

## v15 — 2026-06-13
**Wild book execution-time over-fill fixed (column-aware sweep).** The wild-only execution
branch in `executeTurnPlan` (`ZHF_Advisor.lua`) gathered the pile to stack via a rank scan
(`getMeldColumnObjects` → `getTableCardsOfRank` returns rank-2 wilds embedded in OTHER melds)
plus a flat 3.0-radius proximity sweep (`getCardsNearPos`) — either could pull a wild from an
ADJACENT meld column into the wild book, over-filling it past 7 AND stripping the neighbour
meld of its black-book wild. Added a lateral-axis (`getPlayerDecodeDir`) filter on the final
`safe` list: keep only cards within 1.5 units laterally of the deposit point (same column).
Complements the v12 ALLOCATION cap, which was already correct — this is the EXECUTION layer.

## v14 — 2026-06-12
**Double icon refresh after a book moves.** `executeMoveBooks` (`Global.-1.lua`) now runs
its icon/score refresh twice — at `finalDelay` and again at `finalDelay + 2.5`. The first
pass can race the book's `setPositionSmooth`/zone-registration, so `countScoreInternal`
undercounts and skips an icon; the second pass re-counts after the book settles. Fixes
intermittent missing black/red/wild book icons.

## v13 — 2026-06-12
**Auto-exec stops when the hand is over.** `startAutoExecTimer` tick (`ZHF_UI.lua`) now
checks `gbHandWonPause`/`gbFinishFlag`/`gbHandOver` every tick and aborts the countdown
(so a plan mid-countdown when an opponent goes out is never auto-executed); `showPlanPanel`
won't start the countdown if the hand is already over. Manual Execute is unaffected.
Auto-draw was already gated by the same three flags at `Global.-1.lua` onPlayerTurnStart.

## v12 — 2026-06-12
**Wild book capped at 7 (Phase 4 / new wild meld).** `evalWildAllocations` Phase 4
(`ZHF_Advisor.lua`) added `and #assigned < 7` so a *fresh* wild pile never takes more than
7 wilds; extras stay in hand (held) to convert other melds to black books later. Phases 2/3
(completing an *existing* wild pile) were already capped via `neededForBook = 7 - combinedWildOnTable`.
NOTE: this caps ALLOCATION only — it does not cap the EXECUTION-time proximity sweep, which
can still over-fill a wild book by pulling a wild embedded in an adjacent meld (see open
issue tracked after v14).

## v11 — 2026-06-10
Two changes stamped here:
- **p5 "dump onto completed book" suppression.** `evalMeldsToPlay` (`ZHF_Advisor.lua`):
  a lone card is only played onto an already-complete book when pre-foot (`state.hasFoot`)
  or an opponent is one book from going out; otherwise it's held. p3 (extending an *open*
  meld) is unchanged. Genuine go-out re-adds book extensions via buildTurnPlan's go-out passes.
- **Container-event C# null-ref hardening.** `onObjectEnterContainer` (`ZHF_Events.lua`)
  made a no-op (it computed unused locals via `getGUID()`/`getDescription()` on cards being
  absorbed into a book Deck, throwing "Object reference not set" that escapes pcall).
  `onObjectLeaveContainer` now captures `obj.guid`/`bag.guid` via guarded reads and bails
  if invalid, using the captured strings in its deferred closures.

## v10 — 2026-06-10
**onLoad crash fix.** Added `require("ZHF_UI")` to `Global.-1.lua`'s require block. `ZHF_UI`
(which defines `setButtons` and the `click_*` handlers) had been extracted to its own module
but never required, so `setButtons()` in `onLoad` was nil → "attempt to call a nil value".
