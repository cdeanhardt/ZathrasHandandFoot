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
--   1 — play completes an existing meld to a book (≥7 total)
--   2 — play extends an existing meld
--   3 — play starts a new meld (no existing meld of this rank on table)
function evalMeldsToPlay(state)
  local plans = {}

  for rank, count in pairs(state.handByRank) do
    if count >= 3 and isEligibleRank(rank) then
      -- How many cards are already on the table for this rank?
      local existingMeld  = state.meldsByRank[rank]
      local existingCount = 0
      if existingMeld then
        local ok, qty = pcall(function() return existingMeld.obj.getQuantity() end)
        existingCount = (ok and qty) or 1  -- Card tag = 1
      end

      local projected = existingCount + count
      local priority, reason

      if existingMeld and existingCount < 7 and projected >= 7 then
        priority = 1
        reason = string.format("completes book: %d + %d = %d", existingCount, count, projected)
      elseif existingMeld then
        priority = 2
        reason = string.format("extends meld: %d on table + %d from hand", existingCount, count)
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
        rank          = rank,
        cards         = cards,
        count         = count,
        existingCount = existingCount,
        priority      = priority,
        reason        = reason,
      })
    end
  end

  -- Sort: priority first, then larger melds before smaller at same priority
  table.sort(plans, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.count > b.count
  end)

  return plans
end

-- Discard tier for a non-wild card.  Lower tier = discard sooner.
-- Tiers: 0=black 3s, 1=low(4-7), 2=mid(8-K), 3=ace, 99=red 3s (skip)
local gt_DISCARD_TIER = {
  ["4"]=1, ["5"]=1, ["6"]=1, ["7"]=1,
  ["8"]=2, ["9"]=2, ["10"]=2, ["J"]=2, ["Q"]=2, ["K"]=2,
  ["A"]=3,
}
local function discardTier(card)
  if card.rank == "3" then
    return card.color == "Black" and 0 or 99
  end
  return gt_DISCARD_TIER[card.rank] or 2
end

-- What card to discard after planned melds? Returns {card=entry_or_nil, reason=string}
--
-- Rules (in priority order):
--   FILTER — never discard a wild while any non-wild remains
--   FILTER — never discard a red 3 (handled by the red-3 mechanic)
--   TIER   — black 3s first, then ranks 4-7, then 8-K, then Aces
--   COUNT  — within a tier, fewest copies remaining first (1-of before 2-of, etc.)
--   WILDS  — only if no non-wilds remain: 2s before Jokers
function evalDiscard(state, meldPlan)
  local melding = {}
  for _, m in ipairs(meldPlan) do melding[m.rank] = true end

  local remaining    = {}
  local remainByRank = {}
  for _, card in ipairs(state.hand) do
    if not melding[card.rank] then
      table.insert(remaining, card)
      if card.color ~= "Wild" and card.rank ~= "3" then
        remainByRank[card.rank] = (remainByRank[card.rank] or 0) + 1
      end
    end
  end

  if #remaining == 0 then
    return {card=nil, reason="hand emptied by melds (go out)"}
  end

  local hasNonWild = false
  for _, card in ipairs(remaining) do
    if card.color ~= "Wild" then hasNonWild = true; break end
  end

  local best, bestScore, bestReason = nil, math.huge, "no suitable discard found"
  for _, card in ipairs(remaining) do
    local tier, count, skip = 0, 0, false
    if card.color == "Wild" then
      if hasNonWild then skip = true
      elseif card.rank == "Joker" then tier = 11
      else tier = 10 end
      count = 0
    else
      tier = discardTier(card)
      if tier == 99 then skip = true end
      count = remainByRank[card.rank] or 1
    end
    if not skip then
      local score = tier * 1000 + count
      if score < bestScore then
        bestScore  = score
        best       = card
        if card.color == "Wild" then
          bestReason = string.format("wild %s (no non-wilds remain, tier %d)", card.rank, tier)
        else
          bestReason = string.format("%s: tier %d, %d of rank remaining", card.rank, tier, count)
        end
      end
    end
  end

  if best then return {card=best, reason=bestReason} end
  return {card=remaining[1], reason="fallback: only unplayable cards remain"}
end

-- ----------------------------------------------------------------------------
-- Plan assembler
-- ----------------------------------------------------------------------------

-- Builds a complete TurnPlan for sColor.
-- Returns a plain table; nothing is moved.
--
-- TurnPlan fields:
--   color    string
--   state    snapshotState result
--   goOut    evalGoOut result
--   melds    evalMeldsToPlay result
--   discard  evalDiscard result
--   log      [string] — human-readable reasoning trace
--   ok       bool
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
    L("Melds: nothing eligible to play from hand")
  else
    for _, m in ipairs(melds) do
      L(string.format("  [p%d] %s — %s", m.priority, m.rank, m.reason))
    end
  end

  local discard = evalDiscard(state, melds)
  if discard.card then
    L(string.format("Discard: %s %s — %s",
      discard.card.rank, discard.card.suit or "?", discard.reason))
  else
    L("Discard: " .. discard.reason)
  end

  return {
    color   = sColor,
    state   = state,
    goOut   = goOut,
    melds   = melds,
    discard = discard,
    log     = log,
    ok      = true,
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
