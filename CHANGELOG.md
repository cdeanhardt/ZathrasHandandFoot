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

## v39 — 2026-06-27
**Book lift changed from a (wrong) multiplier to a fixed ~2-inch clearance.** v38 used
`raisedY = p.y * 3`, which is 3× the absolute world Y (table base included), not 3× the height
off the table — a large, position-dependent lift. Replaced with `raisedY = p.y + 2.0` in
`executeMoveBooks` (`Global.-1.lua`): a fixed 2.0-board-unit lift above the deck's resting
height. Per this game's card constant (gv_CARD_SIZE x=3/z=2 ≈ a 3.5"×2.5" card), 1 board unit
≈ ~1.2", so 2.0 units ≈ ~2.4" — the "≈2 inches to clear easily" requested. Tunable.

## v38 — 2026-06-27
**Books now travel HIGH over the table when moving to the score zone.** `executeMoveBooks`
(`Global.-1.lua`) used to slide a book flat across the table to its slot, dragging it past
neighbouring melds (mixing cards). It now does a 3-phase arc: lift straight up to ~3x the
book's height off the board (`raisedY = p.y * 3`, tunable), carry it across at that height to
above the slot, then lower it straight down. Phases spaced (1.0s, 2.0s) so each setPositionSmooth
finishes before the next; rotation waits until after the drop (delay+3.7); per-book cadence
1.6→2.7s; finalDelay adjusted.

## v37 — 2026-06-24
**Booking a meld no longer steals cards (rank OR wild) from the adjacent meld.** The wild/meld
stacking branches in `executeTurnPlan` (`ZHF_Advisor.lua`) fed `stackOrSpread` a `safe` list
built partly from `getCardsNearPos(..., 3.0)` (and `getMeldColumnObjects`'s ±2.0 wild absorption)
with no column filter — so a 3-unit radius reached into the neighbouring column and swept its 9s
(and stray wilds) into the book, making an invalid mixed book. Only the wild-only branch had the
v15 lateral filter; the partial-play, naturals-already-placed, and new-wild-meld branches did not.
Added a shared `filterToColumn(objs, anchorPos)` helper (keep only cards within 1.5 lateral units
of the deposit column — positional, so it drops stray 9s and stray wilds alike, keeps in-column
wilds) and applied it to the final `safe` in all four branches before stacking.

## v36 — 2026-06-24
**Manual Draw/Plan resumes auto-play (false-ending recovery).** New `resumeAutoPlay()`
(`ZHF_UI.lua`) clears `gbAutoSuppress` plus the transient hand-end flags
(`gbHandOver`/`gbFinishFlag`/`gbHandWonPause`), called at the top of `click_ActionDraw` and
`click_ActionPlan`. So if a "gone out" detection was a FALSE ending and play continues, pressing
Draw or Plan re-enables autodraw/autoexec immediately (not after the flags time out). Auto stays
on until the hand genuinely ends again (which re-sets gbAutoSuppress via the go-out handler).

## v35 — 2026-06-24
**Suppress autodraw/autoexec for the rest of an ended hand.** The existing gates used
`gbHandOver`, which resets at scoring (~3s after go-out), so a turn-start in the window before
the next deal could re-trigger auto. Added a dedicated `gbAutoSuppress` flag: set true on go-out,
cleared only in `initializeHand` (the new deal). Added `not gbAutoSuppress` to all three gates —
autodraw (`onPlayerTurnStart`), the autoexec countdown tick, and the autoexec kickoff
(`ZHF_UI.lua`). Net: once the hand ends, no autodraw/autoexec until the next hand, at which point
it resumes on the player's turn as usual (if the boxes are checked).

## v34 — 2026-06-22
**Top-card re-stack moved out of `scoreTarget` (it was flinging cards off moving books).** The
"bubble the right-coloured card to the top" logic was a side effect of `scoreTarget`, which runs
on every scoring/meld scan — including the one `executeMoveBooks` triggers while books are still
sliding — so `takeObject` ejected the top card off a moving deck.
- New `restackBookTop(deck)` (`Global.-1.lua`): same red/black/joker-on-top rule, but with a
  MOTION GUARD (skips if the deck has velocity) and valid-book checks (qty 7–20, single rank),
  so it only ever runs on a stationary book.
- `scoreTarget` now just classifies/scores — no mutation.
- Triggered on card-add via `onObjectEnterContainer` (`ZHF_Events.lua`, re-enabled but never
  touches the entering card — only the bag's guid, deferred + retried until the deck is parked,
  debounced per deck), and after each book settles in `executeMoveBooks`.
Keeps today's behavior (re-stacks when auto-play or a player adds a card) without the mid-move drop.

## v33 — 2026-06-21
**Books shed/drop a card while moving to the score zone — two fixes** (`executeMoveBooks`,
`Global.-1.lua`):
- **#1 Solidify before moving.** New `solidifyBook()` box-casts a one-card footprint around the
  Deck and `putObject`s any loose Card sitting on/beside it into the Deck before the slide, so a
  fragile physics-merge doesn't carry a straggler that gets dropped (tight box so it can't grab
  an adjacent column).
