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
  local hasRed     = false
  local hasBlack   = false

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
        if clr == "Red"   then hasRed   = true end
        if clr == "Black" then hasBlack = true end
      end
    end
  end

  if mixed then return nil end           -- inconsistent ranks
  if wildCount == qty then return "wild" end
  -- Color-balance rule: rank books require ≥1 red-suit and ≥1 black-suit natural card.
  if not (hasRed and hasBlack) then return nil end
  if wildCount > 0 then return "black" end
  return "red"
end

-- ----------------------------------------------------------------------------
-- Shared helpers  (used by multiple evaluators below)
-- ----------------------------------------------------------------------------

-- Sort wild cards in-place: 2s before Jokers.
local function sortWilds(cards)
  table.sort(cards, function(a, b)
    return (a.rank == "Joker" and 1 or 0) < (b.rank == "Joker" and 1 or 0)
  end)
end

-- True when the player already has at least one eligible meld or any book on the table.
local function hasExistingMeldsOrBooks(state)
  if #state.books.red + #state.books.black + #state.books.wild > 0 then return true end
  -- A valid meld requires >=3 cards; a single stray card in the zone does not count.
  for rank, meld in pairs(state.meldsByRank) do
    if isEligibleRank(rank) and (meld.count or 1) >= 3 then return true end
  end
  return false
end

-- Count wild cards in a Card or Deck TTS object.  Safe: never throws.
-- When a Deck's contents cannot be read (getObjects fails), returns a conservative
-- upper bound (min(qty, 2)) so callers never under-report and exceed the 2-wild cap.
local function countMeldWilds(obj)
  if not obj then return 0 end
  local count = 0
  pcall(function()
    if obj.tag == "Card" then
      local cl = cardDeets(obj)
      if cl == "Wild" then count = 1 end
    elseif obj.tag == "Deck" then
      local ok, cards = pcall(function() return obj.getObjects() end)
      if ok and cards then
        for _, info in ipairs(cards) do
          local nm = info.description and string.match(info.description, "^([%a%d]+)") or ""
          if nm == "2" or nm == "Joker" then count = count + 1 end
        end
      else
        -- Cannot inspect deck; report conservative maximum to avoid exceeding the cap.
        local ok2, qty = pcall(function() return obj.getQuantity() end)
        count = (ok2 and qty and qty >= 1) and math.min(qty, 2) or 2
      end
    end
  end)
  return count
end

