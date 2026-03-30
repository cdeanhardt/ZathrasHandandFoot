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

  return {
    color       = sColor,
    hand        = hand,
    handCount   = #hand,
    handByRank  = handByRank,
    wildCount   = wildCount,
    melds       = melds,
    meldsByRank = meldsByRank,
    books       = books,
    bookCounts  = bookCounts,
    hasFoot     = playerHasFoot(sColor),
    canGoOut    = (bookCounts.red >= 2 and bookCounts.black >= 2),
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
-- Each returned entry: {rank, meldObj, naturalCards, wilds, existingCount, isNew, priority, reason}
-- Priority 1 = completes book; Priority 2 = new meld with 2 naturals + 1 wild.
function evalWildAllocations(state, meldPlan)
  if state.wildCount == 0 then return {} end

  -- Count all cards in a meld column of `rank`, including wilds already mixed in.
  -- Stacked Decks: getQuantity() includes wilds. Books (qty>=7) excluded.
  -- Spread melds: count natural cards + wild Cards at the same lateral position.
  local rotY       = getPlayerRotY(state.color)
  local decode     = gt_DECODE_DIR[rotY]
  local lateralAxis = decode and decode[1] or "x"

  local function countMeldCards(rank)
    local naturalObjs = getTableCardsOfRank(state.color, rank)
    if #naturalObjs == 0 then return 0 end
    local total = 0
    local spreadLats = {}
    for _, obj in ipairs(naturalObjs) do
      if obj.tag == "Deck" then
        local ok, qty = pcall(function() return obj.getQuantity() end)
        local q = (ok and qty and qty >= 1) and qty or 1
        if q < 7 then total = total + q end
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
                    end
                  end
                end
              end)
            end
          end
        end
      end
    end
    return total
  end

  -- projected is a LIST (not map) so book+meld of same rank are separate entries.
  local projected = {}
  for rank, meld in pairs(state.meldsByRank) do
    local cnt = countMeldCards(rank)
    if cnt > 0 then
      table.insert(projected, {rank=rank, count=cnt, obj=meld.obj, isBook=false})
    end
  end
  for _, bookList in pairs(state.books) do
    for _, book in ipairs(bookList) do
      if book.rank then
        local ok, qty = pcall(function() return book.obj.getQuantity() end)
        table.insert(projected, {
          rank=book.rank, count=(ok and qty and qty >= 1) and qty or 7,
          obj=book.obj, isBook=true,
        })
      end
    end
  end
  for _, m in ipairs(meldPlan) do
    local found = false
    for _, p in ipairs(projected) do
      if p.rank == m.rank and not p.isBook then p.count = p.count + m.count; found = true; break end
    end
    if not found then
      table.insert(projected, {rank=m.rank, count=m.count, obj=nil, isBook=false})
    end
  end

  local wildCards = {}
  for _, card in ipairs(state.hand) do
    if card.color == "Wild" then table.insert(wildCards, card) end
  end
  table.sort(wildCards, function(a, b)
    return ((a.rank == "Joker") and 1 or 0) < ((b.rank == "Joker") and 1 or 0)
  end)

  local wildsLeft = #wildCards
  local nextWild  = 1
  local allocs    = {}

  local completable = {}
  for i, info in ipairs(projected) do
    if not info.isBook and info.count > 0 and info.count < 7 and isEligibleRank(info.rank) then
      local need = 7 - info.count
      if need <= wildsLeft then
        table.insert(completable, {idx=i, rank=info.rank, count=info.count, obj=info.obj, need=need})
      end
    end
  end
  table.sort(completable, function(a, b) return a.need < b.need end)

  for _, target in ipairs(completable) do
    if wildsLeft < target.need then break end
    if not projected[target.idx].isBook then
      local assigned = {}
      for i = 1, target.need do
        table.insert(assigned, wildCards[nextWild]); nextWild = nextWild + 1
      end
      wildsLeft = wildsLeft - target.need
      table.insert(allocs, {
        rank=target.rank, meldObj=target.obj, naturalCards={}, wilds=assigned,
        existingCount=target.count, isNew=false, priority=1,
        reason=string.format("completes book: %d + %d wild = 7", target.count, target.need),
      })
      projected[target.idx].count  = 7
      projected[target.idx].isBook = true
    end
  end

  -- hasMeld at broader scope so Phase 2 and go-out rebalance share it.
  local hasMeld = {}
  for _, p in ipairs(projected) do if not p.isBook then hasMeld[p.rank] = true end end

  if wildsLeft >= 1 then
    for rank, count in pairs(state.handByRank) do
      if wildsLeft >= 1 and isEligibleRank(rank) and not hasMeld[rank] and count == 2 then
        local assigned = {wildCards[nextWild]}; nextWild = nextWild + 1; wildsLeft = wildsLeft - 1
        local naturalCards = {}
        for _, card in ipairs(state.hand) do
          if card.rank == rank then table.insert(naturalCards, card) end
        end
        table.insert(allocs, {
          rank=rank, meldObj=nil, naturalCards=naturalCards, wilds=assigned,
          existingCount=0, isNew=true, priority=2,
          reason=string.format("new meld: 2 × %s + 1 wild", rank),
        })
        table.insert(projected, {rank=rank, count=3, obj=nil, isBook=false})
        hasMeld[rank] = true
      end
    end
  end

  -- Go-out rebalance: if Phase 1 exhausted all wilds but 2-natural groups remain,
  -- and projBlack > 2, sacrifice one Phase 1 completion to fund each group.
  if wildsLeft == 0 and not state.hasFoot then
    local projBlack = state.bookCounts.black
    for _, a in ipairs(allocs) do if a.priority == 1 then projBlack = projBlack + 1 end end
    if projBlack > 2 then
      local consumedRanks = {}
      for _, m in ipairs(meldPlan) do consumedRanks[m.rank] = true end
      for _, a in ipairs(allocs) do
        for _, c in ipairs(a.naturalCards) do consumedRanks[c.rank] = true end
      end
      for rank, count in pairs(state.handByRank) do
        if projBlack <= 2 then break end
        if count == 2 and isEligibleRank(rank)
           and not consumedRanks[rank] and not hasMeld[rank] then
          local sacIdx, sacNeed = nil, 0
          for i, a in ipairs(allocs) do
            if a.priority == 1 and #a.wilds > sacNeed then
              sacNeed = #a.wilds; sacIdx = i
            end
          end
          if sacIdx then
            local sacrificed = table.remove(allocs, sacIdx)
            projBlack = projBlack - 1
            local naturalCards = {}
            for _, card in ipairs(state.hand) do
              if card.rank == rank then table.insert(naturalCards, card) end
            end
            table.insert(allocs, {
              rank=rank, meldObj=nil, naturalCards=naturalCards,
              wilds={sacrificed.wilds[1]}, existingCount=0, isNew=true, priority=2,
              reason=string.format("new meld: 2 × %s + 1 wild (go-out play)", rank),
            })
            hasMeld[rank] = true; consumedRanks[rank] = true
          end
        end
      end
    end
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

  local wildAllocs = evalWildAllocations(state, melds)
  if #wildAllocs == 0 then
    if state.wildCount > 0 then L("Wild plays: no useful allocation found") end
  else
    for _, wa in ipairs(wildAllocs) do
      L(string.format("  [w%d] %s — %s", wa.priority, wa.rank, wa.reason))
    end
  end

  local projRed   = state.bookCounts.red
  local projBlack = state.bookCounts.black
  for _, m  in ipairs(melds)      do if m.priority  == 1 then projRed   = projRed   + 1 end end
  for _, wa in ipairs(wildAllocs) do if wa.priority == 1 then projBlack = projBlack + 1 end end

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