- **#3 Rotate later.** The post-move rotation delay went 1.2s → 2.2s so the book has clearly
  arrived and is at REST before rotating (rotating mid-motion shocks physics and ejects the top
  card). finalDelay adjusted 0.4 → 1.4 accordingly.

## v32 — 2026-06-20
**Debug Trace no longer wipes itself each turn.** `executeTurnPlan` was calling `traceClear()`
on every plan, so a crash trace got erased before it could be copied. Removed the auto-clear;
each execution now appends a `=== execute plan ... @t= ===` separator and the buffer accumulates
(cap raised 300→600 lines, self-trimming oldest). `traceClear()` stays available for a manual
fresh start (or delete the tab).

## v31 — 2026-06-20
**Debug Trace tab was locked.** It was created with `color="Red"`, which locks a notebook tab
to the Red player. Changed to `color="Grey"` (neutral/everyone) in `trace`/`traceClear` so it's
selectable. The existing locked tab updates to Grey on the next trace write.

## v30 — 2026-06-20
Three things for the wild-completes-black-book crash (red book + "Object reference not set"):
- **Breadcrumb tracer to a notecard.** New `trace()`/`traceClear()` (`Global.-1.lua`) write
  step-by-step breadcrumbs to a **"Debug Trace" notebook tab** (gated by `gbTraceOn=true`).
  Since the C# ref error escapes pcall and has no Lua line, the LAST line before a crash is
  the culprit. Wired into `executeTurnPlan` start + the wild-on-meld branch.
- **Crash fix.** The wild-on-meld executor used a captured `meldObj`; if a prior play booked &
  moved that meld, the ref is dead and `getPosition()` threw the escaping C# error. Now it
  re-fetches the position LIVE via `getMeldAnchor(rank)` (nil if gone → skip, no crash).
- **Red-instead-of-black fix.** Gated the second-pass p5 (`ZHF_Advisor.lua`): it only fires for
  a real go-out setup (post-foot, ≥2 red projected, wilds reach the 2nd black book). Otherwise
  it over-filled a book the wild already completes to 7 — and being executed before the wild,
  the natural made a RED book and stranded the wild.

## v29 — 2026-06-19
**Pause-before-move 2.0s → 2.5s in all three book paths** (cards still occasionally dropping
off; +0.5s to catch the rest). Bumped the settle-pause in `stackOrSpread` (ZHF_Advisor, both
passes), `spread4` (Global, both passes), and `bookByStacking` (Global). Executor backup
checkAndMoveBooks calls left at their own timings.

## v28 — 2026-06-19
**Added the missing settle-pause to the third book path (`bookByStacking`).** The 2.0s
pause-before-move from v21/v22 was only in `stackOrSpread` (wild) and `spread4` (manual);
`bookByStacking` — the auto-exec NATURAL-rank book path, the most common one — still called
checkAndMoveBooks immediately after its sweep (~0.8s), so natural books moved with no settle
time (cards left behind / moving as two pieces). Now it waits 2.0s after the sweep before
moving (move at ~2.8s), and the backup check moved 4.0s → 5.0s to stay after it. (`Global.-1.lua`)