-- Returns {hasRed=bool, hasBlack=bool} indicating whether an existing meld
-- (Card or Deck TTS object) contains at least one red-suit and one black-suit
-- natural card.  Wild cards (2s/Jokers) are not counted toward either color.
local function getMeldColors(obj)
  local hasRed, hasBlack = false, false
  if not obj then return {hasRed=false, hasBlack=false} end
  pcall(function()
    if obj.tag == "Card" then
      local cl = cardDeets(obj)
      if cl == "Red"   then hasRed   = true
      elseif cl == "Black" then hasBlack = true end
    elseif obj.tag == "Deck" then
      local ok, cards = pcall(function() return obj.getObjects() end)
      if ok and cards then
        for _, c in ipairs(cards) do
          pcall(function()
            local cl, _, _ = cardDeets(c)
            if cl == "Red"   then hasRed   = true
            elseif cl == "Black" then hasBlack = true end
          end)
        end
      end
    end
  end)
  return {hasRed=hasRed, hasBlack=hasBlack}
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
      if meld.rank then
        -- Count cards in this TTS object (Card=1, Deck=quantity).
        local objCount = 1
        if meld.obj and meld.obj.tag == "Deck" then
          local ok, qty = pcall(function() return meld.obj.getQuantity() end)
          objCount = (ok and qty and qty >= 1) and qty or 1
        end
        if not meldsByRank[meld.rank] then
          meldsByRank[meld.rank] = {rank=meld.rank, obj=meld.obj, count=objCount,
                                    isBook=false, pos=meld.pos, colors={hasRed=false, hasBlack=false}}
        else
          -- Additional spread Card objects of the same rank: accumulate count.
          meldsByRank[meld.rank].count = meldsByRank[meld.rank].count + objCount
        end
        -- Accumulate color balance from ALL objects of this rank (handles spread cards
        -- where each card is a separate TTS object and no single obj shows both colors).
        local mc = getMeldColors(meld.obj)
        if mc.hasRed   then meldsByRank[meld.rank].colors.hasRed   = true end
        if mc.hasBlack then meldsByRank[meld.rank].colors.hasBlack = true end
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
    existingByRank[rank] = {obj=meld.obj, count=meld.count or safeQty(meld.obj, 1), isBook=false, colors=meld.colors}
  end
  for _, bookList in pairs(state.books) do
    for _, book in ipairs(bookList) do
      if book.rank and not existingByRank[book.rank] then
        existingByRank[book.rank] = {obj=book.obj, count=safeQty(book.obj, 7), isBook=true}
      end
    end
  end

  -- Count open melds that are exactly 6 cards — each is "1 wild away from a black book."
  -- Used below to allow an extra red book when enough near-black candidates remain.
  local nearBlackCount = 0
  for rank, meld in pairs(state.meldsByRank) do
    if meld.count == 6 then nearBlackCount = nearBlackCount + 1 end
  end

  -- Priority tiers:
  --   1 = complete a red book (all natural cards, no wilds in existing meld)
  --   2 = complete a black book (existing meld has ≥1 wild)
  --   3 = extend an existing meld without completing it
  --   4 = start a new meld
  -- Exception: after foot pickup, suppress priority-1 plays when red books > 1
  -- but black books < 2 — hold that rank back so a wild completes it as a
  -- black book instead.  Before foot pickup this restriction is lifted (still
  -- in the first half of the hand; accumulating naturals is fine).
  -- Once black books ≥ 2 the default priority ordering already favours red
  -- book completion (p1) over black (p2), so no extra logic is needed.
  local plans = {}
  for rank, count in pairs(state.handByRank) do
    if isEligibleRank(rank) then
      local existing      = existingByRank[rank]
      local existingCount = existing and existing.count or 0

      -- Include if we can start a new meld (count>=3) OR extend any existing meld/book (any count).
      if count >= 3 or existing then
        local projected = existingCount + count
        local priority, reason, meldColor
        local skip = false

        -- Pre-compute projected color balance (existing meld naturals + hand cards of this rank).
        -- Use colors accumulated across ALL spread objects of this rank (set in snapshotState).
        local existingColors = existing and (existing.colors or getMeldColors(existing.obj)) or {hasRed=false, hasBlack=false}
        local projHasRed  = existingColors.hasRed
        local projHasBlack = existingColors.hasBlack
        for _, hc in ipairs(state.hand) do
          if hc.rank == rank then
            if hc.color == "Red"   then projHasRed   = true end
            if hc.color == "Black" then projHasBlack = true end
          end
        end
        local projColorBalanced = projHasRed and projHasBlack

        if existing and existingCount < 7 and projected >= 7 then
          local existingWilds = countMeldWilds(existing.obj)
          local isRedBook = (existingWilds == 0)
          if not projColorBalanced then
            -- Would reach 7 cards but natural cards lack both colors — not a book yet.
            -- Treat as a plain extension so priority ordering is correct.
            meldColor = (existingWilds > 0) and "black" or "red"
            priority  = 3
            reason = string.format("extends %s to %d (needs both colors to book)",
              meldColor .. " meld", projected)
          elseif isRedBook and not state.hasFoot
              and state.bookCounts.red > 1 and state.bookCounts.black < 2 then
            -- Default: suppress making another red book while still needing black books.
            -- Exception: if this meld is currently a 6-card near-black candidate, allow
            -- the red book only when enough OTHER near-black melds remain to cover the
            -- remaining black-book requirement.
            local blackBooksNeeded = 2 - state.bookCounts.black
            local thisIsNearBlack  = (existingCount == 6)
            local remainNearBlack  = nearBlackCount - (thisIsNearBlack and 1 or 0)
            if thisIsNearBlack and remainNearBlack >= blackBooksNeeded then
              priority  = 1
              meldColor = "red"
              reason = string.format(
                "completes red book: %d + %d = 7 (ok: %d near-black remain ≥ %d needed)",
                existingCount, count, remainNearBlack, blackBooksNeeded)
            else
              skip = true
            end
          else
            priority  = isRedBook and 1 or 2
            meldColor = isRedBook and "red" or "black"
            reason = string.format("completes %s book: %d + %d = %d",
              meldColor, existingCount, count, projected)
          end
        elseif existing then
          local existingWilds = countMeldWilds(existing.obj)
          meldColor = (existingWilds > 0) and "black" or "red"
          -- Suppress extending natural OPEN melds toward a 3rd red book.
          -- Extending a completed book is fine — that book is already counted.
          if not existing.isBook and existingWilds == 0 and not state.hasFoot
             and state.bookCounts.red >= 2 and state.bookCounts.black < 2 then
            local wildsAvail = math.min(state.wildCount, 2 - existingWilds)
            if existingCount + count + wildsAvail >= 7 and projColorBalanced then
              priority  = 2
              meldColor = "red"
              reason = string.format("completes black book with wilds: %d + %d + %d = 7",
                existingCount, count, wildsAvail)
            else
              -- Can't complete a book this turn — but still extend the meld (don't skip).
              priority = 3
              reason = string.format("extends red meld: %d on table + %d from hand (black book later)",
                existingCount, count)
            end
          else
            priority = 3
            local target = existing.isBook and (meldColor .. " book") or (meldColor .. " meld")
            reason = string.format("extends %s: %d on table + %d from hand",
              target, existingCount, count)
          end
        else
          meldColor = "red"    -- new melds are always all naturals (red)
          priority  = 4
          reason = string.format("new red meld: %d cards of rank %s", count, rank)
        end

        if not skip then
          local cards = {}
          for _, card in ipairs(state.hand) do
            if card.rank == rank then table.insert(cards, card) end
          end
          -- For book-completing plays (p1/p2) with an existing meld, only play the
          -- minimum cards needed to reach 7.  Excess cards stay in hand for discard.
          local playCount = count
          if priority <= 2 and existingCount > 0 and projected > 7 then
            playCount = 7 - existingCount
          end
          local partial = (playCount < count)
          table.insert(plans, {
            rank=rank, cards=cards, count=playCount,
            existingCount=existingCount, priority=priority,
            meldColor=meldColor, reason=reason,
            partial=partial,
          })
        end
      end
    end
  end

  -- Sort: priority first, then larger melds before smaller at same priority
  table.sort(plans, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.count > b.count
  end)

  -- Opening meld check: if the player has no existing melds or books, the total
  -- point value of all planned new melds must meet the hand's minimum threshold.
  -- If the threshold isn't met, suppress all melds (can't open yet).
  -- Exclude red-3 stacks (rank "3") — they are not real melds for opening purposes.
  if not hasExistingMeldsOrBooks(state) then
    local minimum = gi_OPENING_MELD_MIN[giHand] or 50
    local totalPts = 0
    for _, plan in ipairs(plans) do
      for _, card in ipairs(plan.cards) do
        if card.rank ~= "3" then   -- red 3s never count toward opening minimum
          totalPts = totalPts + scoreCard(card.obj)
        end
      end
    end
    if totalPts < minimum then
      return {}
    end
  end

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
--  2.5 Meld protection: cards whose rank has an existing meld on the table are
--      protected — prefer unprotected cards first.  Only discard a protected card
--      if no unprotected non-wild candidates remain.
--  3. Minimum count: singletons before pairs before triples, etc.
--  4. Lowest strata within min-count: strata 1 (4-7) → 2 (8-K) → 3 (A).
--  5. Prefer same-color sets (all-Red or all-Black) within chosen strata/count.
--  6. Within chosen set, prefer the card whose removal leaves ≥1 of each color.
--  7. Tiebreaker: lowest rank-slot within the strata (4 before 7, 8 before K).
--  8. Wild fallback (no non-wilds left): 2s before Jokers.
--  9. Absolute fallback: first remaining card.
-- wildAllocs is optional — the list from evalWildAllocations.
function evalDiscard(state, meldPlan, wildAllocs)
  -- Count how many cards of each rank the meld plan consumes.
  -- Partial melds (m.count < all of that rank) must only exclude m.count cards,
  -- leaving the excess available as discard candidates.
  local meldingCount = {}
  for _, m in ipairs(meldPlan) do
    meldingCount[m.rank] = (meldingCount[m.rank] or 0) + m.count
  end

  local playedObjs = {}
  if wildAllocs then
    for _, wa in ipairs(wildAllocs) do
      for _, card in ipairs(wa.wilds)        do playedObjs[card.obj] = true end
      for _, card in ipairs(wa.naturalCards) do playedObjs[card.obj] = true end
    end
  end

  local remaining = {}
  local rankUsed = {}   -- how many cards of each rank have been consumed by melds so far
  for _, card in ipairs(state.hand) do
    local needed = meldingCount[card.rank] or 0
    local used   = rankUsed[card.rank] or 0
    if used < needed then
      rankUsed[card.rank] = used + 1   -- consume this card for the meld, skip it
    elseif not playedObjs[card.obj] then
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

  -- RULE 2: Partition into candidates (non-wild, non-3) and wilds.
  local candidates, wilds = {}, {}
  for _, card in ipairs(remaining) do
    if card.color == "Wild" then
      table.insert(wilds, card)
    elseif card.rank ~= "3" then    -- red 3s silently skipped
      table.insert(candidates, card)
    end
  end

  -- RULE 8: Wild fallback only when no candidates remain.
  if #candidates == 0 then
    sortWilds(wilds)
    if #wilds > 0 then
      return {card=wilds[1], reason=string.format("wild %s (no non-wilds remain — 2s before Jokers)", wilds[1].rank)}
    end
    return {card=remaining[1], reason="absolute fallback"}
  end

  -- RULE 2.5: Meld protection + RULE 2.6: Black-book-candidate hold.
  --
  -- holdRanks: when the foot has been picked up, we already have 2+ red books,
  -- and we still need 2 black books — ranks with existing all-natural (red) melds
  -- on the table should NOT be discarded.  We're saving those cards so a wild can
  -- convert the meld to a black meld and it can eventually complete as a black book.
  --
  -- Exception A (surplus): if 2+ cards of a held rank remain after melds, we can
  -- discard one (keeps ≥1 on hand to later extend the meld).
  -- Exception B (wild fallback): if the only non-wild candidates left are held
  -- singletons, we discard one rather than throw away a wild card.
  local holdRanks = {}
  if not state.hasFoot and state.bookCounts.red >= 2 and state.bookCounts.black < 2 then
    local seen = {}
    for _, card in ipairs(candidates) do
      local rank = card.rank
      if not seen[rank] and state.meldsByRank[rank] then
        seen[rank] = true
        local w = 0
        pcall(function() w = countMeldWilds(state.meldsByRank[rank].obj) end)
        if w == 0 then holdRanks[rank] = true end
      end
    end
  end

  -- Count how many of each held rank remain in candidates (for surplus detection).
  local heldCount = {}
  for _, card in ipairs(candidates) do
    if holdRanks[card.rank] then
      heldCount[card.rank] = (heldCount[card.rank] or 0) + 1
    end
  end

  -- Four buckets (tried in order):
  --   unprotected    — rank has no meld on table and is not held
  --   surplus        — held rank with 2+ copies remaining; can discard one, keep the rest
  --   protected      — rank has meld but is not held for black book
  --   superProtected — held rank with exactly 1 copy; discard only to avoid wild discard
  local unprotected, surplus, protected, superProtected = {}, {}, {}, {}
  for _, card in ipairs(candidates) do
    if holdRanks[card.rank] then
      if heldCount[card.rank] >= 2 then
        table.insert(surplus, card)
      else
        table.insert(superProtected, card)
      end
    elseif state.meldsByRank[card.rank] then
      table.insert(protected, card)
    else
      table.insert(unprotected, card)
    end
  end

  -- Helper: apply rules 3-7 to a flat card list; returns {card, reason} or nil.
  local function isMono(g)
    local c = nil
    for _, card in ipairs(g.cards) do
      if c == nil then c = card.color
      elseif card.color ~= c then return false end
    end
    return true
  end
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

  local function pickBest(cardList, tag)
    if #cardList == 0 then return nil end

    -- Group by rank.
    local byRank = {}
    for _, card in ipairs(cardList) do
      if not byRank[card.rank] then byRank[card.rank] = {rank=card.rank, cards={}} end
      table.insert(byRank[card.rank].cards, card)
    end
    local groups = {}
    for _, g in pairs(byRank) do table.insert(groups, g) end

    -- RULE 4: Strata is the primary filter — lowest strata discarded first.
    -- Aces (strata 3) are always held over 8–K (strata 2) and 4–7 (strata 1),
    -- even if the Ace is a singleton.  Wilds are handled separately (fallback only).
    local minStrata = math.huge
    for _, g in ipairs(groups) do
      local s = gt_DISCARD_STRATA[g.rank] or 2
      if s < minStrata then minStrata = s end
    end
    local atMinStrata = {}
    for _, g in ipairs(groups) do
      if (gt_DISCARD_STRATA[g.rank] or 2) == minStrata then
        table.insert(atMinStrata, g)
      end
    end

    -- RULE 3: Within the lowest strata, prefer ranks with fewest copies in hand.
    local minCount = math.huge
    for _, g in ipairs(atMinStrata) do
      if #g.cards < minCount then minCount = #g.cards end
    end
    local atMinCount = {}
    for _, g in ipairs(atMinStrata) do
      if #g.cards == minCount then table.insert(atMinCount, g) end
    end

    -- RULE 7: Lowest rank within strata/count wins.
    table.sort(atMinCount, function(a, b)
      return (gt_RANK_WITHIN_STRATA[a.rank] or 0) < (gt_RANK_WITHIN_STRATA[b.rank] or 0)
    end)
    local chosen = atMinCount[1]

    -- RULE 6: Within chosen rank group, prefer the card that preserves color balance.
    local pick
    if #chosen.cards == 1 then
      pick = chosen.cards[1]
    else
      for _, card in ipairs(chosen.cards) do
        if removingKeepsBalance(card, chosen.cards) then pick = card; break end
      end
      if not pick then pick = chosen.cards[1] end
    end

    local reason = string.format(
      "%s — strata=%d count=%d rank-slot=%d%s",
      chosen.rank, minStrata, minCount,
      gt_RANK_WITHIN_STRATA[chosen.rank] or 0,
      tag or "")
    return {card=pick, reason=reason}
  end

  -- Try buckets in priority order (Rules 2.5 / 2.6).
  local result = pickBest(unprotected, "")
  if not result then result = pickBest(surplus,        " [held surplus — keeping ≥1 for black book]") end
  if not result then result = pickBest(protected,      " [meld-protected — no unprotected left]") end
  if not result then result = pickBest(superProtected, " [held for black book — last non-wild option]") end
  if result then return result end

  -- RULE 8: Wild fallback (only reached if all candidates were exhausted above).
  sortWilds(wilds)
  if #wilds > 0 then
    return {card=wilds[1], reason=string.format("wild %s (no non-wilds remain — 2s before Jokers)", wilds[1].rank)}
  end
  return {card=remaining[1], reason="absolute fallback"}
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
function evalWildAllocations(state, meldPlan, logFn, projRed)
  local L = logFn or function() end
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
          else
            -- Cannot inspect deck; assume maximum wilds to avoid exceeding the 2-wild cap.
            wilds = wilds + math.min(q, 2)
          end
        end
      else
        total = total + 1
        local ok, pos = pcall(function() return obj.getPosition() end)
        if ok and pos then table.insert(spreadLats, pos[lateralAxis]) end
      end
    end
    -- Secondary scan: find wild cards (2s/Jokers) physically mixed into a NATURAL rank meld.
    -- Skip for wild ranks ("2"/"Joker") — their cards are already in naturalObjs and would
    -- be double-counted, inflating total past 7 and masking an incomplete wild meld.
    local isWildRank = (rank == "2" or rank == "Joker")
    if #spreadLats > 0 and not isWildRank then
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

  -- Ranks whose natural cards will be placed by layoutHandRank (executeTurnPlan's
  -- natural-meld loop).  Wild allocs for these ranks must NOT re-place those cards.
  local meldPlanRanks = {}
  for _, m in ipairs(meldPlan) do meldPlanRanks[m.rank] = true end

  -- Ranks that already have a completed red book on the table.
  -- Wilds may NEVER be added to a red book (it would convert it to a black book).
  local redBookRanks = {}
  for _, book in ipairs(state.books.red) do
    if book.rank then redBookRanks[book.rank] = true end
  end

  -- Mutable meld table: rank → {rank, obj, total, wilds, isNew, naturals}
  -- obj ~= nil  ↔  meld already existed on table before this turn
  local melds = {}

  for rank, meld in pairs(state.meldsByRank) do
    if rank ~= "3" then   -- red 3 stack is never a meld target
      local tot, wlds = getMeldInfo(rank)
      local isWildMeld = (rank == "2" or rank == "Joker")
      -- Use colors accumulated across all spread objects (set in snapshotState).
      local colors = isWildMeld and {hasRed=false, hasBlack=false} or (meld.colors or getMeldColors(meld.obj))
      melds[rank] = {rank=rank, obj=meld.obj, total=tot, wilds=wlds,
                     isNew=false, isWildMeld=isWildMeld, naturals={}, colors=colors}
    end
  end
  for _, m in ipairs(meldPlan) do
    if isEligibleRank(m.rank) and not redBookRanks[m.rank] then
      if melds[m.rank] then
        -- Merge in color info from the incoming hand cards.
        local mc = melds[m.rank].colors
        for _, hc in ipairs(m.cards or {}) do
          if hc.color == "Red"   then mc.hasRed   = true end
          if hc.color == "Black" then mc.hasBlack = true end
        end
        melds[m.rank].total = melds[m.rank].total + m.count
      else
        -- New meld: compute colors from the hand cards being played.
        local mc = {hasRed=false, hasBlack=false}
        for _, hc in ipairs(m.cards or {}) do
          if hc.color == "Red"   then mc.hasRed   = true end
          if hc.color == "Black" then mc.hasBlack = true end
        end
        melds[m.rank] = {rank=m.rank, obj=nil, total=m.count, wilds=0,
                         isNew=true, isWildMeld=false, naturals=m.cards or {}, colors=mc}
      end
    end
  end

  -- *** These must be defined BEFORE canEmptyWithWilds / canEmptyViaWildMeld ***
  local hasFoot       = state.hasFoot
  local otherFoot     = state.otherFootOnTable
  local needBlackBook = state.bookCounts.black < 2

  -- How many wild-assisted pair melds are acceptable when emptying the hand to pick up the
  -- foot.  Scales with game pressure from the other player(s):
  --   otherFoot=true  (other still has foot on table)  → conservative: 1 pair
  --   otherFoot=false (other has picked up foot)       → moderate: 2 pairs
  --   otherFoot=false AND other player has 3+ books    → aggressive: 3 pairs
  --   hasFoot=false   (self going out)                 → no cap
  local emptyHandCap
  if not hasFoot then
    emptyHandCap = math.huge        -- going-out scenario: no restriction
  elseif otherFoot then
    emptyHandCap = 1                -- other player not yet in foot: be conservative
  else
    local otherBooks = 0
    pcall(function()
      for _, color in ipairs(playerList or {}) do
        if color ~= state.color and not playerHasFoot(color) then
          for _, m in ipairs(getMelds(color)) do
            if m.isBook and classifyBook(m.obj) then otherBooks = otherBooks + 1 end
          end
        end
      end
    end)
    emptyHandCap = (otherBooks >= 3) and 3 or 2
  end

  -- Check if playing pair melds (up to emptyHandCap) + remaining wilds as wild meld
  -- would empty the hand.  When true, Phase 1 restrictions are lifted so the player
  -- can pick up their foot.  Works regardless of needBlackBook.
  -- NOTE: when canEmptyWithWilds is true, Phases 2 & 3 are skipped so remaining wilds
  -- are not stolen by existing melds — they must flow to the Phase 4 wild meld.
  local canEmptyWithWilds = false
  if hasFoot then
    local meldNaturals = 0
    for _, m in ipairs(meldPlan) do meldNaturals = meldNaturals + m.count end
    local eligiblePairCount = 0
    for rank, count in pairs(state.handByRank) do
      if isEligibleRank(rank) and count == 2 and not melds[rank] and not redBookRanks[rank] then
        eligiblePairCount = eligiblePairCount + 1
      end
    end
    local pairsUsed    = math.min(eligiblePairCount, emptyHandCap)
    local wildsForPairs = math.min(pairsUsed, state.wildCount)
    local wildsForMeld  = state.wildCount - wildsForPairs
    local wildMeldCards = (wildsForMeld >= 3) and wildsForMeld or 0
    local totalPlayable = meldNaturals + pairsUsed * 2 + wildsForPairs + wildMeldCards
    canEmptyWithWilds = (state.handCount - totalPlayable <= 1)
    if canEmptyWithWilds then
      L(string.format("canEmptyWithWilds: %d naturals + %d pairs×2 + %d w→pairs + %d w→wildmeld = %d of %d",
        meldNaturals, pairsUsed, wildsForPairs, wildMeldCards, totalPlayable, state.handCount))
    end
  end

  -- Detect the pure "wild meld + one mixed meld empties hand" scenario:
  -- foot on table, 4+ wilds, exactly 2 natural cards forming a pair.
  -- All wilds: 1 goes to the mixed meld, the rest form a pure wild meld.
  local canEmptyViaWildMeld = false
  if hasFoot and state.wildCount >= 4 then
    local naturalCount = state.handCount - state.wildCount
    if naturalCount == 2 then
      for rank, count in pairs(state.handByRank) do
        if isEligibleRank(rank) and count >= 2 then
          canEmptyViaWildMeld = true
          break
        end
      end
    end
  end
  if canEmptyViaWildMeld then
    L("canEmptyViaWildMeld: foot on table, " .. state.wildCount ..
      " wilds + 1 pair → wild meld + mixed meld")
  end

  -- Suppress wild plays on RANK melds when fewer than 2 red books are projected.
  -- Adding wilds to natural melds converts them to black melds, making it harder
  -- to build a 2nd red book.  Exception: hand-emptying plays for foot pickup.
  -- Exception: completing a WILD BOOK is always allowed — wild books are independent
  -- of the red/black book requirement and score 1500 pts regardless.
  local projRedVal = projRed or state.bookCounts.red
  local canCompleteWildBook = false
  do
    -- Find an extendable wild meld (total < 7).
    local wm = (melds["2"]    and melds["2"].total    < 7 and melds["2"])
            or (melds["Joker"] and melds["Joker"].total < 7 and melds["Joker"])
    if wm and wm.total + state.wildCount >= 7 then
      canCompleteWildBook = true   -- extending existing wild meld to 7
    elseif not melds["2"] and not melds["Joker"] and state.wildCount >= 7 then
      canCompleteWildBook = true   -- no wild meld yet; Phase 4 creates one from 7+ wilds
    end
  end
  if not hasFoot and projRedVal < 2
     and not canEmptyWithWilds and not canEmptyViaWildMeld
     and not canCompleteWildBook then
    L(string.format("Wild plays: held — build 2 red books first (projected red=%d)", projRedVal))
    return {}
  end
  if canCompleteWildBook and not hasFoot and projRedVal < 2 then
    L("Wild plays: wild book completion allowed (independent of red book count)")
  end

  -- Gather wilds: 2s before Jokers
  local wildCards = {}
  for _, card in ipairs(state.hand) do
    if card.color == "Wild" then table.insert(wildCards, card) end
  end
  sortWilds(wildCards)

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
    -- A rank meld becomes a book only if it also has ≥1 red-suit and ≥1 black-suit natural card.
    local mc = m.colors or {hasRed=false, hasBlack=false}
    local colorBalanced = m.isWildMeld or (mc.hasRed and mc.hasBlack)
    local completesBook = (m.total >= 7) and colorBalanced
    -- Merge into existing alloc when:
    --   (a) follow-on wild for a Phase 1 new rank meld (obj==nil, not isNew), or
    --   (b) additional wild for a pre-existing wild meld (consolidate into one executor alloc).
    if (not m.isWildMeld and m.obj == nil and not m.isNew)
    or (m.isWildMeld and m.obj ~= nil) then
      for i = #allocs, 1, -1 do
        if allocs[i].rank == rank then
          table.insert(allocs[i].wilds, wildCards[nextWild])
          allocs[i].completesBook = allocs[i].completesBook or completesBook
          nextWild = nextWild + 1
          return true
        end
      end
    end
    -- If this rank's naturals are being placed by layoutHandRank, the executor
    -- must not try to place them again.  Clear naturalCards and flag accordingly.
    local naturalsPlaced = meldPlanRanks[rank] == true
    local naturals = (not naturalsPlaced) and (m.naturals or {}) or {}
    m.naturals = {}
    table.insert(allocs, {
      rank                 = rank,
      meldObj              = m.obj,
      naturalCards         = naturals,
      wilds                = {wildCards[nextWild]},
      existingCount        = m.total - 1,
      isNew                = m.isNew,
      isWildMeld           = m.isWildMeld,
      naturalsAlreadyPlaced = naturalsPlaced,
      priority             = priority,
      completesBook        = completesBook,
      prevWilds            = m.wilds - 1,
      reason               = reason,
    })
    nextWild = nextWild + 1
    m.isNew  = false
    return true
  end

  -- Eligibility predicate: can this meld accept one more wild?
  --   Wild melds:              always (no 2-wild cap, up to 7).
  --   New rank melds (obj==nil): up to 2-wild cap, always extendable regardless of foot status.
  --   Pre-existing rank melds:  going-out scenario (no foot) OR we still need a black book.
  -- NOTE: use m.obj==nil (not m.isNew) — isNew is reset by the first assignWild call.
  local function canExtend(m)
    if m.total >= 7 then return false end
    if m.isWildMeld then return true end          -- wild melds: no 2-wild cap
    if m.wilds >= 2  then return false end        -- rank melds: enforce 2-wild cap
    if m.obj == nil  then return true end         -- new this turn: always extendable
    -- Pre-existing rank meld: allow when going out, need a black book,
    -- OR the other player's foot is already gone (use wilds rather than discard them).
    return not hasFoot or needBlackBook or not otherFoot
  end

  -- Rank priority for Phase 1 pair selection (highest value first → more points as a book).
  local rankPriority = {
    ["A"]=13,["K"]=12,["Q"]=11,["J"]=10,["10"]=9,
    ["9"]=8,["8"]=7,["7"]=6,["6"]=5,["5"]=4,["4"]=3,
  }

  -- Phase 1: hand pairs (exactly 2 naturals, no existing meld) → 1 wild → new rank meld of 3.
  -- When going out (no foot): all pairs eligible, no cap.
  -- Suppressed when needBlackBook unless canEmptyWithWilds / canEmptyViaWildMeld.
  -- canEmptyViaWildMeld: foot on table, 4+ wilds, 1 pair → exactly 1 wild, cap = 1.
  -- canEmptyWithWilds: emptying hand with up to emptyHandCap pairs is beneficial.
  -- Pairs are processed highest-rank first so the cap trims low-value pairs, not high ones.
  local phase1Allowed = canEmptyViaWildMeld or canEmptyWithWilds or
                        ((not hasFoot or not otherFoot) and not needBlackBook)
  local phase1Cap
  if canEmptyViaWildMeld then
    phase1Cap = 1
  elseif canEmptyWithWilds then
    phase1Cap = emptyHandCap        -- use same cap that made canEmptyWithWilds true
  elseif hasFoot and not otherFoot then
    phase1Cap = 2                   -- regular foot-pickup play (non-emptying)
  else
    phase1Cap = math.huge
  end
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
      local label = canEmptyViaWildMeld
        and string.format("new black meld: 2 × %s + 1 wild (wild+pair empty hand)", rank)
        or  (hasFoot and not otherFoot)
          and string.format("new black meld: 2 × %s + 1 wild (foot-pickup play, %d/2)", rank, phase1Count+1)
          or  string.format("new black meld: 2 × %s + 1 wild (hand pair)", rank)
      assignWild(rank, 1, label)
      phase1Count = phase1Count + 1
    end
  end

  -- Phases 2 and 3 are skipped when emptying the hand (canEmptyViaWildMeld or
  -- canEmptyWithWilds) so remaining wilds flow directly to the Phase 4 wild meld.
  if not canEmptyViaWildMeld and not canEmptyWithWilds then
    -- Phase 2: pre-existing melds on table (obj ~= nil).
    -- Normal (not needBlackBook): 1 wild each.
    -- needBlackBook: concentrate all wilds needed to COMPLETE one meld at a time (sorted
    --   by fewest-additional-wilds first), re-checking eligibility with remaining wilds.
    do
      local preExisting = {}
      for rank, m in pairs(melds) do
        if m.obj ~= nil and canExtend(m) then
          local wildsLeft = #wildCards - nextWild + 1
          local mc2 = m.colors or {hasRed=false, hasBlack=false}
          local colorOk = mc2.hasRed and mc2.hasBlack
          -- When needBlackBook, wild melds only qualify if completing to a wild book this turn.
          local wildBookComplete = m.isWildMeld and (m.total + math.min(wildsLeft, 7 - m.total) >= 7)
          local eligible = not needBlackBook
                        or wildBookComplete
                        or (not m.isWildMeld and (m.total + math.min(wildsLeft, 2 - m.wilds) >= 7) and colorOk)
          if eligible then table.insert(preExisting, rank) end
        end
      end
      if needBlackBook then
        -- Sort: fewest additional wilds needed to complete a book first (closest to 7).
        table.sort(preExisting, function(a, b)
          local ma, mb = melds[a], melds[b]
          local na = 7 - ma.total   -- additional wilds needed to reach 7
          local nb = 7 - mb.total
          if na ~= nb then return na < nb end
          return ma.total > mb.total  -- tiebreak: more existing cards first
        end)
        for _, rank in ipairs(preExisting) do
          if nextWild > #wildCards then break end
          local m = melds[rank]
          -- Re-check with remaining wilds: still reachable?
          local wildsLeft = #wildCards - nextWild + 1
          local mc2 = m.colors or {hasRed=false, hasBlack=false}
          local colorOk = mc2.hasRed and mc2.hasBlack
          local wildBookComplete = m.isWildMeld and (m.total + math.min(wildsLeft, 7 - m.total) >= 7)
          if wildBookComplete then
            -- Concentrate all wilds needed to complete this wild book.
            while nextWild <= #wildCards and canExtend(m) and m.total < 7 do
              assignWild(rank, 2, string.format("completes wild book (%d → 7)", m.total))
            end
          elseif not m.isWildMeld and (m.total + math.min(wildsLeft, 2 - m.wilds) >= 7) and colorOk then
            -- Assign all wilds needed to complete this black rank book.
            while nextWild <= #wildCards and canExtend(m) and m.total < 7 do
              assignWild(rank, 2,
                string.format("completes black book %s (%d → 7)", rank, m.total))
            end
          end
        end
      else
        for _, rank in ipairs(preExisting) do
          if nextWild > #wildCards then break end
          local m = melds[rank]
          local label = m.isWildMeld
            and string.format("extends wild meld (%d cards on table)", m.total)
            or  string.format("extends black meld %s (%d cards on table)", rank, m.total)
          assignWild(rank, 2, label)
        end
      end
    end

    -- Update needBlackBook after Phase 2: if Phase 2 completed enough black books,
    -- Phase 3 should no longer be gated by that requirement.
    if needBlackBook then
      local projectedBlack = state.bookCounts.black
      for _, wa in ipairs(allocs) do
        if wa.completesBook then
          local m = melds[wa.rank]
          if m and m.wilds > 0 then projectedBlack = projectedBlack + 1 end
        end
      end
      if projectedBlack >= 2 then needBlackBook = false end
    end

    -- Phase 3: remaining wilds → fewest-cards-first.
    -- Wild melds always eligible; rank melds only when player has no foot (via canExtend).
    -- When needBlackBook, rank melds only qualify when wild would bring total to >= 7.
    while nextWild <= #wildCards do
      local candidates = {}
      for _, m in pairs(melds) do
        if canExtend(m) then
          local wildsLeft = #wildCards - nextWild + 1
          local mc2 = m.colors or {hasRed=false, hasBlack=false}
          local colorOk = mc2.hasRed and mc2.hasBlack
          -- When needBlackBook, wild melds only qualify if completing to a wild book this turn.
          local wildBookComplete = m.isWildMeld and (m.total + math.min(wildsLeft, 7 - m.total) >= 7)
          local eligible = not needBlackBook
                        or wildBookComplete
                        or (not m.isWildMeld and (m.total + math.min(wildsLeft, 2 - m.wilds) >= 7) and colorOk)
          if eligible then table.insert(candidates, m) end
        end
      end
      if #candidates == 0 then break end
      table.sort(candidates, function(a, b) return a.total < b.total end)
      local placed = false
      for _, m in ipairs(candidates) do
        if canExtend(m) then  -- re-check: assignWild may have updated m.wilds/m.total
          placed = assignWild(m.rank, 3,
            string.format("extends %s (%d cards, fewest-first)",
              m.isWildMeld and "wild meld" or ("black meld "..m.rank), m.total))
          if placed then break end
        end
      end
      if not placed then break end
    end
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

  -- Phase 5: place any remaining unallocated wilds on eligible melds rather than
  -- letting them fall through to discard.  This handles wilds left over after
  -- Phases 2/3 were skipped (canEmptyWithWilds / canEmptyViaWildMeld path) or
  -- after Phase 4 consumed fewer wilds than available.
  --
  -- Eligibility is the same as Phases 2/3 (via canExtend), which now includes
  -- "not otherFoot" — so when the other player's foot is gone, ANY pre-existing
  -- rank meld with room can absorb a leftover wild.
  --
  -- In the hand-emptying path (canEmptyWithWilds / canEmptyViaWildMeld) the
  -- needBlackBook gate is lifted so the wild goes somewhere useful rather than
  -- being discarded.
  while nextWild <= #wildCards do
    local candidates = {}
    for _, m in pairs(melds) do
      if canExtend(m) then
        local freePlace = canEmptyWithWilds or canEmptyViaWildMeld or hasFoot
        local eligible  = freePlace or not needBlackBook
                          or m.isWildMeld or (m.total + 1 >= 7)
        if eligible then table.insert(candidates, m) end
      end
    end
    if #candidates == 0 then break end
    table.sort(candidates, function(a, b) return a.total < b.total end)
    local placed = false
    for _, m in ipairs(candidates) do
      if canExtend(m) then
        placed = assignWild(m.rank, 5,
          string.format("extends %s (%d cards, avoids wild discard)",
            m.isWildMeld and "wild meld" or ("black meld "..m.rank), m.total))
        if placed then break end
      end
    end
    if not placed then break end
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
    if not hasExistingMeldsOrBooks(state) then
      local minimum = gi_OPENING_MELD_MIN[giHand] or 50
      L(string.format("Natural melds: suppressed — opening minimum %d pts not met (hand %d)",
        minimum, giHand))
    else
      L("Natural melds: nothing eligible (need 3+ of a rank)")
    end
  else
    for _, m in ipairs(melds) do
      L(string.format("  [p%d] %s — %s", m.priority, m.rank, m.reason))
    end
  end

  -- Projected red book count from natural meld plays only (used to gate wild allocation).
  local projRedFromMelds = state.bookCounts.red
  for _, m in ipairs(melds) do
    if m.priority == 1 then projRedFromMelds = projRedFromMelds + 1 end
  end

  -- Compute wild allocs now (needed for go-out projection), but only keep them
  -- if the plan actually results in going out this turn.
  local wildAllocs = evalWildAllocations(state, melds, L, projRedFromMelds)

  local projRed   = state.bookCounts.red
  local projBlack = state.bookCounts.black
  for _, m in ipairs(melds) do
    if m.priority == 1 then projRed   = projRed   + 1 end  -- completes red book
    if m.priority == 2 then projBlack = projBlack + 1 end  -- completes black book (naturals into wild meld)
  end
  for _, wa in ipairs(wildAllocs) do if wa.completesBook then projBlack = projBlack + 1 end end

  local cardsConsumed = 0
  for _, m in ipairs(melds) do cardsConsumed = cardsConsumed + m.count end
  for _, wa in ipairs(wildAllocs) do
    cardsConsumed = cardsConsumed + #wa.wilds + #wa.naturalCards
  end
  local projHandCount = state.handCount - cardsConsumed

  -- evalGoOut may have returned should=true purely on books/foot state, without
  -- knowing what plays are possible this turn.  Override to false if the planned
  -- plays don't actually reduce the hand to 0-1 cards.
  if goOut.should and projHandCount > 1 then
    goOut = {should=false, reason=string.format(
      "books met but %d cards remain after plays", projHandCount)}
    L("Go out: deferred — " .. goOut.reason)
  end

  -- projHandCount == 1 means one card remains after plays: that card is the discard.
  -- projHandCount == 0 means plays consume every card (no discard needed).
  -- Both cases satisfy "hand emptied this turn", so use <= 1.
  if not state.hasFoot and projHandCount <= 1 and projRed >= 2 and projBlack >= 2 then
    goOut = {should=true, reason=string.format(
      "empties hand after plays (proj red=%d black=%d)", projRed, projBlack)}
    L("Go out: YES (after plays) — " .. goOut.reason)
  elseif not state.hasFoot and projRed >= 2 and projBlack >= 2 and not goOut.should then
    L(string.format("Projected go-out: books met (red=%d black=%d) but %d cards remain",
      projRed, projBlack, projHandCount))
  end

  -- Wild plays are allowed when:
  --   (a) the plays would empty the hand (projHandCount <= 1, last card = discard), AND
  --       no other player has foot on table (end-game), OR going out, OR picking up own foot.
  --   OR
  --   (b) end-game black-book build: foot already picked up, projected 2+ red books this
  --       turn but fewer than 2 black books — use wilds to convert existing red melds into
  --       black books regardless of hand size.
  -- Wild cards are NEVER discarded unless all remaining cards are wild (evalDiscard rule 8).
  local needsBlackBooks = not state.hasFoot and projRed >= 2 and state.bookCounts.black < 2
  local allowWilds =
    ((projHandCount <= 1) and (not state.otherFootOnTable or goOut.should or state.hasFoot))
    or needsBlackBooks

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
    end
    wildAllocs = {}
  else
    if needsBlackBooks and projHandCount > 1 then
      L(string.format("Wild plays: allowed — building black books (red=%d black=%d)",
        projRed, state.bookCounts.black))
    end
    if #wildAllocs == 0 then
      if state.wildCount > 0 then L("Wild plays: no useful allocation found") end
    else
      for _, wa in ipairs(wildAllocs) do
        local displayRank = (wa.isWildMeld or wa.rank == "__wild__") and "wild-meld" or wa.rank
        L(string.format("  [w%d] %s — %s", wa.priority, displayRank, wa.reason))
      end
    end
  end

  -- Ensure at least 2 cards remain when the player cannot go out and is not
  -- intentionally emptying their hand to pick up their foot.
  -- (1 card to keep + 1 card to discard.)  Prune wild allocs first, then
  -- non-book-completing melds (priority >= 3, i.e. extend or new meld).
  local originalMeldCount = #melds
  if not goOut.should and not (state.hasFoot and allowWilds) then
    local consumed = 0
    for _, m  in ipairs(melds)      do consumed = consumed + m.count                    end
    for _, wa in ipairs(wildAllocs) do consumed = consumed + #wa.wilds + #wa.naturalCards end
    local proj2 = state.handCount - consumed
    if proj2 < 2 then
      -- Step 1: prune wild allocs (highest priority number = least important first)
      if #wildAllocs > 0 then
        table.sort(wildAllocs, function(a, b) return a.priority > b.priority end)
        local i = 1
        while proj2 < 2 and i <= #wildAllocs do
          local wa = wildAllocs[i]
          proj2 = proj2 + #wa.wilds + #wa.naturalCards
          L(string.format("Wild alloc pruned (hand too small): %s", wa.rank))
          table.remove(wildAllocs, i)
        end
      end
      -- Step 2: prune non-book-completing melds (p3 / p4) if still short
      if proj2 < 2 then
        -- Prune fewest-card plays first (keep high-count plays that score more points).
        -- Use priority as tiebreaker: remove lower-importance plays first.
        table.sort(melds, function(a, b)
          if a.count ~= b.count then return a.count < b.count end
          return a.priority > b.priority
        end)
        local pruned = {}
        local i = 1
        while proj2 < 2 and i <= #melds do
          if melds[i].priority >= 3 then
            proj2 = proj2 + melds[i].count
            table.insert(pruned, melds[i].rank)
            table.remove(melds, i)
          else
            i = i + 1
          end
        end
        if #pruned > 0 then
          L("Melds pruned (cannot go out, hand too small): " .. table.concat(pruned, ", "))
        end
      end
    end
  end

  -- If melds were pruned, recompute wild allocs so allocs don't reference removed ranks.
  if allowWilds and #melds ~= originalMeldCount then
    wildAllocs = evalWildAllocations(state, melds, L, projRedFromMelds)
    for _, wa in ipairs(wildAllocs) do
      L(string.format("  [w%d] %s — %s (recomputed after pruning)", wa.priority, wa.rank, wa.reason))
    end
  end

  local discard
  if goOut.should and projHandCount == 0 then
    discard = {card=nil, reason="going out — no discard needed"}
  else
    discard = evalDiscard(state, melds, wildAllocs)
  end

  -- Wild-discard prevention: if the planned discard is a wild card AND there are
  -- non-book melds (priority >= 3) being played, try removing them (least important
  -- first) until a non-wild discard is available.  Keeping the naturals in hand
  -- lets evalDiscard choose them over a wild.
  if not goOut.should and discard.card and discard.card.color == "Wild" then
    local pruneable = {}
    for i, m in ipairs(melds) do
      if m.priority >= 3 then table.insert(pruneable, {idx=i, m=m}) end
    end
    table.sort(pruneable, function(a, b) return a.m.priority > b.m.priority end)
    for _, entry in ipairs(pruneable) do
      local tryMelds = {}
      for i, m in ipairs(melds) do
        if i ~= entry.idx then table.insert(tryMelds, m) end
      end
      local tryConsumed = 0
      for _, m  in ipairs(tryMelds)  do tryConsumed = tryConsumed + m.count end
      local tryProjHand = state.handCount - tryConsumed
      -- Wild allocs are only kept if they empty the hand; otherwise clear them.
      local tryWA = {}
      if tryProjHand <= 1 then
        tryWA = evalWildAllocations(state, tryMelds, function() end, projRedFromMelds)
        for _, wa in ipairs(tryWA) do
          tryConsumed = tryConsumed + #wa.wilds + #wa.naturalCards
        end
        tryProjHand = state.handCount - tryConsumed
      end
      local tryDiscard = evalDiscard(state, tryMelds, tryWA)
      if tryDiscard.card and tryDiscard.card.color ~= "Wild" then
        L(string.format("Pruned %s meld (kept naturals to avoid discarding wild)", entry.m.rank))
        melds       = tryMelds
        wildAllocs  = tryWA
        discard     = tryDiscard
        projHandCount = tryProjHand
        break
      end
    end
  end

  -- Final safety check: if all plays together consumed all but 1 card, and that
  -- remaining card would be discarded, and we can't go out, we'd empty the hand
  -- without meeting the go-out requirement.  Scrap every play so the full hand
  -- is available and evalDiscard can choose a proper (non-wild) card.
  if not goOut.should and discard.card and (projHandCount - 1 == 0) then
    L("Plays scrapped — discarding last card without going out; re-evaluating from full hand")
    melds         = {}
    wildAllocs    = {}
    projHandCount = state.handCount
    discard       = evalDiscard(state, {}, {})
  end

  -- ── PLAY SUMMARY ──────────────────────────────────────────
  -- Emit after all pruning is resolved so only confirmed plays appear.
  L("")
  L("Plays")
  if #melds == 0 and #wildAllocs == 0 then
    L("  (no plays this turn)")
  else
    -- Merge melds and wildAllocs by rank for combined display.
    local rankOrder = {}
    local rankData  = {}  -- rank → {natCount, wildCount, existingColor, isNew, completes, becomesBlack}

    local function getOrCreate(rank, defaults)
      if not rankData[rank] then
        table.insert(rankOrder, rank)
        rankData[rank] = defaults
      end
      return rankData[rank]
    end

    for _, m in ipairs(melds) do
      local d = getOrCreate(m.rank, {
        natCount=0, wildCount=0,
        existingColor=m.meldColor,
        isNew=(m.existingCount == 0),
        completes=false, becomesBlack=false,
      })
      d.natCount = d.natCount + m.count
      if m.priority <= 2 then d.completes = true end
    end

    local wildMeldWa = nil
    for _, wa in ipairs(wildAllocs) do
      if wa.isWildMeld or wa.rank == "__wild__" then
        wildMeldWa = wa
      else
        local prevColor = (wa.isNew or (wa.prevWilds or 0) == 0) and "red" or "black"
        local d = getOrCreate(wa.rank, {
          natCount=#wa.naturalCards, wildCount=0,
          existingColor=prevColor,
          isNew=wa.isNew,
          completes=false, becomesBlack=false,
        })
        d.wildCount = d.wildCount + #wa.wilds
        if wa.completesBook then d.completes = true end
        if prevColor == "red" and not d.isNew then d.becomesBlack = true end
      end
    end

    for _, rank in ipairs(rankOrder) do
      local d = rankData[rank]
      local what = {}
      if d.natCount  > 0 then table.insert(what, rank .. " x" .. d.natCount)  end
      if d.wildCount > 0 then table.insert(what, "Wild x" .. d.wildCount) end
      local whatStr = table.concat(what, " ")
      local where, xform
      if d.completes then
        local bookColor = (d.wildCount > 0 or d.existingColor == "black") and "Black" or "Red"
        if d.isNew then
          where = "new " .. bookColor .. " " .. rank .. " Book"
          xform = ""
        else
          where = "on " .. d.existingColor .. " " .. rank .. " Meld"
          xform = " -> " .. bookColor .. " Book"
        end
      elseif d.isNew then
        where = "new " .. (d.wildCount > 0 and "black" or "red") .. " " .. rank .. " Meld"
        xform = ""
      else
        where = "on " .. d.existingColor .. " " .. rank .. " Meld"
        xform = d.becomesBlack and (" -> black " .. rank .. " Meld") or ""
      end
      L("  " .. whatStr .. " : " .. where .. xform)
    end

    if wildMeldWa then
      local wildN = #wildMeldWa.wilds
      local loc   = wildMeldWa.isNew and "new Wild Meld" or "on Wild Meld"
      local xform = wildMeldWa.completesBook and " -> Wild Book" or ""
      L("  Wild x" .. wildN .. " : " .. loc .. xform)
    end
  end
  -- picksUpFoot: after melds + discard the hand is empty while foot is still on the table.
  -- This covers both the no-discard case (projHandCount==0) and the discard-last-card case
  -- (projHandCount==1 with a discard card → 0 cards remain → pick up foot).
  local postDiscardCount = projHandCount - (discard.card and 1 or 0)
  local picksUpFoot = state.hasFoot and (postDiscardCount == 0)

  if goOut.should and not discard.card then
    L("  DISC  (going out — no discard)")
  elseif goOut.should and discard.card then
    local r = discard.card.rank
    local s = discard.card.suit or "?"
    L(string.format("  DISC  %s of %s (going out)", r, s))
  elseif picksUpFoot and discard.card then
    local r = discard.card.rank
    local s = discard.card.suit or "?"
    L(string.format("  DISC  %s of %s (then pick up foot)", r, s))
  elseif picksUpFoot then
    L("  DISC  (none — hand empty, picking up foot)")
  elseif discard.card then
    local r = discard.card.rank
    local s = discard.card.suit or "?"
    L(string.format("  DISC  %s of %s", r, s))
  else
    L("  DISC  " .. (discard.reason or "none"))
  end
  L("─────────────────────────────────────────────────────────")

  return {
    color=sColor, state=state, goOut=goOut,
    melds=melds, wildAllocs=wildAllocs, discard=discard,
    picksUpFoot=picksUpFoot,
    log=log, ok=true,
  }
