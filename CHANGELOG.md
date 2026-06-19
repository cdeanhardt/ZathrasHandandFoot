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