## v27 — 2026-06-19
**Hotseat root cause found + fixed: dealt hand fuses into a Deck.** The v26 diagnostic showed
the hand cards were a single `Deck` (q=12) in the hand zone — in hotseat the rapid deal lands
cards on one spot and TTS physics merges them, instead of them entering the hand individually
(multiplayer). `getHandCards` was only accepting `tag=="Card"`, so it skipped the deck. Now,
when the hand-zone box-cast hits a Deck, it EXPLODES it: `takeObject`s each card out to a
spread position (so they stay individual and don't re-merge) and adds the returned refs, which
the planner can read and play. (debugHand diagnostic kept one more round to confirm; remove
next.) Cosmetic fanning may still be off, but the planner now gets real card objects.

## v26 — 2026-06-19
**TEMP diagnostic build** (v24/v25 hotseat hand-read fixes didn't work; instrumenting before
guessing again). Added `debugHand(sColor)` (`Global.-1.lua`) which logs: getHandObjects count,
seated state, getHandTransform pos/scale/rot, what the hand-zone box-cast finds, and every
Card/Deck within 15u of the hand origin. Called once at the top of `buildTurnPlan`
(`ZHF_Advisor.lua`). User runs the plan in hotseat and pastes the [HANDDBG] log so we can see
WHERE the dealt cards actually are and WHAT they are (loose Cards vs a merged Deck). REMOVE
both the function and the buildTurnPlan call once diagnosed.

## v25 — 2026-06-19
**Hotseat hand read must MERGE, not only-if-empty (fixes v24).** v24 only ran the hand-zone
scan when `getHandObjects()` returned 0 cards. But a hotseat hand can be MIXED — cards drawn
on the active seat get registered, dealt cards don't — so `getHandObjects()` returned the 2
drawn cards (non-empty), the fallback was skipped, and the planner missed the dealt cards.
Changed `getHandCards` (`Global.-1.lua`) to always UNION both sources, deduped by GUID:
managed hand cards + any Card physically in the hand zone. Multiplayer unchanged (the two
sources are identical there); a card inside a hand zone is by definition a hand card, so no
false positives. (Cosmetic fanning still unaddressed — separate issue.)

## v24 — 2026-06-19
**Auto-plan now reads the hand in hotseat mode.** `getHandCards` (`Global.-1.lua`) relied
solely on `Player[color].getHandObjects()`, which returns the TTS-managed hand set. In hotseat,
cards dealt to a seat that isn't the live/active one never get registered into the hand system
(same reason they don't fan), so the planner saw an empty hand. Added a fallback: only when
`getHandObjects()` returns 0 cards, box-cast the hand zone (`getHandTransform`) and read the
loose Card objects physically present there. Multiplayer is unaffected — `getHandObjects()`
always returns there, so the fallback never runs. (Hotseat untested from dev side; user verifies.)

## v23 — 2026-06-17
**Version stamp is now Lua-driven so it reliably reflects the loaded code.** The static XML
`text` on `ActionVersionStamp` isn't always rebuilt on a Ctrl+Alt+S hot-reload, so the panel
could show a stale version even when the new code was live. Added `gsVersion` constant in
`Global.-1.lua` and an `UI.setAttribute("ActionVersionStamp","text",gsVersion)` in onLoad
(setAttribute repaints a live element). `gsVersion` is now the bump point (source of truth);
the XML text is just a pre-onLoad fallback. Bonus: if the panel ever shows an OLD number now,
the Lua genuinely didn't load — a real clobber detector.

## v22 — 2026-06-17
**Lengthened the pause-before-move by another second** (1.0s → 2.0s) in both `stackOrSpread`
(`ZHF_Advisor.lua`) and `spread4` (`Global.-1.lua`), per request — books were still
occasionally moving before the merge fully settled. Settle-before-reclaim stays 2.0s; the
post-reclaim pause before `checkAndMoveBooks` is now 2.0s.

## v21 — 2026-06-15
Two more reclaim/timing fixes:
- **Wild book bloating to 9/12 cards and becoming unscoreable/uncollectable.** The reclaim
  absorbed `qty<7` pieces into the LARGEST object — so a separate wild sub-deck played near an
  already-complete wild book got pulled into it (7→12). Fixed (`Global.-1.lua`
  `reclaimColumnStragglers`): if the largest object in the column is already a complete book
  (qty>=7) it does nothing (never grows a finished book), and absorption now STOPS at 7 so a
  book can't be over-filled. (Diagnosed: 12 = a 7 book + ~5 pile, not two 7s fusing.)
- **Books moving as two pieces / shedding a card mid-move despite the v19 pause.** The merge
  wasn't finished when the move fired. Lengthened the timing in both `stackOrSpread`
  (`ZHF_Advisor.lua`) and `spread4` (`Global.-1.lua`): settle-before-reclaim 1.5s→2.0s, and
  pause-before-move 0.5s→1.0s.

Note: wild decks already bloated by earlier versions are corrupted in-save and won't be
repaired by this — they must be removed manually.

## v20 — 2026-06-15
**Refined the v19 reclaim guard so it doesn't block legitimate consolidation.** v19's "bail if
2+ Decks in the column" couldn't distinguish two finished books (must NOT fuse) from two
incomplete sub-decks of the same meld (an accidental 3+4 split that SHOULD book up) — so it
would have prevented booking a split meld. Changed the discriminator from deck-vs-card to
QUANTITY (`Global.-1.lua` `reclaimColumnStragglers`): it now bails only when 2+ COMPLETE books
(qty>=7) are co-located, and otherwise absorbs every qty<7 piece (loose cards AND sub-decks)
into the largest base while never pulling in a qty>=7 neighbour. Keeps the two-books-fuse
protection and the deal/setup guard, but lets split/sub-deck melds consolidate and book.

## v19 — 2026-06-15
Two fixes to the v18 book/reclaim work:
- **`reclaimColumnStragglers` could fuse two real books into a mixed, scoreless, uncollectable
  deck** (it merged by position, not rank — seen as two of Blue's books collapsing at new-hand
  deal). Hardened (`Global.-1.lua`): it now ONLY absorbs loose single Cards (tag=="Card") into
  exactly ONE Deck base; if two+ Decks are in the column it bails (never fuses Decks together);
  and it no-ops while `gbDealing`/`gbInitializing` (cards in motion during deal/reset).
- **Cards sometimes started moving to the score zone before the book finished assembling**, so
  one dropped half-way. Added a 0.5s pause between booking (reclaim) and moving
  (`checkAndMoveBooks`) in both `stackOrSpread` (`ZHF_Advisor.lua`) and `spread4`'s book branch
  (`Global.-1.lua`) — reclaim, let it settle, then move.

## v18 — 2026-06-14
**Reverted v17's putObject formation (it regressed book-forming); kept the straggler fix a
different way.** v17 built the book by `putObject`-ing loose cards into a single-card base —
which is flaky (the first card+card merge often returns nil), so books frequently failed to
form at all. Reverted `stackOrSpread` and `spread4`'s ≥7 branch to the original physics
formation (co-locate via setPosition/setPositionSmooth — reliable at FORMING a deck). Added
new global `reclaimColumnStragglers(sColor, anchorPos)` (`Global.-1.lua`): after a settle
delay it re-scans the meld's own column (lateral filter, same 1.5-unit band as v15) and
`putObject`s any card physics left loose INTO the formed Deck — a reliable DECK-base merge —
before the book is moved. Both paths now call it (at 1.5s and 3.5s) ahead of checkAndMoveBooks.
Net: reliable formation (physics) + reliable straggler reclaim (deck-base putObject), fixing
the original "card left behind" without the v17 regression. `bookByStacking` still unchanged.

## v17 — 2026-06-14
**Book formation no longer strands a card ("card left behind").** Two consolidation paths
formed books by co-locating cards with `setPosition`/`setPositionSmooth` and relying on TTS
physics to fuse them — non-deterministic, so a card could fail to merge and be stranded, and
`checkAndMoveBooks` (timer-driven, no settle check) could move the deck out from under a
still-settling card. Converted both to deterministic, synchronous `putObject` merges (the
approach `bookByStacking` already used and documented as reliable):
- `stackOrSpread` (`ZHF_Advisor.lua`) — wild / auto-exec book consolidation.
- `spread4` ≥7 book branch (`Global.-1.lua`) — manual drops / "Layout Pretty". Cards are
  still spread (separate, valid refs) at that point, so they're safe to `putObject` directly.
Because putObject is synchronous the Deck reaches full size before the move timers fire,
fixing both the dropped-card and move-race mechanisms. `bookByStacking` was already robust
and left unchanged. No clones were involved — the stray was always a real, unmerged card.

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
