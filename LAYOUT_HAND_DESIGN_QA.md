# Layout Hand Feature — Design Q&A

This file captures the game rules context, questions asked, and answers given so the feature
can be re-implemented cleanly from a fresh start without repeating the design conversation.

---

## Game Context (provided by user)

- Hand and Foot is a variant of Canasta.
- Players draw cards and make **melds** from same-ranked cards with 0–2 wild cards (Jokers and 2s).
- Rank 3 cards are not used in melds.
- A meld must contain **at least 3 cards total** and **at least 2 ranked (non-wild) cards**.
- A complete book/canasta = 7 cards. `spread4` recognizes near-books (6 cards) and complete books
  (7+) and lays them out accordingly (stacked and turned sideways for a complete book).
- The game does not absolutely enforce meld validity — invalid melds are allowed but flagged
  during scoring.

---

## Zone Layout

- Each player has 1–3 score zones (depends on player count).
- **Zone 1** is the primary large zone where melds are laid out during play.
- Zones 2 and 3 are smaller side areas used for scoring organization (player may move cards there).
- Score zones are set up when the NewGame button is clicked, not at load time.

---

## `spread4` behavior (from code)

- `spread4(player, desiredPos, tCards)` places the **first card at `desiredPos`** (topmost,
  nearest board center), then advances subsequent cards **away from center** using
  `changeRelativePosition(pos, rot, false)`.
- Detects the player's rotation from which score zone the first card belongs to.
- Silently exits (no-op) if `playerStuff[player].bSpreading == true`.
- Handles near-books (6 cards) and complete books (7+) specially.

---

## `cardDeets(card)` returns `(color, rank, suit)`

- `color`: `"Wild"` / `"Black"` / `"Red"`
- `rank`: `"K"`, `"4"`, `"2"`, `"Joker"`, etc.
- Wilds: rank `"2"` or `"Joker"`, color `"Wild"`

---

## Key constants

```lua
gv_CARD_SIZE    = {x=3, y=1, z=2}   -- card dimensions (y = thickness)
gfSpreadMult    = 0.8                -- advance distance per card within a meld
gt_DECODE_DIR   = { [0]={"x",-1}, [90]={"z",-1}, [180]={"x",1}, [270]={"z",1} }
--   {lateralAxis, direction}
--   White(0)  → lateral=x, direction=-1
--   Green(90) → lateral=z, direction=-1
--   Blue(180) → lateral=x, direction=+1
--   Red(270)  → lateral=z, direction=+1
```

Constant to add (not in committed code yet):
```lua
gt_COLOR_ROT = {White=0, Blue=180, Green=90, Red=270}
```

Inter-meld spacing (from `nearMe`):
```lua
cardGap = gv_CARD_SIZE.x + 0.2   -- = 3.2, lateral center-to-center between different rank melds
```

---

## Direction conventions

`direction` from `gt_DECODE_DIR` serves double duty:

1. **Lateral "right"**: `pos[lateralAxis] + direction * cardGap` moves one meld-width to the right
   (from the player's perspective).
   - Left = `pos[lateralAxis] - direction * cardGap`

2. **Depth "toward center"**: `direction` is also the sign of "toward board center" along the
   depth axis.
   - `depthAxis = (lateralAxis == "x") and "z" or "x"`
   - `zoneTopEdge = zone.center[depthAxis] + direction * (depthScale / 2)`
   - Verified: White dir=-1, top edge = zone.center.z - scale.z/2 ✓
                Blue dir=+1,  top edge = zone.center.z + scale.z/2 ✓

---

## Design Q&A

### Q: Is zone 1 always where melds go? What are zones 2/3 for?
**A:** Zone 1 is where melds go during play. Zones 2 and 3 are used for scoring organization —
players may move cards into those spaces. All three zones are used for score calculation.

### Q: Should wildcards be included automatically when laying out a rank?
**A:** No. For now, wildcards are left to the player to play manually. The layout functions
only play same-rank non-wild cards.

### Q: Should meld validity be enforced?
**A:** Partially. Enforce the 3-card minimum and the "can't leave fewer than 2 in hand" rule.
Don't enforce wild card limits — the game allows bad melds and flags them during scoring.
`spread4` itself handles the visual presentation of near-books and complete books.

### Q: What triggers "Play Hand" and "Layout Hand"?
**A:** Both are right-click context menu items on cards. "Layout All Hand" is also a right-click
option.

### Q: Is there a "layout all eligible ranks" operation?
**A:** Yes — `layoutHandAll(sColor)` cycles through every rank in the player's hand that has
3+ cards, calling `layoutHandRank` on each one sequentially.

### Q: When adding cards to an existing meld, how should they be positioned?
**A:** Drop the new cards onto the existing meld position, then call `spread4` on the full
set (existing + new). `spread4` handles the re-layout.

### Q: Where does the FIRST meld go when zone 1 is empty?
**A:** Center of zone 1 laterally. Depth: the center of the topmost card should be
**1.5 card-heights from the zone's top edge** (toward the player).

Formula:
```
zoneTopEdge       = zone1.center[depthAxis] + direction * (depthScale / 2)
firstCardCenter   = zoneTopEdge - direction * 1.5 * gv_CARD_SIZE.z
```

### Q: What is "top" — nearest board center or nearest player?
**A:** "Top" = the edge of the zone **closest to the board center** (farthest from the player).

### Q: Are melds in a single row or multiple rows?
**A:** Always a single row. A "row" is a vertical column from the player's perspective
(cards in a meld are spread away from the player; different rank melds are placed
side-by-side laterally).

### Q: What is the lateral gap between different rank melds?
**A:** `gv_CARD_SIZE.x + 0.2 = 3.2` units center-to-center (from `nearMe`).

### Q: Which direction does each new rank meld go?
**A:** To the **right** (from the player's perspective) of all existing content.
- "Right" = `pos[lateralAxis] + direction * cardGap`

### Q: What happens when zone 1 fills up to the right?
**A:** Start placing to the **left** of all existing melds:
- Left overflow: `leftmostCard[lateralAxis] - direction * cardGap`
- If that also fills up: go to the midpoint depth of zone 1 (halfway between top edge and
  bottom edge, i.e. zone1 center depth) and start there. (Practically never happens.)

### Q: Should Layout All Hand use delays between ranks?
**A:** Yes — no more than 1 second between finishing one rank and starting the next.

### Q: Is `direction` the correct sign for "right" and also for "toward center"?
**A:** Yes to both. Confirmed by user.

---

## Context Menu Wiring Rules

**Critical:** TTS scripting zones (hand zones) break if too many context menu items are added
to them during `onObjectSpawn`. The committed codebase adds 2 items to all objects in
`onObjectSpawn` and 1 item to hand zones in the `onLoad` obj_Zone loop = 3 total on hand zones.
Do not add more items to hand zones.

Rules:
1. **`onObjectSpawn`** — only add new items gated on `obj.tag == "Card"`. Never add new items
   unconditionally (would add to hand zone scripting zones).
2. **`onLoad` obj_Zone loop** — safe to add items here (zones are fully loaded). Can add
   "Layout All Hand" here alongside "Play Hand" if desired for the hand panel popup.
3. **Never call `clearContextMenu()`** — not a valid TTS API method. Crashes the spawn handler.
4. **Never add a `getAllObjects()` loop in `onLoad`** to bulk-add context menus — this duplicates
   `onObjectSpawn` and accumulates context menu items on hand zones across hot-reloads.

---

## Functions to Implement

### 1. `getTableCardsOfRank(sColor, rank)`
Scans all of `sColor`'s score zones. Returns a list of every face-up Card (or Deck) whose
rank matches `rank`. Skips face-down objects (foot piles). Uses pcall on getObjects() for safety.

### 2. `autoPlayMatchingCards(sColor)` — "Play Hand"
- Build map of ranks already on the table (scan score zones, ignore wilds and face-down)
- Find hand cards (non-wild) whose rank is on the table
- Play each onto the table position with ~1.5s delays between cards
- Call `spread4` after each rank's cards have landed to tidy the line
- Debug gate: `gtDebugFlags["playhand"]`

### 3. `computeNewLinePosition(sColor, colorZones, rotY, dph)`
Returns `{x, y, z}` for the top card of a brand-new rank meld.

Logic:
```
decode      = gt_DECODE_DIR[rotY]
lateralAxis = decode[1]
direction   = decode[2]
depthAxis   = (lateralAxis=="x") and "z" or "x"

-- Scan all face-up objects in colorZones.zones:
--   topmost:   max of pos[depthAxis] * direction
--   rightmost: max of pos[lateralAxis] * direction
--   leftmost:  min of pos[lateralAxis] * direction

cardGap = gv_CARD_SIZE.x + 0.2   -- 3.2

if existing content:
  newPos[depthAxis]   = topmost[depthAxis]
  newPos[lateralAxis] = rightmost[lateralAxis] + direction * cardGap
  -- check zone bounds; if outside, try left overflow:
  -- newPos[lateralAxis] = leftmost[lateralAxis] - direction * cardGap
  -- if still outside, fall back to midpoint depth (zone1 center depth), laterally centered

else (zone empty):
  zone1 = colorZones.zones[1]
  depthScale          = (depthAxis=="z") and zone1.scl.z or zone1.scl.x
  zoneTopEdge         = zone1.pos[depthAxis] + direction * (depthScale / 2)
  newPos[depthAxis]   = zoneTopEdge - direction * 1.5 * gv_CARD_SIZE.z
  newPos[lateralAxis] = zone1.pos[lateralAxis]   -- centered
```

### 4. `layoutHandRank(sColor, rank)`
- Reject wilds ("2", "Joker") and 3s
- Collect hand cards of that rank (non-wild)
- Guard: need 3+, must leave 2+ remaining in hand
- Find `existingCards = getTableCardsOfRank(sColor, rank)`
- If existing: `targetPos = topmost existing card position`
- If new: `targetPos = computeNewLinePosition(...)`
- Move cards to targetPos one at a time (0.3s apart)
- After all placed + 1.0s: reset `playerStuff[sColor].bSpreading = false`, call
  `spread4(sColor, targetPos, allCards)` where allCards = getTableCardsOfRank (or fallback
  to direct card list if zone scan hasn't registered yet)
- Debug gate: `gtDebugFlags["layouthand"]`

### 5. `layoutHandAll(sColor)`
- Collect all eligible ranks from hand (3+ non-wild cards of a rank, not "2"/"3"/"Joker")
- For each rank, schedule `layoutHandRank(sColor, rank)` with offsets so each rank starts
  no more than 1 second after the previous one finishes
- Approximate time per rank: `(numCards * 0.3) + 1.0 + buffer`

---

## Context Menu Items to Add

**In `onObjectSpawn`** (gated on `obj.tag == "Card"`):
```lua
obj.addContextMenuItem('Play Hand', function(playerColor)
  autoPlayMatchingCards(playerColor)
end, false)
obj.addContextMenuItem('Layout Hand', function(playerColor)
  local _, rank, _ = cardDeets(obj)
  layoutHandRank(playerColor, rank)
end, false)
obj.addContextMenuItem('Layout All Hand', function(playerColor)
  layoutHandAll(playerColor)
end, false)
```

**In `onLoad` obj_Zone loop** (after the existing `zone.addContextMenuItem("Play Hand", ...)` line):
```lua
zone.addContextMenuItem("Layout All Hand", function() layoutHandAll(c) end, false)
```