end

-- ----------------------------------------------------------------------------
-- Executor
-- ----------------------------------------------------------------------------

-- Executes a TurnPlan: plays melds in priority order, then discards.
-- Melds are driven by layoutHandRank (existing animation pipeline).
-- Discard fires after all melds have had time to animate.
-- When plan.picksUpFoot is true the hand is empty after melds so the executor
-- automatically deals the foot pile to the player's hand, sorts, and opens
-- the Plan panel — exactly as if they had clicked the Plan button themselves.
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

  -- Discard after melds finish
  if plan.discard.card then
    Wait.time(function()
      pcall(function()
        plan.discard.card.obj.setPositionSmooth(obj_Zone_Discard.getPosition())
        plan.discard.card.obj.setRotation({0, 180, 0})
      end)
    end, totalMeldTime + 0.5)
  end

  -- Foot pickup: hand emptied (with or without discard) → auto-deal foot, sort, re-plan.
  if plan.picksUpFoot then
    Wait.time(function()
      -- Find the face-down foot pile in the player's score zones.
      local footObj = nil
      pcall(function()
        local colorZones = getPlayerZones(sColor)
        if not colorZones then return end
        for _, scoreZone in ipairs(colorZones.zones) do
          local ok, objs = pcall(function() return scoreZone.obj.getObjects() end)
          if ok and objs then
            for _, obj in ipairs(objs) do
              if (obj.tag == "Deck" or obj.tag == "Card") and obj.is_face_down then
                footObj = obj
                break
              end
            end
          end
          if footObj then break end
        end
      end)

      if not footObj then
        printToColor("(auto foot pickup: foot pile not found)", sColor)
        return
      end

      -- Deal all foot cards into the player's hand.
      pcall(function()
        if footObj.tag == "Deck" then
          local ok, qty = pcall(function() return footObj.getQuantity() end)
          footObj.deal(ok and qty or 11, sColor)
        else
          footObj.deal(1, sColor)
        end
      end)

      broadcastToColor("Picking up your foot!", sColor)

      -- After cards arrive: sort the hand, then branch on how foot was triggered.
      -- No discard (hand emptied by melds): handle red 3s, sort, show new plan.
      -- After a discard (turn is over):      just sort — no red-3 swap, no plan.
      Wait.time(function()
        if not plan.discard.card then
          handleRedThrees(sColor, function()
            pcall(function() sortHand(nil, sColor) end)
            Wait.time(function()
              gPlanResult = buildTurnPlan(sColor)
              local text = table.concat(gPlanResult.log, "\n")
              if text == "" then text = "(no plan output)" end
              pcall(function() text = text .. buildStateContext(gPlanResult) end)
              UI.setAttribute("PlanResultText", "text", text)
              Wait.time(function()
                UI.setAttribute("PlanResultPanel", "active", "true")
              end, 0.05)
            end, 0.75)
          end)
        else
          pcall(function() sortHand(nil, sColor) end)
        end
      end, 2.0)
    end, plan.discard.card and (totalMeldTime + 1.5) or (totalMeldTime + 0.5))
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
