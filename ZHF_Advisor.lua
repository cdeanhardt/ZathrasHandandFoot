--==============================================================================
-- ZHF_Advisor.lua
-- Turn advisor: snapshots game state, evaluates options, returns a TurnPlan.
-- No TTS animation calls.  Included by Global.-1.lua via -- #include.
--
-- Entry points:
--   buildTurnPlan(sColor)  → TurnPlan table (inspect or execute)
--   executeTurnPlan(plan)  → drives animations for the plan
--   printTurnPlan(plan, sColor) → prints plan.log to sColor's chat
--==============================================================================

-- ----------------------------------------------------------------------------
-- Book classification
-- ----------------------------------------------------------------------------

-- Examines a Deck object and returns its book type:
--   "red"   — 7+ cards, no wilds
--   "black" — 7+ cards, 1–2 wilds mixed in
--   "wild"  — 7+ cards, all wilds (2s and Jokers)
--   nil     — fewer than 7 cards, mixed ranks, or unreadable
function classifyBook(deckObj)
  local ok, qty = pcall(function() return deckObj.getQuantity() end)
  if not ok or not qty or qty < 7 then return nil end
  local ok2, cards = pcall(function() return deckObj.getObjects() end)
  if not ok2 or not cards then return nil end

  local wildCount  = 0
  local rankFound  = nil
  local mixed      = false

  for _, c in ipairs(cards) do
    local ok3, clr, rank = pcall(function()
      local cl, rk, _ = cardDeets(c)
      return cl, rk
    end)
    if ok3 then
      if clr == "Wild" then
        wildCount = wildCount + 1
      else
        if rankFound and rank ~= rankFound then mixed = true end
        rankFound = rankFound or rank
      end
    end
  end

  if mixed then return nil end           -- inconsistent ranks
  if wildCount == qty then return "wild" end
  if wildCount > 0 then return "black" end
  return "red"
end

-- ----------------------------------------------------------------------------
-- State snapshot
-- ----------------------------------------------------------------------------

-- Returns a plain-data snapshot of sColor's game state.
-- All evaluators and the plan assembler read from this; no TTS calls after this.
--
-- Fields:
--   color        string
--   hand         [{rank, suit, color, obj}]   — full hand
--   handCount    number
--   handByRank   {rank → count}               — non-wild, non-3 cards
--   wildCount    number                        — wilds in hand
--   melds        [{rank, isBook, bookType, obj, pos}]  — everything on table
--   meldsByRank  {rank → meld}                — first face-up meld per rank (non-book)
--   books        {red=[...], black=[...], wild=[...]}
--   bookCounts   {red=n, black=n, wild=n}
--   hasFoot      bool
--   canGoOut     bool                          — book requirements met
function snapshotState(sColor)
  local hand  = getHandCards(sColor)
  local melds = getMelds(sColor)

  -- Annotate each meld with bookType; build books index
  local books = {red={}, black={}, wild={}}
  local meldsByRank = {}
  for _, meld in ipairs(melds) do
    if meld.isBook then
      local bt = classifyBook(meld.obj)
      meld.bookType = bt
      if bt then table.insert(books[bt], meld) end
    else
      meld.bookType = nil
      -- Keep the first (topmost) non-book meld per rank for anchor lookups
      if meld.rank and not meldsByRank[meld.rank] then
        meldsByRank[meld.rank] = meld
      end
    end
  end

  -- Hand breakdown
  local handByRank = {}
  local wildCount  = 0
  for _, card in ipairs(hand) do
    if card.color == "Wild" then
      wildCount = wildCount + 1
    elseif card.rank ~= "3" then
      handByRank[card.rank] = (handByRank[card.rank] or 0) + 1
    end
  end

  local bookCounts = {
    red   = #books.red,
    black = #books.black,
    wild  = #books.wild,
  }

  local otherFootOnTable = false
  for _, otherColor in ipairs(playerList or {}) do
    if otherColor ~= sColor and playerHasFoot(otherColor) then
      otherFootOnTable = true
      break
    end
  end

  return {
    color            = sColor,
    hand             = hand,
    handCount        = #hand,
    handByRank       = handByRank,
    wildCount        = wildCount,
    melds            = melds,
    meldsByRank      = meldsByRank,
    books            = books,
    bookCounts       = bookCounts,
    hasFoot          = playerHasFoot(sColor),
    canGoOut         = (bookCounts.red >= 2 and bookCounts.black >= 2),
    otherFootOnTable = otherFootOnTable,
  }
