# Changes to Reapply After Revert

This document describes all changes made to `Global.-1.lua` since the last committed version,
organized by purpose. Re-apply these in order.

---

## 1. New constant: `gt_COLOR_ROT`

**Where:** Near the top of the file, on the line immediately after `gt_DECODE_DIR`.

**What:** A table mapping player color names to the Y-rotation of their hand zone.
```
gt_COLOR_ROT = {White=0, Blue=180, Green=90, Red=270}
```

---

## 2. Defensive guards in score-zone iteration functions

Several existing functions that loop over `objScoreZones[giPlayerCount]` could crash if called
before zones were fully initialized. Wrap each place that calls `scoreZone.obj.getObjects()`
with `pcall`, and add an early-return guard at the top of each function that checks
`objScoreZones[giPlayerCount]` before iterating.

**Affected functions:**
- `countScoreInternal`
- `whoIsFirst`
- `objectInScoreZone`
- `getAllScoreZones`
- `checkFootNote`

For `objectInScoreZone` and `getAllScoreZones` specifically, also add guards for
`colorEntry.zones` being nil, and wrap the `objectInZone` / `getGUID` calls in pcall
so a stale zone object doesn't crash the function.

---

## 3. New function: `getTableCardsOfRank(sColor, rank)`

**Where:** Insert as a new function. (Place it anywhere before `autoPlayMatchingCards`.)

**What:** Scans all of `sColor`'s score zones and returns a list of every face-up Card (or Deck)
whose rank matches `rank`. Skips face-down objects (foot piles). Uses pcall on
`scoreZone.obj.getObjects()` so a nil zone doesn't crash it.

---

## 4. New function: `autoPlayMatchingCards(sColor)`

**Where:** Insert immediately after `getTableCardsOfRank`.

**What:** "Play Hand" action. Scans the player's score zones to build a map of ranks already
on the table. Then scans the player's hand for non-wild cards whose rank is on the table.
Plays each matching card onto the corresponding table position with a 1.5-second delay between
cards, then calls `spread4` to tidy each line after all cards of a rank have landed.

Debug logging is gated on `gtDebugFlags["playhand"]`.

---

## 5. New function: `computeNewLinePosition(sColor, colorZones, rotY, tableY, dph)`

**Where:** Insert after `autoPlayMatchingCards`.

**What:** Helper for `layoutHandRank`. Given a player's color zones, works out where to drop a
brand-new line of cards.

- Uses `gt_DECODE_DIR[rotY]` to determine which axis is lateral and which is depth.
- `depth_dir` = same sign as `direction` (i.e. `depth_dir = direction`).
- Scans all face-up objects in the zones to find:
  - `bestTopDepth`: the depth position of the topmost card (highest `pos[depthAxis] * depth_dir`).
  - `bestLateralPos`: the lateral position of the rightmost card (highest `pos[lateralAxis] * direction`).
- If existing content found: places the new line at the same depth as the topmost card, laterally
  just past the rightmost card (`bestLateralPos + direction * (gv_CARD_SIZE.x + 0.5)`).
- If no existing content: places the new line at the center of the largest zone laterally, and at
  a depth so the top edge of the card is half a card-height from the zone's top edge:
  `zoneTopEdge - depth_dir * gv_CARD_SIZE.z`
  where `zoneTopEdge = zoneCenter[depthAxis] + depth_dir * (zoneDepthSize / 2)`.

---

## 6. New function: `layoutHandRank(sColor, rank)`

**Where:** Insert immediately after `computeNewLinePosition`.

**What:** "Layout Hand" action for a specific rank.

Rules enforced:
- Rank must not be "2", "3", or "Joker" (rejects wilds and 3s).
- Player must have 3 or more cards of that rank in hand.
- Playing them must not leave fewer than 2 cards remaining in hand.

Behavior:
- If a line of that rank already exists on the table (via `getTableCardsOfRank`), drops the hand
  cards onto the position of the first card in that existing line.
- If no line exists, calls `computeNewLinePosition` to find a new drop position.
- Moves cards one at a time with 0.3-second spacing.
- After all cards are placed (+ 1.0s buffer), resets `playerStuff[sColor].bSpreading = false`
  then calls `spread4` to lay them out properly. Falls back to the direct card list if the zone
  scan hasn't registered the new cards yet.

Debug logging is gated on `gtDebugFlags["layouthand"]`.

---

## 7. `onLoad`: Add "Play Hand" to hand zone context menus

**Where:** In `onLoad`, immediately after the four `obj_Zone["Color"] = ...` assignments.

**What:** Loop over `obj_Zone` and call `addContextMenuItem("Play Hand", ...)` on each hand
zone, binding to `autoPlayMatchingCards(c)`. This makes "Play Hand" appear when you right-click
the hand zone background or use the hand panel popup.

```lua
for sColor, zone in pairs(obj_Zone) do
  local c = sColor
  zone.addContextMenuItem("Play Hand", function() autoPlayMatchingCards(c) end, false)
end
```

**Important:** Do NOT add a `for _, oThing in pairs(getAllObjects())` loop anywhere in `onLoad`.
Context menu setup for all other objects is handled entirely by `onObjectSpawn`.

---

## 8. `onObjectSpawn`: Add "Play Hand" and "Layout Hand" items

**Where:** In the existing `onObjectSpawn` function, after the two existing `addContextMenuItem`
calls for "Layout Pretty" and "Layout TowardCam".

**What:**
- Add "Play Hand" to ALL spawned objects (same as the existing two items — no tag filter needed).
- Add "Layout Hand" ONLY to objects whose `tag == "Card"`. This guard is required — adding a 4th
  context menu item to scripting zones (hand zones) breaks their hand-zone behavior in TTS.

```lua
obj.addContextMenuItem('Play Hand', function(x) autoPlayMatchingCards(x) end, false)
if obj.tag == "Card" then
  obj.addContextMenuItem('Layout Hand', function(playerColor)
    local _, rank, _ = cardDeets(obj)
    layoutHandRank(playerColor, rank)
  end, false)
end
```

---

## 9. `onChat`: Add `#playhand` command and improve `#debug` command

**Where:** In `onChat`, in the block that handles `#` commands.

**What:**
- Add a `#playhand` command that calls `autoPlayMatchingCards(sColor)` directly (for testing
  without needing to right-click).
- Update the `#help` text to mention `#playhand`.
- Improve the `#debug` command so `#debug on` enables `playhand` debug specifically, and
  `#debug off` disables it — in addition to the existing behavior where `#debug <key>` sets
  an arbitrary key. (Any key works for debug flags; `#debug layouthand` will enable layout hand
  debug output without any additional code change.)

---

## Summary of what NOT to do (lessons learned)

- **Do not call `clearContextMenu()` anywhere.** It is not a valid TTS API method. Calling it in
  `onObjectSpawn` crashes the spawn handler and prevents cards from being placed in hand zones.
- **Do not add a `getAllObjects()` loop in `onLoad` to bulk-add context menus.** This doubles up
  with `onObjectSpawn`, accumulates on hand zones across hot-reloads, and eventually breaks hand
  zone behavior. All object context menus should be set up in `onObjectSpawn` only.
- **Do not add more than 3 context menu items to hand zone scripting zone objects.** TTS breaks
  their hand-zone behavior when they have too many. Use the tag filter in `onObjectSpawn` and the
  targeted `obj_Zone` loop in `onLoad` instead of bulk-adding to all objects.