end

-- ----------------------------------------------------------------------------
-- Evaluators
-- ----------------------------------------------------------------------------

-- Should the player go out this turn?
-- Returns {should=bool, reason=string}
function evalGoOut(state)
  if state.hasFoot then
    return {should=false, reason="foot pile still on table"}
  end
  if not state.canGoOut then
    return {
      should = false,
      reason = string.format("need >=2 red (have %d) and >=2 black (have %d)",
        state.bookCounts.red, state.bookCounts.black),
    }
  end
  return {should=true, reason="book requirements met and foot is gone"}
end

-- Which melds should be played from hand, and in what order?
-- Returns [{rank, cards, count, existingCount, priority, reason}] sorted by priority.
--
-- Priority tiers:
--   1 — play completes an existing meld/book to a book (≥7 total)
--   2 — play extends an existing meld or book (any count, including singletons/pairs)
--   3 — play starts a new meld (no existing meld of this rank on table, count ≥ 3)
function evalMeldsToPlay(state)
  -- Build a rank→{obj,count,isBook} lookup covering both open melds and books.
  -- (state.meldsByRank only holds non-book melds; books are indexed by type.)
  -- TTS getQuantity() returns -1 for a single Card object (not a Deck).
  -- Clamp to 1 minimum so existingCount is never negative.
  local function safeQty(obj, fallback)
    local ok, qty = pcall(function() return obj.getQuantity() end)
    if ok and qty and qty >= 1 then return qty end
    return fallback
  end

  local existingByRank = {}
  for rank, meld in pairs(state.meldsByRank) do
    existingByRank[rank] = {obj=meld.obj, count=safeQty(meld.obj, 1), isBook=false}
  end
  for _, bookList in pairs(state.books) do
    for _, book in ipairs(bookList) do
      if book.rank and not existingByRank[book.rank] then
        existingByRank[book.rank] = {obj=book.obj, count=safeQty(book.obj, 7), isBook=true}
      end
    end
  end

  local plans = {}
  for rank, count in pairs(state.handByRank) do
    if isEligibleRank(rank) then
      local existing      = existingByRank[rank]
      local existingCount = existing and existing.count or 0

      -- Include if we can start a new meld (count>=3) OR extend an existing one (any count).
      if count >= 3 or existing then
        local projected = existingCount + count
        local priority, reason
        if existing and existingCount < 7 and projected >= 7 then
          priority = 1
          reason = string.format("completes book: %d + %d = %d", existingCount, count, projected)
        elseif existing then
          priority = 2
          reason = string.format("extends %s: %d on table + %d from hand",
            existing.isBook and "book" or "meld", existingCount, count)
        else
          priority = 3
          reason = string.format("new meld: %d cards of rank %s", count, rank)
        end

        -- Gather actual card objects for this rank
        local cards = {}
        for _, card in ipairs(state.hand) do
          if card.rank == rank then table.insert(cards, card) end
        end
        table.insert(plans, {
          rank=rank, cards=cards, count=count,
          existingCount=existingCount, priority=priority, reason=reason,
        })
      end
    end
  end

  -- Sort: priority first, then larger melds before smaller at same priority
  table.sort(plans, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.count > b.count
  end)

  return plans
end

-- Strata for eligible ranks (4-7=1, 8-K=2, A=3).
-- Lower strata = discard sooner.
local gt_DISCARD_STRATA = {
  ["4"]=1,["5"]=1,["6"]=1,["7"]=1,
  ["8"]=2,["9"]=2,["10"]=2,["J"]=2,["Q"]=2,["K"]=2,
  ["A"]=3,
}
-- Rank ordering within a strata for tiebreaker (higher = discard first).
local gt_RANK_WITHIN_STRATA = {
  ["4"]=1,["5"]=2,["6"]=3,["7"]=4,
  ["8"]=1,["9"]=2,["10"]=3,["J"]=4,["Q"]=5,["K"]=6,
  ["A"]=1,
}

-- What card to discard after planned melds? Returns {card=entry_or_nil, reason=string}
--
-- Priority pipeline:
--  1. Black 3s — always first.
--  2. Non-wild, non-3 candidates only (red 3s never discarded; wilds held for last).
--  3. Minimum count: singletons before pairs before triples, etc.
--  4. Lowest strata within min-count: strata 1 (4-7) → 2 (8-K) → 3 (A).
--  5. Prefer same-color sets (all-Red or all-Black) within chosen strata/count.
--  6. Within chosen set, prefer the card whose removal leaves ≥1 of each color.
--  7. Tiebreaker: highest rank within the strata (K before 8, 7 before 4, etc.).
--  8. Wild fallback (no non-wilds left): 2s before Jokers.
--  9. Absolute fallback: first remaining card.
-- wildAllocs is optional — the list from evalWildAllocations.
function evalDiscard(state, meldPlan, wildAllocs)
  local melding = {}
  for _, m in ipairs(meldPlan) do melding[m.rank] = true end

  local playedObjs = {}
  if wildAllocs then
    for _, wa in ipairs(wildAllocs) do
      for _, card in ipairs(wa.wilds)        do playedObjs[card.obj] = true end
      for _, card in ipairs(wa.naturalCards) do playedObjs[card.obj] = true end
    end
  end

  local remaining = {}
  for _, card in ipairs(state.hand) do
    if not melding[card.rank] and not playedObjs[card.obj] then
      table.insert(remaining, card)
    end
  end

  if #remaining == 0 then
    return {card=nil, reason="hand emptied by melds (go out)"}
  end

  -- RULE 1: Black 3 always first.
  for _, card in ipairs(remaining) do
    if card.rank == "3" and card.color == "Black" then
      return {card=card, reason="black 3 — always discard first"}
    end
  end

  -- Partition into eligible candidates (non-wild, non-3) and wilds.
  local candidates, wilds = {}, {}
  for _, card in ipairs(remaining) do
    if card.color == "Wild" then
      table.insert(wilds, card)
    elseif card.rank ~= "3" then
      table.insert(candidates, card)
    end
  end

  -- RULE 8: Wild fallback only when no candidates remain.
  if #candidates == 0 then
    table.sort(wilds, function(a, b)
      return (a.rank == "Joker" and 1 or 0) < (b.rank == "Joker" and 1 or 0)
    end)
    if #wilds > 0 then
      return {card=wilds[1], reason=string.format("wild %s (no non-wilds remain — 2s before Jokers)", wilds[1].rank)}
    end
    return {card=remaining[1], reason="absolute fallback"}
  end

  -- Group candidates by rank.
  local byRank = {}
  for _, card in ipairs(candidates) do
    if not byRank[card.rank] then byRank[card.rank] = {rank=card.rank, cards={}} end
    table.insert(byRank[card.rank].cards, card)
  end
  local groups = {}
  for _, g in pairs(byRank) do table.insert(groups, g) end

  -- RULE 3: Minimum count.
  local minCount = math.huge
  for _, g in ipairs(groups) do
    if #g.cards < minCount then minCount = #g.cards end
  end
  local atMinCount = {}
  for _, g in ipairs(groups) do
    if #g.cards == minCount then table.insert(atMinCount, g) end
  end

  -- RULE 4: Lowest strata within min-count.
  local minStrata = math.huge
  for _, g in ipairs(atMinCount) do
    local s = gt_DISCARD_STRATA[g.rank] or 2
    if s < minStrata then minStrata = s end
  end
  local atMinStrata = {}
  for _, g in ipairs(atMinCount) do
    if (gt_DISCARD_STRATA[g.rank] or 2) == minStrata then
      table.insert(atMinStrata, g)
    end
  end

  -- RULE 5: Prefer mono-color groups.
  local function isMono(g)
    local c = nil
    for _, card in ipairs(g.cards) do
      if c == nil then c = card.color
      elseif card.color ~= c then return false end
    end
    return true
  end
  local mono = {}
  for _, g in ipairs(atMinStrata) do
    if isMono(g) then table.insert(mono, g) end
  end
  local pool = (#mono > 0) and mono or atMinStrata

  -- RULE 7: Tiebreaker — highest rank within strata.
  table.sort(pool, function(a, b)
    return (gt_RANK_WITHIN_STRATA[a.rank] or 0) > (gt_RANK_WITHIN_STRATA[b.rank] or 0)
  end)
  local chosen = pool[1]

  -- RULE 6: Within chosen group, pick card that leaves ≥1 of each color.
  local function colorCounts(cards)
    local cc = {}
    for _, c in ipairs(cards) do cc[c.color] = (cc[c.color] or 0) + 1 end
    return cc
  end
  local function removingKeepsBalance(card, groupCards)
    local cc = colorCounts(groupCards)
    cc[card.color] = cc[card.color] - 1
    for _, cnt in pairs(cc) do if cnt < 1 then return false end end
    return true
  end

  local pick = nil
  if #chosen.cards == 1 then
    pick = chosen.cards[1]
  else
    for _, card in ipairs(chosen.cards) do
      if removingKeepsBalance(card, chosen.cards) then pick = card; break end
    end
    if not pick then pick = chosen.cards[1] end
  end

  local reason = string.format(
    "%s — count=%d strata=%d rank-slot=%d%s",
    chosen.rank, minCount, minStrata,
    gt_RANK_WITHIN_STRATA[chosen.rank] or 0,
    isMono(chosen) and " [mono-color]" or "")
  return {card=pick, reason=reason}
end

-- ----------------------------------------------------------------------------
-- Wild allocation evaluator
-- ----------------------------------------------------------------------------

-- evalWildAllocations: decide which wilds to play and where.
-- Called after evalMeldsToPlay so projected meld counts include natural plays.
--
-- Each returned entry:
--   {rank, meldObj, naturalCards, wilds, existingCount, isNew, priority, completesBook, reason}
--
-- Priority tiers (allocation order, only applied when the caller decides wilds are allowed):
--   1 — new meld from a hand pair (2 naturals + 1 wild)
--   2 — extend a pre-existing meld on the table (1 wild, up to 2-wild limit)
--   3 — any remaining meld with < 2 wilds, fewest cards first
function evalWildAllocations(state, meldPlan)
  if state.wildCount == 0 then return {} end

  local rotY        = getPlayerRotY(state.color)
  local decode      = gt_DECODE_DIR[rotY]
  local lateralAxis = decode and decode[1] or "x"

  -- Returns (total, wilds) for an existing non-book meld column.
  local function getMeldInfo(rank)
    local naturalObjs = getTableCardsOfRank(state.color, rank)
    if #naturalObjs == 0 then return 0, 0 end
    local total, wilds = 0, 0
    local spreadLats = {}
    for _, obj in ipairs(naturalObjs) do
      if obj.tag == "Deck" then
        local ok, qty = pcall(function() return obj.getQuantity() end)
        local q = (ok and qty and qty >= 1) and qty or 1
        if q < 7 then
          total = total + q
          local ok2, cards = pcall(function() return obj.getObjects() end)
          if ok2 and cards then
            for _, c in ipairs(cards) do
              pcall(function()
                local cl, _, _ = cardDeets(c)
                if cl == "Wild" then wilds = wilds + 1 end
              end)
            end
          end
        end
      else
        total = total + 1
        local ok, pos = pcall(function() return obj.getPosition() end)
        if ok and pos then table.insert(spreadLats, pos[lateralAxis]) end
      end
    end
    if #spreadLats > 0 then
      local sumLat = 0
      for _, lat in ipairs(spreadLats) do sumLat = sumLat + lat end
      local avgLat = sumLat / #spreadLats
      local colorZones = getPlayerZones(state.color)
      if colorZones then
        for _, scoreZone in ipairs(colorZones.zones) do
          local ok, zoneObjs = pcall(function() return scoreZone.obj.getObjects() end)
          if ok and zoneObjs then
            for _, obj in ipairs(zoneObjs) do
              pcall(function()
                if not obj.is_face_down and obj.tag == "Card" then
                  local cl, _, _ = cardDeets(obj)
                  if cl == "Wild" then
                    local ok_p, pos = pcall(function() return obj.getPosition() end)
                    if ok_p and pos and math.abs(pos[lateralAxis] - avgLat) < 1.5 then
                      total = total + 1
                      wilds = wilds + 1
                    end
                  end
                end
              end)
            end
          end
        end
      end
    end
    return total, wilds
  end

  -- Mutable meld table: rank → {rank, obj, total, wilds, isNew, naturals}
  -- obj ~= nil  ↔  meld already existed on table before this turn
  local melds = {}

  for rank, meld in pairs(state.meldsByRank) do
    if rank ~= "3" then   -- red 3 stack is never a meld target
      local tot, wlds = getMeldInfo(rank)
      local isWildMeld = (rank == "2" or rank == "Joker")
      melds[rank] = {rank=rank, obj=meld.obj, total=tot, wilds=wlds,
                     isNew=false, isWildMeld=isWildMeld, naturals={}}
    end
  end
  for _, m in ipairs(meldPlan) do
    if isEligibleRank(m.rank) then
      if melds[m.rank] then
        melds[m.rank].total = melds[m.rank].total + m.count
      else
        melds[m.rank] = {rank=m.rank, obj=nil, total=m.count, wilds=0,
                         isNew=true, isWildMeld=false, naturals=m.cards or {}}
      end
    end
  end

  -- Gather wilds: 2s before Jokers
  local wildCards = {}
  for _, card in ipairs(state.hand) do
    if card.color == "Wild" then table.insert(wildCards, card) end
  end
  table.sort(wildCards, function(a, b)
    return (a.rank == "Joker" and 1 or 0) < (b.rank == "Joker" and 1 or 0)
  end)

  local nextWild = 1
  local allocs   = {}

  -- Place one wild into rank's meld. Returns false if no wild available or meld full.
  -- Special case: if the meld was created this turn (obj==nil) and already had one wild
  -- assigned (isNew==false after first assignWild call), append the wild to the most
  -- recent alloc for this rank rather than creating a new alloc with meldObj=nil that
  -- the executor cannot resolve.
  local function assignWild(rank, priority, reason)
    if nextWild > #wildCards then return false end
    local m = melds[rank]
    if not m or m.total >= 7 then return false end
    if not m.isWildMeld and m.wilds >= 2 then return false end
    m.total = m.total + 1
    m.wilds = m.wilds + 1
    local completesBook = (m.total >= 7)
    -- Merge into existing alloc when this is a follow-on wild for a Phase 1 new meld.
    if not m.isWildMeld and m.obj == nil and not m.isNew then
      for i = #allocs, 1, -1 do
        if allocs[i].rank == rank then
          table.insert(allocs[i].wilds, wildCards[nextWild])
          allocs[i].completesBook = allocs[i].completesBook or completesBook
          nextWild = nextWild + 1
          return true
        end
      end
    end
    local naturals = m.naturals or {}
    m.naturals = {}
    table.insert(allocs, {
      rank          = rank,
      meldObj       = m.obj,
      naturalCards  = naturals,
      wilds         = {wildCards[nextWild]},
      existingCount = m.total - 1,
      isNew         = m.isNew,
      priority      = priority,
      completesBook = completesBook,
      reason        = reason,
    })
    nextWild = nextWild + 1
    m.isNew  = false
    return true
  end

  local hasFoot   = state.hasFoot
  local otherFoot = state.otherFootOnTable

  -- Eligibility predicate: can this meld accept one more wild?
  --   Wild melds:              always (no 2-wild cap, up to 7).
  --   New rank melds (obj==nil): up to 2-wild cap, always extendable regardless of foot status.
  --   Pre-existing rank melds:  only when player has no foot (going-out scenario), under cap.
  -- NOTE: use m.obj==nil (not m.isNew) — isNew is reset by the first assignWild call.
  local function canExtend(m)
    if m.total >= 7 then return false end
    if m.isWildMeld then return true end   -- wild melds: no 2-wild cap
    if m.wilds >= 2  then return false end -- rank melds: enforce 2-wild cap
    if m.obj == nil  then return true end  -- new this turn: always extendable
    return not hasFoot                     -- pre-existing: only when going out
  end

  -- Rank priority for Phase 1 pair selection (highest value first → more points as a book).
  local rankPriority = {
    ["A"]=13,["K"]=12,["Q"]=11,["J"]=10,["10"]=9,
    ["9"]=8,["8"]=7,["7"]=6,["6"]=5,["5"]=4,["4"]=3,
  }

  -- Phase 1: hand pairs (exactly 2 naturals, no existing meld) → 1 wild → new rank meld of 3.
  -- When player has foot: only allowed if no other player has their foot, capped at 2 new melds.
  -- When player has no foot (going out): all pairs eligible, no cap.
  -- Pairs are processed highest-rank first so the cap eliminates low-value pairs, not high ones.
  local phase1Allowed = not hasFoot or not otherFoot
  local phase1Cap     = (hasFoot and not otherFoot) and 2 or math.huge
  if phase1Allowed then
    local eligiblePairs = {}
    for rank, count in pairs(state.handByRank) do
      if isEligibleRank(rank) and count == 2 and not melds[rank] then
        table.insert(eligiblePairs, rank)
      end
    end
    table.sort(eligiblePairs, function(a, b)
      return (rankPriority[a] or 0) > (rankPriority[b] or 0)
    end)
    local phase1Count = 0
    for _, rank in ipairs(eligiblePairs) do
      if nextWild > #wildCards or phase1Count >= phase1Cap then break end
      local naturalCards = {}
      for _, card in ipairs(state.hand) do
        if card.rank == rank then table.insert(naturalCards, card) end
      end
      melds[rank] = {rank=rank, obj=nil, total=2, wilds=0, isNew=true, isWildMeld=false, naturals=naturalCards}
      local label = (hasFoot and not otherFoot)
        and string.format("new meld: 2 × %s + 1 wild (foot-pickup play, %d/2)", rank, phase1Count+1)
        or  string.format("new meld: 2 × %s + 1 wild (hand pair)", rank)
      assignWild(rank, 1, label)
      phase1Count = phase1Count + 1
    end
  end

  -- Phase 2: pre-existing melds on table (obj ~= nil) → 1 wild each.
  -- Wild melds: always extend (preferred destination when hasFoot).
  -- Rank melds: only when player has no foot (going out scenario).
  do
    local preExisting = {}
    for rank, m in pairs(melds) do
      if m.obj ~= nil and canExtend(m) then table.insert(preExisting, rank) end
    end
    for _, rank in ipairs(preExisting) do
      if nextWild > #wildCards then break end
      local m = melds[rank]
      local label = m.isWildMeld
        and string.format("extends wild meld (%d cards on table)", m.total)
        or  string.format("extends own meld %s (%d cards on table)", rank, m.total)
      assignWild(rank, 2, label)
    end
  end

  -- Phase 3: remaining wilds → fewest-cards-first.
  -- Wild melds always eligible; rank melds only when player has no foot (via canExtend).
  while nextWild <= #wildCards do
    local candidates = {}
    for _, m in pairs(melds) do
      if canExtend(m) then table.insert(candidates, m) end
    end
    if #candidates == 0 then break end
    table.sort(candidates, function(a, b) return a.total < b.total end)
    local placed = false
    for _, m in ipairs(candidates) do
      if canExtend(m) then  -- re-check: assignWild may have updated m.wilds/m.total
        placed = assignWild(m.rank, 3,
          string.format("extends %s (%d cards, fewest-first)",
            m.isWildMeld and "wild meld" or ("meld "..m.rank), m.total))
        if placed then break end
      end
    end
    if not placed then break end
  end

  -- Phase 4: if 3+ wilds still unallocated and no wild meld exists on the table,
  -- bundle them into a new pure wild meld.
  local wildsLeft4 = #wildCards - nextWild + 1
  if wildsLeft4 >= 3 and not melds["2"] and not melds["Joker"] then
    local assigned = {}
    while nextWild <= #wildCards do
      table.insert(assigned, wildCards[nextWild])
      nextWild = nextWild + 1
    end
    table.insert(allocs, {
      rank         = "__wild__",
      meldObj      = nil,
      naturalCards = {},
      wilds        = assigned,
      existingCount = 0,
      isNew        = true,
      isWildMeld   = true,
      priority     = 4,
      completesBook = (#assigned >= 7),
      reason       = string.format("new wild meld: %d wilds", #assigned),
    })
  end

  return allocs
end

-- ----------------------------------------------------------------------------
-- Plan assembler
-- ----------------------------------------------------------------------------

-- Builds a complete TurnPlan for sColor.
-- TurnPlan fields: color, state, goOut, melds, wildAllocs, discard, log[], ok
function buildTurnPlan(sColor)
  local log = {}
  local function L(msg) table.insert(log, msg) end

  local state = snapshotState(sColor)

  L(string.format("=== Turn Plan for %s ===", sColor))
  L(string.format("Hand: %d cards (%d wilds)", state.handCount, state.wildCount))
  L(string.format("Books: %d red, %d black, %d wild",
    state.bookCounts.red, state.bookCounts.black, state.bookCounts.wild))
  L(string.format("Foot on table: %s", state.hasFoot and "yes" or "no"))
  L(string.format("Melds on table: %d", #state.melds))

  local goOut = evalGoOut(state)
  L(string.format("Go out: %s — %s", goOut.should and "YES" or "no", goOut.reason))

  local melds = evalMeldsToPlay(state)
  if #melds == 0 then
    L("Natural melds: nothing eligible (need 3+ of a rank)")
  else
    for _, m in ipairs(melds) do
      L(string.format("  [p%d] %s — %s", m.priority, m.rank, m.reason))
    end
  end

  -- Compute wild allocs now (needed for go-out projection), but only keep them
  -- if the plan actually results in going out this turn.
  local wildAllocs = evalWildAllocations(state, melds)

  local projRed   = state.bookCounts.red
  local projBlack = state.bookCounts.black
  for _, m  in ipairs(melds)      do if m.priority  == 1 then projRed   = projRed   + 1 end end
  for _, wa in ipairs(wildAllocs) do if wa.completesBook then projBlack = projBlack + 1 end end

  local cardsConsumed = 0
  for _, m in ipairs(melds) do cardsConsumed = cardsConsumed + m.count end
  for _, wa in ipairs(wildAllocs) do
    cardsConsumed = cardsConsumed + #wa.wilds + #wa.naturalCards
  end
  local projHandCount = state.handCount - cardsConsumed

  if not state.hasFoot and projHandCount == 0 and projRed >= 2 and projBlack >= 2 then
    goOut = {should=true, reason=string.format(
      "empties hand after plays (proj red=%d black=%d)", projRed, projBlack)}
    L("Go out: YES (after plays) — " .. goOut.reason)
  elseif not state.hasFoot and projRed >= 2 and projBlack >= 2 and not goOut.should then
    L(string.format("Projected go-out: books met (red=%d black=%d) but %d cards remain",
      projRed, projBlack, projHandCount))
  end

  -- Wild plays are allowed when ALL of:
  --   (a) the plays would empty the hand (projHandCount <= 1, last card = discard), AND
  --   (b) no other player has their foot on the table (end-game), OR going out this turn.
  -- Wild cards are NEVER discarded unless all remaining cards are wild (evalDiscard rule 8).
  local allowWilds = (projHandCount <= 1) and
    (not state.otherFootOnTable or goOut.should)

  if not allowWilds then
    if #wildAllocs > 0 then
      local why
      if projHandCount > 1 then
        why = "plays would not empty hand"
      elseif state.otherFootOnTable then
        why = "other players still have foot on table"
      else
        why = "conditions not met"
      end
      L(string.format("Wild plays: suppressed (%d alloc(s) — %s)", #wildAllocs, why))
    elseif state.wildCount > 0 then
      L("Wild plays: held — conditions not met")
    end
    wildAllocs = {}
  else
    if #wildAllocs == 0 then
      if state.wildCount > 0 then L("Wild plays: no useful allocation found") end
    else
      for _, wa in ipairs(wildAllocs) do
        L(string.format("  [w%d] %s — %s", wa.priority, wa.rank, wa.reason))
      end
    end
  end

  local discard
  if goOut.should then
    discard = {card=nil, reason="going out — no discard needed"}
    L("Discard: none (going out)")
  else
    discard = evalDiscard(state, melds, wildAllocs)
    if discard.card then
      L(string.format("Discard: %s %s — %s",
        discard.card.rank, discard.card.suit or "?", discard.reason))
    else
      L("Discard: " .. discard.reason)
    end
  end

  return {
    color=sColor, state=state, goOut=goOut,
    melds=melds, wildAllocs=wildAllocs, discard=discard,
    log=log, ok=true,
  }
end

-- ----------------------------------------------------------------------------
-- Executor
-- ----------------------------------------------------------------------------

-- Executes a TurnPlan: plays melds in priority order, then discards.
-- Melds are driven by layoutHandRank (existing animation pipeline).
-- Discard fires after all melds have had time to animate.
function executeTurnPlan(plan)
  if not plan.ok then return end
  local sColor = plan.color

  -- Estimate total meld animation time so discard fires after
  local totalMeldTime = 0
  for _, m in ipairs(plan.melds) do
    -- Each rank: cards * 0.15s stagger + 0.5s spread4 buffer (from executeLayoutRank)
    totalMeldTime = totalMeldTime + (m.count * 0.15) + 0.75
  end

  -- Play each eligible meld rank (layoutHandRank handles its own timing)
  for _, m in ipairs(plan.melds) do
    layoutHandRank(sColor, m.rank)
  end

  -- Discard after melds finish (skip if going out with empty hand)
  if plan.discard.card and not plan.goOut.should then
    Wait.time(function()
      pcall(function()
        plan.discard.card.obj.setPositionSmooth(obj_Zone_Discard.getPosition())
        plan.discard.card.obj.setRotation({0, 180, 0})
      end)
    end, totalMeldTime + 0.5)
  end
end

-- ----------------------------------------------------------------------------
-- Debug helper
-- ----------------------------------------------------------------------------

-- Print the plan log to a specific player's chat window.
function printTurnPlan(plan, sColor)
  for _, line in ipairs(plan.log) do
    printToColor(line, sColor)
  end
end
