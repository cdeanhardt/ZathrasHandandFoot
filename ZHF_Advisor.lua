--==============================================================================
-- ZHF_Advisor.lua
-- Turn advisor: snapshots game state, evaluates options, returns a TurnPlan.
-- Bundled into Global.-1.lua via require("ZHF_Advisor").
--
-- Entry points:
--   buildTurnPlan(sColor)   -> TurnPlan table
--   executeTurnPlan(plan)   -> animates the plan in TTS
--   printTurnPlan(plan,c)   -> prints plan.log to chat
--==============================================================================

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
  if mixed then return nil end
  if rankFound == "3" then return nil end  -- 3s are never a valid book
  if wildCount == qty then return "wild" end
  -- Color-balance rule: rank books require ≥1 red-suit and ≥1 black-suit natural card.
  if not (hasRed and hasBlack) then return nil end
  if wildCount > 0 then return "black" end
  return "red"
end

function snapshotState(sColor)
  local hand  = getHandCards(sColor)
  local melds = getMelds(sColor)
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
        if meld.obj.tag == "Deck" then
          local ok, qty = pcall(function() return meld.obj.getQuantity() end)
          objCount = (ok and qty and qty >= 1) and qty or 1
        end
        if not meldsByRank[meld.rank] then
          -- First object of this rank: store it with the computed count.
          meldsByRank[meld.rank] = {rank=meld.rank, obj=meld.obj, count=objCount,
                                    embeddedWilds=0,
                                    isBook=false, pos=meld.pos, colors={hasRed=false, hasBlack=false}}
        else
          -- Additional spread Card objects of the same rank: accumulate count.
          meldsByRank[meld.rank].count = meldsByRank[meld.rank].count + objCount
        end
        -- Accumulate embedded wild count (separate wild Card objects co-located in this column).
        if meld.embeddedWilds and meld.embeddedWilds > 0 then
          meldsByRank[meld.rank].embeddedWilds =
            (meldsByRank[meld.rank].embeddedWilds or 0) + meld.embeddedWilds
        end
        -- Accumulate color balance from ALL objects of this rank (handles spread cards
        -- where each card is a separate TTS object and no single obj shows both colors).
        local mc = getMeldColors(meld.obj)
        if mc.hasRed   then meldsByRank[meld.rank].colors.hasRed   = true end
        if mc.hasBlack then meldsByRank[meld.rank].colors.hasBlack = true end
      end
    end
  end
  -- Filter out lone stray cards (count+embeddedWilds < 2) — a single card in the zone
  -- is not a valid meld and must not be treated as an extendable meld by the planner.
  for rank, entry in pairs(meldsByRank) do
    if (entry.count + (entry.embeddedWilds or 0)) < 2 then
      meldsByRank[rank] = nil
    end
  end

  -- Promote spread melds that have reached book size (total ≥ 7) into the books table.
  -- getMelds sets isBook=true only for TTS Deck objects with qty≥7.  Until checkAndMoveBooks
  -- physically merges the spread cards into a Deck, a completed meld of individual Cards
  -- has isBook=false and stays in meldsByRank — invisible to book-counting and go-out logic.
  for rank, entry in pairs(meldsByRank) do
    local total = (entry.count or 0) + (entry.embeddedWilds or 0)
    if total >= 7 and rank ~= "3" then
      local wildCt = (entry.embeddedWilds or 0)
      pcall(function() wildCt = wildCt + countMeldWilds(entry.obj) end)
      -- House rule: a rank book (red or black) needs >=1 red-suit AND >=1 black-suit natural
      -- card.  Only promote to a book when colour-balanced (or the pile is all-wild).  A 7+
      -- same-colour meld is NOT a book yet — leave it in meldsByRank so the planner keeps it
      -- visible and can complete it with an opposite-colour card.
      local ec = entry.colors or {}
      local isAllWild     = (wildCt >= total)
      local colorBalanced = ec.hasRed and ec.hasBlack
      if isAllWild or colorBalanced then
        local bt = (wildCt == 0) and "red" or (wildCt <= 2 and "black" or "wild")
        table.insert(books[bt], {rank=rank, obj=entry.obj, bookType=bt, pos=entry.pos})
        meldsByRank[rank] = nil
      end
    end
  end

  local handByRank = {}
  local wildCount  = 0
  for _, card in ipairs(hand) do
    if card.color == "Wild" then
      wildCount = wildCount + 1
    elseif card.rank ~= "3" then
      handByRank[card.rank] = (handByRank[card.rank] or 0) + 1
    end
  end
  local bookCounts = {red=#books.red, black=#books.black, wild=#books.wild}
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

function evalMeldsToPlay(state, anyOpponentNearGoOut)
  anyOpponentNearGoOut = anyOpponentNearGoOut or false
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
    -- Include embedded wilds in the count so existingCount reflects the true meld size.
    -- Without this, a meld like J×5(1w) (4 natural + 1 embedded wild) appears as 4 cards;
    -- evalMeldsToPlay then believes the meld is all-natural and misclassifies the play.
    local nat = meld.count or safeQty(meld.obj, 1)
    local emb = meld.embeddedWilds or 0
    existingByRank[rank] = {obj=meld.obj, count=nat + emb, isBook=false,
                            colors=meld.colors, embeddedWilds=emb}
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
    -- Use total (naturals + embedded wilds) so a meld like 5N+1W counts as 6-card near-black.
    if (meld.count or 0) + (meld.embeddedWilds or 0) == 6 then nearBlackCount = nearBlackCount + 1 end
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
          -- Include embedded wilds (separate Card objects co-located with rank cards,
          -- tracked via getMelds/snapshotState but not inside the representative obj).
          local existingWilds = countMeldWilds(existing.obj) + (existing.embeddedWilds or 0)
          local isRedBook = (existingWilds == 0)
          if not projColorBalanced then
            -- Would reach 7 cards but natural cards lack both colors — not a book yet.
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
          -- Include embedded wilds — same reasoning as the book-completion branch above.
          local existingWilds = countMeldWilds(existing.obj) + (existing.embeddedWilds or 0)
          meldColor = (existingWilds > 0) and "black" or "red"
          -- Suppress extending natural OPEN melds toward a 3rd red book.
          if not existing.isBook and existingWilds == 0 and not state.hasFoot
             and state.bookCounts.red >= 2 and state.bookCounts.black < 2 then
            -- Normally suppress: would build toward a 3rd red book instead of 2nd black.
            -- Exception: if naturals + available wilds reach 7, this CAN become a black book.
            local wildsAvail = math.min(state.wildCount, 2 - existingWilds)
            if existingCount + count + wildsAvail >= 7 and projColorBalanced then
              priority  = 2   -- completes black book (via wilds)
              meldColor = "red"  -- currently red; display will show -> Black Book
              reason = string.format("completes black book with wilds: %d + %d + %d = 7",
                existingCount, count, wildsAvail)
            else
              -- Can't complete a book this turn — but still extend the meld (don't skip).
              priority = 3
              reason = string.format("extends red meld: %d on table + %d from hand (black book later)",
                existingCount, count)
            end
          else
            if existing.isBook then
              if count >= 3 then
                -- H&F rule: a completed book does NOT prevent starting a fresh independent
                -- meld of the same rank.  3+ naturals → treat as a brand-new p4 meld.
                priority      = 4
                meldColor     = "red"
                existingCount = 0   -- signals execution layer: new column, not the book
                reason = string.format("new red meld: %d cards of rank %s (book exists; independent meld)",
                  count, rank)
              else
                -- count < 3: can't start a new meld.  Dumping a card onto an
                -- ALREADY-COMPLETE book has no strategic value on its own — it only
                -- empties the hand and throws away a card that could later form a
                -- meld or serve as a discard.  Generate this p5 play ONLY when it
                -- can serve a purpose the bot still needs:
                --   * pre-foot (state.hasFoot): emptying the hand may pick up the foot
                --   * an opponent is one book from going out: dump the hand defensively
                -- Genuine go-out scenarios are handled separately: buildTurnPlan's
                -- dedicated go-out passes (second-pass + p5-goout extension) re-add
                -- the needed book extensions from scratch, so suppressing here never
                -- blocks a real go-out.  Otherwise hold the card in hand.
                if state.hasFoot or anyOpponentNearGoOut then
                  priority = 5
                  reason = string.format("extends %s book: %d on table + %d from hand",
                    meldColor, existingCount, count)
                else
                  skip = true
                end
              end
            else
              priority = 3
              reason = string.format("extends %s meld: %d on table + %d from hand",
                meldColor, existingCount, count)
            end
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
          -- House-rule cap: never grow an UNBALANCED meld to book size (7+).  A rank book needs
          -- >=1 red-suit AND >=1 black-suit natural card, so a same-colour meld pushed to 7 is
          -- stuck (can't book, and its cards can't be reclaimed from the table).  Hold it at 6
          -- until an opposite-colour card of this rank is available (it becomes a discard
          -- candidate meanwhile).  p1/p2 book-completions require projColorBalanced so they are
          -- unaffected; existingCount<7 skips plays onto an already-complete book (p5).
          if priority >= 3 and not projColorBalanced
             and existingCount < 7 and (existingCount + playCount) >= 7 then
            playCount = math.max(0, 6 - existingCount)
          end
          local partial = (playCount < count)
          -- A capped-to-zero play contributes nothing; leave the cards in hand.
          if playCount > 0 then
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
  end

  table.sort(plans, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.count > b.count
  end)

  -- Opening minimum check moved to buildTurnPlan (after evalWildAllocations), where the
  -- actual allocated wild cards are known.  Wild cards count only when they are truly
  -- played this turn — which depends on the pre-foot suppression logic in evalWildAllocations.

  return plans
end

function evalDiscard(state, meldPlan, wildAllocs, logFn)
  local L = logFn or function() end
  -- Count how many cards of each rank the meld plan consumes.
  -- Partial melds (m.count < all of that rank) must only exclude m.count cards,
  -- leaving the excess available as discard candidates.
  local meldingCount = {}
  for _, m in ipairs(meldPlan) do
    meldingCount[m.rank] = (meldingCount[m.rank] or 0) + m.count
  end

  -- Track specific card objects consumed by wild allocations (keyed by TTS obj ref).
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
        local meldEntry = state.meldsByRank[rank]
        pcall(function() w = countMeldWilds(meldEntry.obj) end)
        w = w + (meldEntry.embeddedWilds or 0)
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
  -- Build a rank→bool lookup covering all completed books (red/black/wild).
  -- meldsByRank only holds open (non-book) melds, so books need a separate check.
  local bookRanks = {}
  for _, btype in ipairs({"red", "black", "wild"}) do
    for _, b in ipairs(state.books[btype]) do
      if b.rank then bookRanks[b.rank] = true end
    end
  end

  local unprotected, surplus, protected, superProtected = {}, {}, {}, {}
  for _, card in ipairs(candidates) do
    if holdRanks[card.rank] then
      if heldCount[card.rank] >= 2 then
        table.insert(surplus, card)
      else
        table.insert(superProtected, card)
      end
    elseif state.meldsByRank[card.rank] or bookRanks[card.rank] then
      table.insert(protected, card)
    else
      table.insert(unprotected, card)
    end
  end

  -- Log bucket contents so pasted plans show discard decision context.
  do
    local function rl(cards)
      local parts = {}
      for _, c in ipairs(cards) do
        local rv = gt_DISCARD_RANK_VALUE[c.rank]
        table.insert(parts, c.rank .. (rv and ("(rv="..rv..")") or "(rv=?)"))
      end
      return #parts > 0 and table.concat(parts, ",") or "[]"
    end
    local function wl(cards)
      local parts = {}
      for _, c in ipairs(cards) do table.insert(parts, c.rank) end
      return #parts > 0 and table.concat(parts, ",") or "[]"
    end
    L(string.format(
      "disc-buckets: unprotected=[%s] surplus=[%s] protected=[%s] held=[%s] wilds=[%s] holdRanks=[%s]",
      rl(unprotected), rl(surplus), rl(protected), rl(superProtected), wl(wilds),
      (function() local p={} for r,_ in pairs(holdRanks) do table.insert(p,r) end return #p>0 and table.concat(p,",") or "none" end)()))
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

    -- RULE 3: Fewest copies in hand first — discard a singleton before a pair,
    -- a pair before a triple, etc.  Copy-count is the primary sort key.
    local minCount = math.huge
    for _, g in ipairs(groups) do
      if #g.cards < minCount then minCount = #g.cards end
    end
    local atMinCount = {}
    for _, g in ipairs(groups) do
      if #g.cards == minCount then table.insert(atMinCount, g) end
    end

    -- RULE 7: Within the same copy-count, lowest absolute rank value wins (Ace is high).
    table.sort(atMinCount, function(a, b)
      return (gt_DISCARD_RANK_VALUE[a.rank] or 0) < (gt_DISCARD_RANK_VALUE[b.rank] or 0)
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
      "%s — count=%d rank-value=%d%s",
      chosen.rank, minCount,
      gt_DISCARD_RANK_VALUE[chosen.rank] or 0,
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

function evalWildAllocations(state, meldPlan, logFn, projRed, suppressWildBook)
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
      -- rank "2" or "Joker" means a pure wild meld — no 2-wild cap applies.
      local isWildMeld = (rank == "2" or rank == "Joker")
      local tot, wlds
      if isWildMeld then
        -- Use the count from state.meldsByRank, which comes from getMelds and correctly
        -- excludes wild cards that are embedded in rank meld columns.  getMeldInfo uses
        -- getTableCardsOfRank which finds ALL wild-ranked Card objects on the table,
        -- inflating the count with embedded wilds that can never join the wild book pile.
        tot  = meld.count or 0
        wlds = tot   -- every card in a wild meld IS a wild
      else
        tot, wlds = getMeldInfo(rank)
      end
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
        -- Guard: a meld completing a red book this turn must not receive a wild
        -- (that would convert our new red book to black, breaking the 2-red requirement).
        if m.priority == 1 then melds[m.rank].completingRedBook = true end
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

  -- Count opponent's books — used for emptyHandCap and post-foot wild play decisions.
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

  -- Count all eligible-rank meld piles (open + books) across opponents for pressure detection.
  local otherMelds = 0
  pcall(function()
    for _, color in ipairs(playerList or {}) do
      if color ~= state.color then
        for _, m in ipairs(getMelds(color)) do
          if isEligibleRank(m.rank) then otherMelds = otherMelds + 1 end
        end
      end
    end
  end)
  -- Opponent pressure: opponent has built 3+ melds while we haven't picked up our foot yet.
  local opponentPressure = hasFoot and (otherMelds >= 3)

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
    emptyHandCap = (otherMelds >= 3) and 3 or 2
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
      -- redBookRanks is excluded only from EXTENDING existing books (wilds would convert red→black).
      -- Phase 1 creates a NEW meld of the same rank, so red-book ranks are eligible here.
      if isEligibleRank(rank) and count == 2 and not melds[rank] then
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

  -- Under opponent pressure (3+ opponent melds, pre-foot): check if ALL wilds going to rank meld
  -- pairs (no wild meld reserved) would empty the hand this turn for foot pickup.
  local canEmptyViaPressure = false
  if hasFoot and opponentPressure then
    local meldNaturals = 0
    for _, m in ipairs(meldPlan) do meldNaturals = meldNaturals + m.count end
    local eligiblePairCount = 0
    for rank, count in pairs(state.handByRank) do
      -- Phase 1 creates a NEW meld — red-book ranks are eligible as pairs here.
      if isEligibleRank(rank) and count == 2 and not melds[rank] then
        eligiblePairCount = eligiblePairCount + 1
      end
    end
    local pairsUsed = math.min(eligiblePairCount, state.wildCount)
    local totalPlayable = meldNaturals + pairsUsed * 3  -- 2 naturals + 1 wild per pair
    canEmptyViaPressure = (state.handCount - totalPlayable <= 1)
    if canEmptyViaPressure then
      L(string.format("canEmptyViaPressure: opponent has %d melds, %d naturals + %d pairs×3 = %d of %d",
        otherMelds, meldNaturals, pairsUsed, totalPlayable, state.handCount))
    end
  end

  -- Detect the scenario where remaining cards after natural meld plays are ALL wilds,
  -- and existing rank melds have enough capacity (≤2 wilds each) to absorb all of them.
  -- When true, placing those wilds on rank melds empties the hand for foot pickup.
  -- Distinct from canEmptyWithWilds (which needs pairs) and canEmptyViaWildMeld (which
  -- needs 4+ wilds and exactly one natural pair).
  local canEmptyViaWildExtend = false
  if hasFoot and state.wildCount > 0 then
    local meldNaturals = 0
    for _, m in ipairs(meldPlan) do meldNaturals = meldNaturals + m.count end
    local remainingAfterNaturals = state.handCount - meldNaturals
    if remainingAfterNaturals == state.wildCount then
      -- All remaining cards are wilds — check if existing rank melds can absorb them.
      -- Include embedded wilds so we don't overestimate capacity for melds that already
      -- have a co-located wild Card object that countMeldWilds(obj) can't see.
      local wildCapacity = 0
      for _, meld in pairs(state.meldsByRank) do
        local mw = 0
        pcall(function() mw = countMeldWilds(meld.obj) end)
        mw = mw + (meld.embeddedWilds or 0)
        if mw < 2 then wildCapacity = wildCapacity + (2 - mw) end
      end
      canEmptyViaWildExtend = (wildCapacity >= state.wildCount)
      if canEmptyViaWildExtend then
        L(string.format("canEmptyViaWildExtend: %d wilds left after naturals, meld capacity=%d → empties hand",
          state.wildCount, wildCapacity))
      end
    end
  end

  -- Detect the scenario where remaining cards after natural meld plays are all wilds
  -- PLUS exactly one non-wild natural left to discard.  Playing all wilds on existing
  -- rank melds leaves that one card to discard, emptying the hand for foot pickup.
  -- Distinct from canEmptyViaWildExtend (which requires ALL remaining to be wilds with
  -- no discard) and canEmptyWithWilds (which builds new pair melds).
  local canEmptyViaWildOnMeld = false
  if hasFoot and state.wildCount > 0 then
    local meldNaturals = 0
    for _, m in ipairs(meldPlan) do meldNaturals = meldNaturals + m.count end
    local remainingAfterNaturals = state.handCount - meldNaturals
    -- Exactly wildCount wilds + 1 non-wild to discard remain after natural plays.
    if remainingAfterNaturals == state.wildCount + 1 then
      local wildCapacity = 0
      for rank, meld in pairs(state.meldsByRank) do
        -- Only count rank melds — don't route wilds onto the wild meld pile here.
        if rank ~= "2" and rank ~= "Joker" then
          local mw = 0
          pcall(function() mw = countMeldWilds(meld.obj) end)
          mw = mw + (meld.embeddedWilds or 0)
          if mw < 2 then wildCapacity = wildCapacity + (2 - mw) end
        end
      end
      canEmptyViaWildOnMeld = (wildCapacity >= state.wildCount)
      if canEmptyViaWildOnMeld then
        L(string.format("canEmptyViaWildOnMeld: %d naturals + %d wilds on rank melds + 1 discard = %d of %d",
          meldNaturals, state.wildCount, meldNaturals + state.wildCount + 1, state.handCount))
      end
    end
  end

  -- Suppress wild plays on RANK melds when fewer than 2 red books are projected.
  -- Adding wilds to natural melds converts them to black melds, making it harder
  -- to build a 2nd red book.  Exception: hand-emptying plays for foot pickup.
  -- Exception: completing a WILD BOOK is always allowed — wild books are independent
  -- of the red/black book requirement and score 1500 pts regardless.
  local projRedVal = projRed or state.bookCounts.red

  -- Combined total of all existing wild meld cards on table (2s and Jokers may live in
  -- separate piles but can be consolidated by the executor into one 7-card wild book).
  -- Used throughout Phases 2–5 to detect wild book completability.
  local combinedWildOnTable = 0
  for _, m in pairs(melds) do
    if m.isWildMeld and m.obj ~= nil then combinedWildOnTable = combinedWildOnTable + m.total end
  end

  local canCompleteWildBook = false
  do
    if combinedWildOnTable > 0 and combinedWildOnTable + state.wildCount >= 7 then
      canCompleteWildBook = true   -- combined wild meld piles + hand wilds reach 7
    elseif not melds["2"] and not melds["Joker"] and state.wildCount >= 7 then
      canCompleteWildBook = true   -- no wild meld yet; Phase 4 creates one from 7+ wilds
    end
  end

  -- Diagnostic summary: log all key gate values so pasted plan output is self-explanatory.
  L(string.format(
    "evalWilds: projRed=%d hasFoot=%s needBlack=%s otherFoot=%s oppPressure=%s(other=%d) wildOnTable=%d canCompleteWild=%s",
    projRedVal,
    hasFoot and "Y" or "n",
    needBlackBook and "Y" or "n",
    otherFoot and "Y" or "n",
    opponentPressure and "Y" or "n", otherMelds,
    combinedWildOnTable,
    canCompleteWildBook and "Y" or "n"))
  L(string.format(
    "  canEmpty: withWilds=%s viaWildMeld=%s viaPressure=%s viaWildExtend=%s viaWildOnMeld=%s cap=%s",
    canEmptyWithWilds and "Y" or "n",
    canEmptyViaWildMeld and "Y" or "n",
    canEmptyViaPressure and "Y" or "n",
    canEmptyViaWildExtend and "Y" or "n",
    canEmptyViaWildOnMeld and "Y" or "n",
    emptyHandCap == math.huge and "∞" or tostring(emptyHandCap)))

  if not hasFoot and projRedVal < 2
     and not canEmptyWithWilds and not canEmptyViaWildMeld
     and not canEmptyViaWildExtend and not canEmptyViaWildOnMeld
     and not canCompleteWildBook then
    L(string.format("Wild plays: held — build 2 red books first (projected red=%d)", projRedVal))
    return {}
  end
  if canCompleteWildBook and not hasFoot and projRedVal < 2 then
    L("Wild plays: wild book completion allowed (independent of red book count)")
  end

  -- Pre-foot: hold all wilds unless plays this turn can empty the hand for foot pickup,
  -- or an existing wild meld pile can be completed this turn (1500-pt book).
  -- This prevents committing wilds to a new wild meld pile on turns where it doesn't
  -- contribute to picking up the foot.
  if hasFoot and not canEmptyWithWilds and not canEmptyViaWildMeld
             and not canEmptyViaPressure and not canEmptyViaWildExtend
             and not canEmptyViaWildOnMeld and not canCompleteWildBook then
    if state.wildCount > 0 then
      L("Wild plays: held pre-foot — saving wilds for foot pickup and future wild meld")
    end
    return {}
  end
  if hasFoot and canCompleteWildBook then
    L("Wild plays: wild book completion allowed pre-foot (completes 1500-pt book this turn)")
  end

  -- Gather wilds, Jokers first: wilds are consumed in this order by assignWild, so when a
  -- wild book (or any meld) is completed the Jokers go onto the table and any wilds left
  -- HELD in hand are the cheaper 2s — minimising the end-of-hand penalty on held wilds.
  local wildCards = {}
  for _, card in ipairs(state.hand) do
    if card.color == "Wild" then table.insert(wildCards, card) end
  end
  sortWilds(wildCards, true)

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
    -- Always try to merge with an existing alloc for this rank so that multiple wilds
    -- going to the same meld (e.g. Phase 2 while-loop for a pre-existing rank meld)
    -- are batched into one executor entry and played together without a settle gap.
    for i = #allocs, 1, -1 do
      if allocs[i].rank == rank then
        table.insert(allocs[i].wilds, wildCards[nextWild])
        allocs[i].completesBook = allocs[i].completesBook or completesBook
        nextWild = nextWild + 1
        return true
      end
    end
    -- If this rank's naturals are being placed by layoutHandRank, the executor
    -- must not try to place them again.  Clear naturalCards and flag accordingly.
    local naturalsPlaced = meldPlanRanks[rank] == true
    local naturals = (not naturalsPlaced) and (m.naturals or {}) or {}
    m.naturals = {}
    table.insert(allocs, {
      rank                  = rank,
      meldObj               = m.obj,
      naturalCards          = naturals,
      wilds                 = {wildCards[nextWild]},
      existingCount         = m.total - 1,
      isNew                 = m.isNew,
      isWildMeld            = m.isWildMeld,
      naturalsAlreadyPlaced = naturalsPlaced,
      priority              = priority,
      completesBook         = completesBook,
      prevWilds             = m.wilds - 1,
      reason                = reason,
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
    if m.total >= 7 then
      -- Normally can't extend a completed meld.  Exception: a rank meld that is all-natural
      -- (wilds==0) can accept one wild to convert it from a red book to a black book —
      -- but only when we still need a black book AND the meld isn't completing as a red
      -- book this same turn (adding a wild would lose the needed red book).
      if m.wilds == 0 and not m.isWildMeld and needBlackBook and not m.completingRedBook then
        -- fall through to standard checks below
      else
        return false
      end
    end
    if m.isWildMeld then return true end          -- wild melds: no 2-wild cap
    if m.wilds >= 2  then return false end        -- rank melds: enforce 2-wild cap
    if m.obj == nil  then return true end         -- new this turn: always extendable
    -- Pre-existing rank meld: allow when going out, need a black book,
    -- OR the other player's foot is already gone (use wilds rather than discard them).
    return not hasFoot or needBlackBook or not otherFoot
  end

  -- After foot pickup, should a wild be added to this pre-existing rank meld?
  -- YES: the wild completes the book (total + 1 == 7).
  -- YES: total + 1 == 6 and urgency exception (opponent has 3+ books, we have
  --      >= 2 red books, still need black books) — sets up a 1-wild book next turn.
  -- NO:  anything further from completion — keep the wild for a future black/wild book.
  -- Wild melds and new-this-turn melds are not restricted by this predicate.
  local function postFootRankOk(m)
    if hasFoot then return true end
    if m.isWildMeld then return true end
    if m.obj == nil  then return true end
    if m.total + 1 >= 7 then return true end      -- completes book
    if canEmptyViaWildExtend then return true end  -- foot-pickup via wild extend: allow all
    -- Go-out override: if projected books are met this turn, allow placing on any extensible meld
    if projRedVal >= 2 then
      local projBlackSoFar = state.bookCounts.black
      for _, mp in ipairs(meldPlan) do
        if mp.priority == 2 then projBlackSoFar = projBlackSoFar + 1 end
      end
      for _, wa in ipairs(allocs) do
        if wa.completesBook then projBlackSoFar = projBlackSoFar + 1 end
      end
      if projBlackSoFar >= 2 then return true end
    end
    if m.total + 1 == 6 then                       -- one more wild after this = book
      return otherBooks >= 3
         and state.bookCounts.red  >= 2
         and state.bookCounts.black < 2
    end
    return false                                   -- too far from completion
  end

  -- Rank priority for Phase 1 pair selection (highest value first → more points as a book).
  local rankPriority = {
    ["Ace"]=13,["King"]=12,["Queen"]=11,["Jack"]=10,["10"]=9,
    ["9"]=8,["8"]=7,["7"]=6,["6"]=5,["5"]=4,["4"]=3,
  }

  -- Phase 1: hand pairs (exactly 2 naturals, no existing meld) → 1 wild → new rank meld of 3.
  -- When going out (no foot): all pairs eligible, no cap.
  -- Suppressed when needBlackBook unless canEmptyWithWilds / canEmptyViaWildMeld.
  -- canEmptyViaWildMeld: foot on table, 4+ wilds, 1 pair → exactly 1 wild, cap = 1.
  -- canEmptyWithWilds: emptying hand with up to emptyHandCap pairs is beneficial.
  -- Pairs are processed highest-rank first so the cap trims low-value pairs, not high ones.
  local phase1Allowed = canEmptyViaWildMeld or canEmptyWithWilds or canEmptyViaPressure or
                        ((not hasFoot or not otherFoot) and not needBlackBook)
  local phase1Cap
  if canEmptyViaWildMeld then
    phase1Cap = 1
  elseif canEmptyViaPressure then
    phase1Cap = state.wildCount     -- all wilds available; no reserve for wild meld under pressure
  elseif canEmptyWithWilds then
    phase1Cap = emptyHandCap        -- use same cap that made canEmptyWithWilds true
  elseif hasFoot and not otherFoot then
    phase1Cap = 2                   -- regular foot-pickup play (non-emptying)
  else
    phase1Cap = math.huge
  end
  if not phase1Allowed then
    L(string.format("  [p1-skip] pairs suppressed: needBlack=%s hasFoot=%s otherFoot=%s (need empty-flag or no-black-needed)",
      needBlackBook and "Y" or "n", hasFoot and "Y" or "n", otherFoot and "Y" or "n"))
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
        or canEmptyViaPressure
          and string.format("new black meld: 2 × %s + 1 wild (opponent pressure %d melds, %d/%d)", rank, otherMelds, phase1Count+1, phase1Cap)
        or  (hasFoot and not otherFoot)
          and string.format("new black meld: 2 × %s + 1 wild (foot-pickup play, %d/2)", rank, phase1Count+1)
          or  string.format("new black meld: 2 × %s + 1 wild (hand pair)", rank)
      assignWild(rank, 1, label)
      phase1Count = phase1Count + 1
    end
  end

  -- Phases 2 and 3 are skipped when emptying the hand via wild meld (canEmptyViaWildMeld or
  -- canEmptyWithWilds) so remaining wilds flow directly to the Phase 4 wild meld.
  -- Exception: under opponent pressure (canEmptyViaPressure), all wilds go to rank melds
  -- instead of a wild meld — phases 2/3 must run even when canEmptyWithWilds is true.
  if (canEmptyViaWildMeld or canEmptyWithWilds) and not canEmptyViaPressure then
    L("  [p2/3-skip] phases 2/3 skipped — wilds reserved for wild meld (canEmptyWithWilds/ViaWildMeld)")
  end
  if (not canEmptyViaWildMeld and not canEmptyWithWilds) or canEmptyViaPressure then
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
          -- Wild melds: only eligible when adding hand wilds completes a 7-card book (Rule 1).
          -- Never add a partial wild to an existing wild meld — keep it for rank/black books.
          local wildBookComplete = m.isWildMeld
            and (combinedWildOnTable + math.min(wildsLeft, 7 - combinedWildOnTable) >= 7)
          -- Allow when ≥2 red books are projected this turn (projRedVal counts books
          -- completed by natural plays earlier in the same turn).  Execution order
          -- guarantees natural melds land before wilds, so projRedVal is reliable here.
          local eligible = (not suppressWildBook and m.isWildMeld and wildBookComplete)
                        or (not m.isWildMeld and (not needBlackBook
                            or (projRedVal >= 2 and (m.total + math.min(wildsLeft, 2 - m.wilds) >= 7) and colorOk)))
          if eligible then table.insert(preExisting, rank) end
        end
      end
      if needBlackBook then
        -- Sort: wild book completion takes highest priority; otherwise fewest-wilds-needed first.
        table.sort(preExisting, function(a, b)
          local ma, mb = melds[a], melds[b]
          -- When a wild book is achievable (and not suppressed), wild melds sort before all rank melds.
          if not suppressWildBook and canCompleteWildBook and ma.isWildMeld ~= mb.isWildMeld then
            return ma.isWildMeld
          end
          -- Among wild melds, larger pile first (concentrate wilds onto the biggest pile).
          if ma.isWildMeld and mb.isWildMeld then return ma.total > mb.total end
          local na = 7 - ma.total   -- additional wilds needed to reach 7
          local nb = 7 - mb.total
          if na ~= nb then return na < nb end
          return ma.total > mb.total  -- tiebreak: more existing cards first
        end)
        -- Track how many black books Phase 2 projects so we stop at 2.
        -- Wild books (isWildMeld) are not counted against this limit.
        local projBlackPhase2 = 0
        for _, rank in ipairs(preExisting) do
          if nextWild > #wildCards then break end
          local m = melds[rank]
          -- Re-check with remaining wilds: still reachable?
          local wildsLeft = #wildCards - nextWild + 1
          local mc2 = m.colors or {hasRed=false, hasBlack=false}
          local colorOk = mc2.hasRed and mc2.hasBlack
          local wildBookComplete = m.isWildMeld
            and (combinedWildOnTable + math.min(wildsLeft, 7 - combinedWildOnTable) >= 7)
          if wildBookComplete then
            -- Add only the minimum hand wilds needed to complete the book; save extras for rank melds.
            -- Executor merges the smaller wild meld pile into this one to form the 7-card book.
            local neededForBook = math.max(0, 7 - combinedWildOnTable)
            local addedToWild = 0
            while nextWild <= #wildCards and canExtend(m) and addedToWild < neededForBook do
              assignWild(rank, 2, string.format(
                "completes wild book (combined %d on table + %d hand → 7)", combinedWildOnTable, neededForBook))
              addedToWild = addedToWild + 1
            end
          elseif not m.isWildMeld and projRedVal >= 2
              and (m.total + math.min(wildsLeft, 2 - m.wilds) >= 7) and colorOk then
            -- Guard: only convert rank melds to black books when ≥2 red books are projected.
            -- Cap at 2 projected black books: making more black books wastes wilds that could
            -- go into a wild meld, and extra black books don't help reach go-out sooner.
            if state.bookCounts.black + projBlackPhase2 >= 2 then
              L(string.format("  [p2-skip] %s — 2 black books already projected, skipping extra", rank))
              break
            end
            -- Assign all wilds needed to complete this black rank book.
            -- The extra `m.wilds == 0` condition handles melds already at 7+ natural cards
            -- that need exactly one wild to be reclassified from red book to black book.
            while nextWild <= #wildCards and canExtend(m) and (m.total < 7 or m.wilds == 0) do
              local logMsg = (m.total >= 7 and m.wilds == 0)
                and string.format("converts to black book %s (%d-card red meld + wild)", rank, m.total)
                or  string.format("completes black book %s (%d → 7)", rank, m.total)
              assignWild(rank, 2, logMsg)
            end
            projBlackPhase2 = projBlackPhase2 + 1
          end
        end
      else
        -- When not needing a black book (already have 2, or going out), sort by value:
        -- book-completing melds first (total+1 >= 7 → completes a book = more points),
        -- then by rank value (Ace > King > … > 4).  This ensures that when going out,
        -- the wild goes to the meld that actually finishes a book rather than an arbitrary
        -- meld that passes the go-out override in postFootRankOk.
        table.sort(preExisting, function(a, b)
          local ma, mb = melds[a], melds[b]
          local ac = (ma.total + 1 >= 7) and 1 or 0
          local bc = (mb.total + 1 >= 7) and 1 or 0
          if ac ~= bc then return ac > bc end
          -- Both complete or both don't: prefer the one closest to book (more existing cards)
          if ma.total ~= mb.total then return ma.total > mb.total end
          return (rankPriority[a] or 0) > (rankPriority[b] or 0)
        end)
        for _, rank in ipairs(preExisting) do
          if nextWild > #wildCards then break end
          local m = melds[rank]
          if m.isWildMeld then
            -- Wild meld reached preExisting only because wildBookComplete was true.
            -- Add only the minimum hand wilds needed; save extras for rank melds.
            local neededForBook = math.max(0, 7 - combinedWildOnTable)
            local addedToWild = 0
            while nextWild <= #wildCards and canExtend(m) and addedToWild < neededForBook do
              assignWild(rank, 2, string.format(
                "completes wild book (combined %d on table + %d hand → 7)", combinedWildOnTable, neededForBook))
              addedToWild = addedToWild + 1
            end
          elseif not postFootRankOk(m) then
            L(string.format("  [w-skip] %s — post-foot: wild would not complete book (%d cards)", rank, m.total))
          else
            local mc2r = m.colors or {hasRed=false, hasBlack=false}
            if not (mc2r.hasRed and mc2r.hasBlack) then
              L(string.format("  [w-skip] %s — single-color meld, wild can't make a valid black book", rank))
            else
              assignWild(rank, 2, string.format("extends black meld %s (%d cards on table)", rank, m.total))
            end
          end
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

    -- Phase 1 retry: Phase 2 just satisfied the black-book requirement, which means
    -- pair melds that were blocked by needBlackBook are now eligible.  Re-run Phase 1
    -- for any remaining pairs, but only post-foot (pre-foot pair logic is handled by the
    -- canEmpty* flags which were already evaluated).
    if not phase1Allowed and not hasFoot and not needBlackBook and nextWild <= #wildCards then
      L("  [p1-retry] Phase 2 completed 2nd black book — processing unlocked pairs")
      local eligiblePairs = {}
      for rank, count in pairs(state.handByRank) do
        if isEligibleRank(rank) and count == 2 and not melds[rank] and not meldPlanRanks[rank] then
          table.insert(eligiblePairs, rank)
        end
      end
      table.sort(eligiblePairs, function(a, b)
        return (rankPriority[a] or 0) > (rankPriority[b] or 0)
      end)
      for _, rank in ipairs(eligiblePairs) do
        if nextWild > #wildCards then break end
        local naturalCards = {}
        for _, card in ipairs(state.hand) do
          if card.rank == rank then table.insert(naturalCards, card) end
        end
        melds[rank] = {rank=rank, obj=nil, total=2, wilds=0, isNew=true,
                       isWildMeld=false, naturals=naturalCards, colors={hasRed=false, hasBlack=false}}
        assignWild(rank, 1, string.format(
          "new black meld: 2 × %s + 1 wild (pairs unlocked by 2nd black book)", rank))
      end
    end

    -- Phase 3: remaining wilds → fewest-cards-first.
    -- Rank melds only when player has no foot (via canExtend).
    -- Wild melds: only eligible when the combined pile will reach 7 this turn (Rule 1).
    -- Dynamic combinedNow re-evaluated each iteration so partial adds stop once book is done.
    while nextWild <= #wildCards do
      local candidates = {}
      -- Recompute combined wild total dynamically (assignWild updates m.total in-place).
      local combinedNow = 0
      for _, m in pairs(melds) do
        if m.isWildMeld then combinedNow = combinedNow + m.total end
      end
      for _, m in pairs(melds) do
        if canExtend(m) then
          local wildsLeft = #wildCards - nextWild + 1
          local mc2 = m.colors or {hasRed=false, hasBlack=false}
          local colorOk = mc2.hasRed and mc2.hasBlack
          -- Wild melds: only if combined total will reach exactly 7 and book not yet complete.
          local wildBookComplete = not suppressWildBook and m.isWildMeld and combinedNow < 7
            and (combinedNow + math.min(wildsLeft, 7 - combinedNow) >= 7)
          -- Rank melds must have at least one card of each suit-color before a wild
          -- can make them a valid black book (red card + black card required).
          local mc3 = m.colors or {hasRed=false, hasBlack=false}
          local rankEligible = not m.isWildMeld
            and (mc3.hasRed and mc3.hasBlack)
            and (not needBlackBook or (projRedVal >= 2 and m.total + math.min(wildsLeft, 2 - m.wilds) >= 7))
            and postFootRankOk(m)
          if wildBookComplete or rankEligible then table.insert(candidates, m) end
        end
      end
      if #candidates == 0 then break end
      local wildsLeft = #wildCards - nextWild + 1
      table.sort(candidates, function(a, b)
        -- Wild book completion takes priority; among wild melds, larger pile first.
        if a.isWildMeld ~= b.isWildMeld then return a.isWildMeld end
        if a.isWildMeld and b.isWildMeld then return a.total > b.total end
        -- Tier 1: adding THIS ONE wild completes a book (total + 1 >= 7).
        local aCompletes = (a.total + 1 >= 7)
        local bCompletes = (b.total + 1 >= 7)
        if aCompletes ~= bCompletes then return aCompletes end
        -- Tier 2: book completable within the remaining wilds budget (accounting for
        -- the 2-wild-per-rank-meld cap).  Concentrate wilds here rather than spreading
        -- them across melds that won't become books.  Prefer highest rank = more points.
        local aMaxAdd = a.isWildMeld and wildsLeft or math.min(wildsLeft, 2 - a.wilds)
        local bMaxAdd = b.isWildMeld and wildsLeft or math.min(wildsLeft, 2 - b.wilds)
        local aCanBook = not aCompletes and a.total < 7 and (a.total + aMaxAdd >= 7)
        local bCanBook = not bCompletes and b.total < 7 and (b.total + bMaxAdd >= 7)
        if aCanBook ~= bCanBook then return aCanBook end
        if aCanBook and bCanBook then
          return (rankPriority[a.rank] or 0) > (rankPriority[b.rank] or 0)
        end
        return a.total < b.total  -- Tier 3: fewest cards first (minimal extension)
      end)
      local placed = false
      for _, m in ipairs(candidates) do
        if canExtend(m) then  -- re-check: assignWild may have updated m.wilds/m.total
          local reason
          if m.isWildMeld then
            reason = string.format("completes wild book (combined %d on table + hand → 7)", combinedNow)
          elseif m.total + 1 >= 7 then
            reason = string.format("completes black book %s (%d → 7)", m.rank, m.total)
          else
            reason = string.format("extends black meld %s (%d cards, fewest-first)", m.rank, m.total)
          end
          placed = assignWild(m.rank, 3, reason)
          if placed then break end
        end
      end
      if not placed then break end
    end
  end

  -- Phase 4: if 3+ wilds still unallocated and no wild meld exists on the table,
  -- bundle them into a new pure wild meld.
  -- Suppressed under opponent pressure pre-foot: all wilds went to rank melds (phases 1-3).
  -- Suppressed when needBlackBook unless a hand-emptying flag is set or the wild book
  -- can be completed this turn: wilds are more valuable as future black-book converters.
  local wildsLeft4 = #wildCards - nextWild + 1
  local canEmptyAny = canEmptyWithWilds or canEmptyViaWildMeld or canEmptyViaPressure
                   or canEmptyViaWildExtend or canEmptyViaWildOnMeld
  local allowPhase4 = not (hasFoot and opponentPressure)
                   and not canEmptyViaWildExtend
                   and not suppressWildBook
                   and (not needBlackBook or canCompleteWildBook or canEmptyAny)
  if wildsLeft4 >= 3 and (melds["2"] or melds["Joker"]) then
    L("  [p4-skip] wild meld already exists on table — extending in phase 5")
  elseif wildsLeft4 >= 3 and not allowPhase4 then
    L(string.format("  [p4-skip] new wild meld suppressed: oppPressure=%s canEmptyViaWildExtend=%s needBlack=%s",
      (hasFoot and opponentPressure) and "Y" or "n", canEmptyViaWildExtend and "Y" or "n",
      needBlackBook and "Y" or "n"))
  elseif wildsLeft4 < 3 and wildsLeft4 > 0 then
    L(string.format("  [p4-skip] only %d wild(s) left — need 3+ for new wild meld", wildsLeft4))
  end
  if wildsLeft4 >= 3 and not melds["2"] and not melds["Joker"] and allowPhase4 then
    -- Cap the new wild book at exactly 7 cards.  A fresh pile starts from 0 wilds on the
    -- table, so the cap is a flat 7.  Extra wilds beyond the 7 needed are deliberately NOT
    -- dumped here — they stay in hand (held) so they can convert OTHER rank melds into
    -- black books on a later turn.  (evalDiscard never discards a wild unless the whole
    -- hand is wild, so leftovers are genuinely saved, not lost.)  The only thing that
    -- places these extras directly this turn is the go-out path, which must empty the hand.
    local assigned = {}
    while nextWild <= #wildCards and #assigned < 7 do
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
        local wildsLeft5 = #wildCards - nextWild + 1
        -- Wild melds: existing pile (obj ~= nil) can always absorb a leftover wild — a lone wild
        -- belongs on the wild meld rather than converting a rank meld to black.  New wild meld
        -- (obj==nil, created by Phase 4): only add when it would complete the book (Phase 4
        -- consumed all wilds, so this case rarely arises in Phase 5 anyway).
        local combinedNow5 = 0
        for _, wm in pairs(melds) do if wm.isWildMeld then combinedNow5 = combinedNow5 + wm.total end end
        local wildMeldOk = not m.isWildMeld
                        or (not suppressWildBook and m.obj ~= nil and combinedNow5 < 7 and combinedNow5 + wildsLeft5 >= 7)  -- existing wild meld: only if can complete
                        or (not suppressWildBook and m.obj == nil and combinedNow5 < 7 and combinedNow5 + wildsLeft5 >= 7)
        local freePlace  = canEmptyWithWilds or canEmptyViaWildMeld or canEmptyViaPressure
                        or canEmptyViaWildExtend or canEmptyViaWildOnMeld
        -- (note: `not hasFoot` deliberately excluded — post-foot rank-meld wilds require
        -- state.bookCounts.red>=2 gate below, so freePlace only lifts that gate in hand-emptying scenarios)
        -- HARD RULE: a rank book must contain both a red-suit AND a black-suit natural.  A wild
        -- may COMPLETE a rank meld into a book (reach 7) only if the meld already has both
        -- colours — this is NOT waived for hand-emptying (freePlace).  Below 7 (not completing a
        -- book), free-placing a leftover wild onto a single-colour meld is fine (stays open).
        local mc5 = m.colors or {hasRed=false, hasBlack=false}
        local hasBothColors5 = mc5.hasRed and mc5.hasBlack
        local completesBook5 = (m.total + 1 >= 7)
        local colorOk5
        if m.isWildMeld then
          colorOk5 = true
        elseif completesBook5 then
          colorOk5 = hasBothColors5              -- book completion always needs both colours
        else
          colorOk5 = freePlace or hasBothColors5 -- not completing a book: leftover wild OK
        end
        local eligible   = wildMeldOk
                        and colorOk5
                        and postFootRankOk(m)
                        and (m.isWildMeld or freePlace or not needBlackBook or projRedVal >= 2)
        if eligible then table.insert(candidates, m) end
      end
    end
    if #candidates == 0 then break end
    -- Prefer existing wild meld over rank melds: a leftover wild belongs on the wild meld pile
    -- rather than converting a red rank meld to black.  Among same type: book-completing first,
    -- then fewest cards first.
    table.sort(candidates, function(a, b)
      local aExWild = a.isWildMeld and a.obj ~= nil
      local bExWild = b.isWildMeld and b.obj ~= nil
      if aExWild ~= bExWild then return aExWild end
      if not a.isWildMeld and not b.isWildMeld then
        local aCompletes = (a.total + 1 >= 7)
        local bCompletes = (b.total + 1 >= 7)
        if aCompletes ~= bCompletes then return aCompletes end
      end
      return a.total < b.total
    end)
    local placed = false
    for _, m in ipairs(candidates) do
      if canExtend(m) then
        local p5reason
        if m.isWildMeld then
          p5reason = string.format("extends wild meld (%d cards, avoids wild discard)", m.total)
        elseif m.total + 1 >= 7 then
          p5reason = string.format("completes black book %s (%d → 7)", m.rank, m.total)
        else
          p5reason = string.format("extends black meld %s (%d cards)", m.rank, m.total)
        end
        placed = assignWild(m.rank, 5, p5reason)
        if placed then break end
      end
    end
    if not placed then break end
  end

  return allocs
end

function buildTurnPlan(sColor)
  pcall(function() debugHand(sColor) end)   -- TEMP hotseat diagnostic (remove after diagnosing)
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

  -- Detect whether any opponent has 3 of the 4 required books (2 red + 2 black).
  -- When true, book-extension plays (p5) are permitted — opponent is one book from winning.
  local anyOpponentNearGoOut = false
  pcall(function()
    for _, color in ipairs(playerList or {}) do
      if color ~= sColor then
        local oppRed, oppBlack = 0, 0
        for _, m in ipairs(getMelds(color)) do
          if m.isBook then
            local bt = classifyBook(m.obj)
            if bt == "red"   then oppRed   = oppRed   + 1 end
            if bt == "black" then oppBlack = oppBlack + 1 end
          end
        end
        local oppScore = math.min(oppRed, 2) + math.min(oppBlack, 2)
        if oppScore >= 3 then
          L(string.format("Opp near go-out: %s has %dR+%dB books (%d of 4 required)",
            color, oppRed, oppBlack, oppScore))
          anyOpponentNearGoOut = true
        end
      end
    end
  end)

  local melds = evalMeldsToPlay(state, anyOpponentNearGoOut)
  local hadMeldPlans = (#melds > 0)

  -- Cap red-book completions when we still need black books.
  --
  -- Only near-black melds (exactly 6 cards) can become black books with a single wild,
  -- so they are the only valid reserves.  The cap has two parts:
  --
  --   baseReds  = max(0, 2 - redBooks)   — reds still needed to reach the 2-book minimum
  --   extraReds = max(0, nearBlack - blackNeeded)
  --               — extras allowed only when near-black melds exceed the requirement
  --                 (each extra red consumes one near-black meld, so the remainder
  --                 must still cover all outstanding black books)
  --   redCap = baseReds + extraReds
  --
  -- Example: 1 red, 0 black, 2 near-black melds
  --   baseReds=1  extraReds=max(0,2-2)=0  → redCap=1  (make 1 red; keep both 6-card
  --   melds — but one is consumed by baseReds, leaving 1 for black; see note below)
  --
  -- Example: 2 red, 1 black, 3 near-black melds
  --   baseReds=0  extraReds=max(0,3-1)=2  → redCap=2  (2 extra reds; 1 near-black left)
  --
  -- Lifted entirely when black books >= 2.
  -- For demoted plays: fill naturals up to 6 then stop; Phase 2 adds the wild directly.
  if not state.hasFoot and state.bookCounts.black < 2 then
    local blackNeeded = 2 - state.bookCounts.black

    -- Count near-black melds: exactly 6 cards total (naturals + embedded wilds).
    local nearBlackCount = 0
    for _, meld in pairs(state.meldsByRank) do
      if (meld.count or 0) + (meld.embeddedWilds or 0) == 6 then
        nearBlackCount = nearBlackCount + 1
      end
    end

    local baseReds  = math.max(0, 2 - state.bookCounts.red)
    local extraReds = math.max(0, nearBlackCount - blackNeeded)
    local redCap    = baseReds + extraReds

    local p1Seen = 0
    local cappedMelds = {}
    for _, m in ipairs(melds) do
      if m.priority == 1 then
        p1Seen = p1Seen + 1
        if p1Seen > redCap then
          -- Demote: extend meld to 6 naturals max so 1 wild completes it as a black book.
          local fillTo6 = 6 - m.existingCount
          if fillTo6 <= 0 then
            -- Already at 6+ naturals — skip play; Phase 2 adds the wild to finish black.
          else
            local playCount = math.min(fillTo6, #m.cards)
            local trimmed = {}
            for i = 1, playCount do trimmed[i] = m.cards[i] end
            m.cards    = trimmed
            m.count    = playCount
            m.priority = 3
            m.partial  = false
            m.reason   = string.format(
              "extends red meld (capped %d+%d=6, reserve for black book)", m.existingCount, playCount)
            table.insert(cappedMelds, m)
          end
        else
          table.insert(cappedMelds, m)
        end
      else
        table.insert(cappedMelds, m)
      end
    end
    melds = cappedMelds
  end

  -- Projected red book count from natural meld plays only (used to gate wild allocation).
  local projRedFromMelds = state.bookCounts.red
  for _, m in ipairs(melds) do
    if m.priority == 1 then projRedFromMelds = projRedFromMelds + 1 end
  end

  -- Compute wild allocs now (needed for go-out projection), but only keep them
  -- if the plan actually results in going out this turn.
  local preWildAllocLogLen = #log
  local wildAllocs = evalWildAllocations(state, melds, L, projRedFromMelds)

  -- Combined opening minimum check: verify that natural-meld points + actually-allocated
  -- wild points together meet the hand's opening minimum.  This runs after evalWildAllocations
  -- so we know which wilds are truly played (pre-foot wilds may be held/suppressed).
  -- Only fires when natural plans existed AND the player hasn't opened yet.
  if hadMeldPlans and not hasExistingMeldsOrBooks(state) then
    local minimum  = gi_OPENING_MELD_MIN[giHand] or 50
    local totalPts = alreadyPlayedOpeningPts(state)
    for _, m in ipairs(melds) do
      for _, card in ipairs(m.cards) do
        if card.rank ~= "3" then totalPts = totalPts + scoreCard(card.obj) end
      end
    end
    for _, wa in ipairs(wildAllocs) do
      for _, card in ipairs(wa.wilds) do totalPts = totalPts + scoreCard(card.obj) end
      for _, card in ipairs(wa.naturalCards) do
        if card.rank ~= "3" then totalPts = totalPts + scoreCard(card.obj) end
      end
    end
    if totalPts < minimum then
      -- Truncate log entries added by the first evalWildAllocations run, then suppress.
      while #log > preWildAllocLogLen do table.remove(log) end
      melds = {}
      projRedFromMelds = state.bookCounts.red
      wildAllocs = evalWildAllocations(state, {}, L, projRedFromMelds)
      L(string.format(
        "Natural melds: suppressed — opening minimum %d pts not met (combined %d pts, hand %d)",
        minimum, totalPts, giHand))
    end
  end

  -- Second-pass natural plays: when a wild completes a black book for rank R and the hand
  -- still has naturals of R, dump them onto that book.  GATE: only for a genuine GO-OUT
  -- setup.  Otherwise it over-fills a book the wild already completes to 7 — and because the
  -- executor plays naturals BEFORE wilds, that extra natural lands first, makes a RED book,
  -- moves it, and strands the wild (C# ref error).  Go-out setup = post-foot, >=2 red
  -- projected, and these wilds reach the 2nd black book (the only case dumping naturals helps).
  local blackCompletions = 0
  for _, wa in ipairs(wildAllocs) do
    if wa.completesBook and not wa.isWildMeld and wa.rank ~= "__wild__" then
      blackCompletions = blackCompletions + 1
    end
  end
  local secondPassOk = (not state.hasFoot) and (projRedFromMelds >= 2)
                       and (state.bookCounts.black + blackCompletions >= 2)
  if secondPassOk then
  for _, wa in ipairs(wildAllocs) do
    if wa.completesBook and not wa.isWildMeld and wa.rank ~= "__wild__" then
      local rank = wa.rank
      local handCount = state.handByRank[rank] or 0
      if handCount > 0 then
        local alreadyInMelds = false
        for _, m in ipairs(melds) do
          if m.rank == rank then alreadyInMelds = true; break end
        end
        if not alreadyInMelds then
          local cards = {}
          for _, card in ipairs(state.hand) do
            if card.rank == rank then table.insert(cards, card) end
          end
          if #cards > 0 then
            table.insert(melds, {
              rank=rank, cards=cards, count=#cards,
              existingCount=7,   -- wild will have completed the meld to 7 before execution
              priority=5,
              meldColor="black",
              reason=string.format("extends black book (wild completes meld first): %d from hand", #cards),
              partial=false,
            })
          end
        end
      end
    end
  end
  end  -- if secondPassOk

  -- Log melds (after potential opening minimum suppression).
  if #melds == 0 then
    if hadMeldPlans then
      -- already logged the suppression reason above
    elseif not hasExistingMeldsOrBooks(state) then
      L("Natural melds: nothing eligible (need 3+ of a rank, opening minimum not met)")
    else
      L("Natural melds: nothing eligible (need 3+ of a rank)")
    end
  else
    for _, m in ipairs(melds) do
      L(string.format("  [p%d] %s — %s", m.priority, m.rank, m.reason))
    end
  end

  -- Projected book counts and remaining hand size after all planned plays.
  local projRed   = state.bookCounts.red
  local projBlack = state.bookCounts.black
  -- Track p2 ranks for reference (meld plans that INTEND to complete a black book with wilds).
  local p2Ranks = {}
  for _, m in ipairs(melds) do
    if m.priority == 1 then projRed = projRed + 1 end  -- completes red book (naturals only, certain)
    if m.priority == 2 then p2Ranks[m.rank] = true end
  end
  -- projBlack comes ONLY from wildAllocs that actually complete a rank book this turn.
  -- Wild book completion (isWildMeld / "__wild__") does NOT count as a black book for go-out.
  -- A p2 meld only becomes a black book if its wilds were actually allocated — by deriving
  -- projBlack from wildAllocs we automatically handle the case where wilds went elsewhere.
  for _, wa in ipairs(wildAllocs) do
    if wa.completesBook and not wa.isWildMeld and wa.rank ~= "__wild__" then
      projBlack = projBlack + 1
    end
  end
  -- Also count p2 melds that complete a black book purely from natural plays: the existing
  -- meld already has an embedded wild so no new wild alloc is needed.  These are missed by
  -- the wildAllocs loop above because evalWildAllocations correctly skips them (the meld is
  -- already at 7 after the naturals and canExtend returns false).
  for _, m in ipairs(melds) do
    if m.priority == 2 then
      local hasAlloc = false
      for _, wa in ipairs(wildAllocs) do
        if not wa.isWildMeld and wa.rank == m.rank and wa.completesBook then
          hasAlloc = true; break
        end
      end
      if not hasAlloc then
        local mInfo = state.meldsByRank[m.rank]
        if mInfo and (mInfo.embeddedWilds or 0) > 0 then
          projBlack = projBlack + 1
        end
      end
    end
  end

  local cardsConsumed = 0
  for _, m in ipairs(melds) do cardsConsumed = cardsConsumed + m.count end
  for _, wa in ipairs(wildAllocs) do
    cardsConsumed = cardsConsumed + #wa.wilds + #wa.naturalCards
  end
  local projHandCount = state.handCount - cardsConsumed

  -- Go-out p5 extension: projected books are met this turn but the hand still has
  -- natural cards that evalMeldsToPlay couldn't account for (state.canGoOut was false
  -- at snapshot time, or the 3rd-red-book suppression skipped them).  Play those cards
  -- onto existing books or open melds to empty the hand and go out.
  if not state.hasFoot and projRed >= 2 and projBlack >= 2 and projHandCount > 1 then
    -- Build destination lookups: existing books and open melds (non-book).
    local bookByRank = {}
    for _, btype in ipairs({"red", "black"}) do
      for _, b in ipairs(state.books[btype]) do
        if b.rank then
          bookByRank[b.rank] = {obj=b.obj, btype=btype, isBook=true}
        end
      end
    end
    -- Diagnostic: log what books and hand cards the extension sees.
    local bookRankList = {}
    for r in pairs(bookByRank) do table.insert(bookRankList, r) end
    L(string.format("  [p5-ext] fired: projHand=%d books={%s} hand=%d",
      projHandCount, table.concat(bookRankList, ","),
      #state.hand))
    local openMeldByRank = {}
    for rank, meldInfo in pairs(state.meldsByRank) do
      if not bookByRank[rank] then
        local wildCt = countMeldWilds(meldInfo.obj) + (meldInfo.embeddedWilds or 0)
        openMeldByRank[rank] = {obj=meldInfo.obj, btype=(wildCt > 0 and "black" or "red"),
                                count=meldInfo.count, isBook=false}
      end
    end
    -- Count how many naturals of each rank the current plan already consumes.
    local consumedNat = {}
    for _, m in ipairs(melds) do
      consumedNat[m.rank] = (consumedNat[m.rank] or 0) + m.count
    end
    for _, wa in ipairs(wildAllocs) do
      if wa.rank and wa.rank ~= "__wild__" then
        consumedNat[wa.rank] = (consumedNat[wa.rank] or 0) + #wa.naturalCards
      end
    end
    -- Collect remaining non-wild, non-3 hand cards that have any valid destination.
    local byRank, rankOrder = {}, {}
    for _, card in ipairs(state.hand) do
      if card.color ~= "Wild" and card.rank ~= "3" then
        local dest = bookByRank[card.rank] or openMeldByRank[card.rank]
        if dest then
          local used = consumedNat[card.rank] or 0
          if used < (state.handByRank[card.rank] or 0) then
            if not byRank[card.rank] then
              table.insert(rankOrder, card.rank)
              byRank[card.rank] = {cards={}, dest=dest}
            end
            table.insert(byRank[card.rank].cards, card)
            consumedNat[card.rank] = used + 1
          end
        end
      end
    end
    -- Add a p5 meld entry for each eligible rank and update projHandCount.
    for _, rank in ipairs(rankOrder) do
      local entry = byRank[rank]
      local cards, dest = entry.cards, entry.dest
      local existCount = dest.count or 7
      if dest.isBook then
        pcall(function() existCount = dest.obj.getQuantity() end)
      end
      local destLabel = dest.isBook and (dest.btype .. " book") or (dest.btype .. " meld")
      table.insert(melds, {
        rank=rank, cards=cards, count=#cards,
        existingCount=existCount, priority=5,
        meldColor=dest.btype,
        reason=string.format("extends %s for go-out: %d card(s) from hand", destLabel, #cards),
        partial=false,
      })
      cardsConsumed = cardsConsumed + #cards
      projHandCount = state.handCount - cardsConsumed
      L(string.format("  [p5-goout] %s — %d card(s) onto %s (go-out extension)",
        rank, #cards, destLabel))
    end
  end

  -- Go-out via new wild meld: books are met but projHandCount > 1 because remaining
  -- cards are all wilds plus exactly one natural (the discard).  Play all remaining
  -- wilds as a new wild meld so the natural becomes the discard and the hand empties.
  if not state.hasFoot and projRed >= 2 and projBlack >= 2 and projHandCount > 1 then
    local wildConsumed = 0
    for _, wa in ipairs(wildAllocs) do wildConsumed = wildConsumed + #wa.wilds end
    local wildRemaining    = state.wildCount - wildConsumed
    local naturalRemaining = projHandCount - wildRemaining
    if naturalRemaining == 1 and wildRemaining >= 3 then
      local allocedGuids = {}
      for _, wa in ipairs(wildAllocs) do
        for _, wc in ipairs(wa.wilds) do
          pcall(function() allocedGuids[wc.obj.getGUID()] = true end)
        end
      end
      local wildsLeft = {}
      for _, card in ipairs(state.hand) do
        if card.color == "Wild" then
          local guid; local ok = pcall(function() guid = card.obj.getGUID() end)
          if ok and guid and not allocedGuids[guid] then
            table.insert(wildsLeft, card)
          end
        end
      end
      if #wildsLeft >= 3 then
        table.insert(wildAllocs, {
          rank="__wild__", wilds=wildsLeft, naturalCards={},
          meldObj=nil, isNew=true, isWildMeld=true,
          completesBook=false, naturalsAlreadyPlaced=false, priority=4,
          reason=string.format("go-out: new wild meld (%d wilds)", #wildsLeft),
        })
        cardsConsumed = cardsConsumed + #wildsLeft
        projHandCount = state.handCount - cardsConsumed
        L(string.format("  [go-out wild meld] %d wilds → new wild meld, 1 natural left to discard",
          #wildsLeft))
      end
    elseif naturalRemaining == 1 and wildRemaining >= 1 then
      -- Case A3: 1 natural remains as the discard; place 1-2 unallocated wilds on
      -- existing open rank melds to empty the hand.
      local allocedGuids = {}
      for _, wa in ipairs(wildAllocs) do
        for _, wc in ipairs(wa.wilds) do
          pcall(function() allocedGuids[wc.obj.getGUID()] = true end)
        end
      end
      local wildsToPlace = {}
      for _, card in ipairs(state.hand) do
        if card.color == "Wild" then
          local guid; local ok = pcall(function() guid = card.obj.getGUID() end)
          if ok and guid and not allocedGuids[guid] then
            table.insert(wildsToPlace, card)
          end
        end
      end
      if #wildsToPlace >= wildRemaining then
        local openMelds = {}
        for rank, meldInfo in pairs(state.meldsByRank) do
          local isBook = false
          for _, btype in ipairs({"red", "black"}) do
            for _, b in ipairs(state.books[btype]) do
              if b.rank == rank then isBook = true; break end
            end
            if isBook then break end
          end
          if not isBook and meldInfo.count < 7 then
            local wildCt = 0
            pcall(function() wildCt = countMeldWilds(meldInfo.obj) end)
            wildCt = wildCt + (meldInfo.embeddedWilds or 0)
            local allocWilds = 0
            for _, wa in ipairs(wildAllocs) do
              if wa.rank == rank then allocWilds = allocWilds + #wa.wilds end
            end
            if wildCt + allocWilds < 2 then
              table.insert(openMelds, {rank=rank, meldInfo=meldInfo,
                wilds=wildCt+allocWilds, total=meldInfo.count})
            end
          end
        end
        table.sort(openMelds, function(a, b)
          if a.total ~= b.total then return a.total > b.total end
          return a.wilds < b.wilds
        end)
        local placed = 0
        for _, dest in ipairs(openMelds) do
          if placed >= wildRemaining then break end
          local canAbsorb = math.min(2 - dest.wilds, wildRemaining - placed)
          for i = 1, canAbsorb do
            local wc = wildsToPlace[placed + 1]
            if not wc then break end
            local existingAlloc = nil
            for _, wa in ipairs(wildAllocs) do
              if wa.rank == dest.rank then existingAlloc = wa; break end
            end
            if existingAlloc then
              table.insert(existingAlloc.wilds, wc)
            else
              table.insert(wildAllocs, {
                rank=dest.rank, wilds={wc}, naturalCards={},
                meldObj=dest.meldInfo.obj, isNew=false, isWildMeld=false,
                completesBook=false, naturalsAlreadyPlaced=true, priority=4,
                reason=string.format("go-out: extends %s meld (1 wild to empty hand)", dest.rank),
              })
            end
            placed = placed + 1
            dest.wilds = dest.wilds + 1
          end
        end
        if placed >= wildRemaining then
          cardsConsumed = cardsConsumed + placed
          projHandCount = state.handCount - cardsConsumed
          L(string.format("  [go-out A3] placed %d wild(s) on existing meld(s), 1 natural left to discard",
            placed))
        end
      end
    end
  end

  -- evalGoOut may have returned should=true purely on books/foot state, without
  -- knowing what plays are possible this turn.  Override to false if the planned
  -- plays don't actually reduce the hand to 0-1 cards.
  if goOut.should and projHandCount > 1 then
    goOut = {should=false, reason=string.format(
      "books met but %d cards remain after plays", projHandCount)}
    L("Go out: deferred — " .. goOut.reason)
  end

  -- If the plan empties the hand and book requirements are met, this IS a go-out.
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
  --   OR
  --   (c) wild book completion: evalWildAllocations found a wild-meld alloc that completes
  --       a 7-card wild book.  Wild books score 1500 pts; always complete them unless the
  --       current plan already goes out without the wild plays.
  -- Wild cards are NEVER discarded unless all remaining cards are wild (evalDiscard rule 8).
  local needsBlackBooks = not state.hasFoot and projRed >= 2 and state.bookCounts.black < 2
  -- Detect whether evalWildAllocations identified a wild book completion opportunity.
  local wildBookAlloc = false
  for _, wa in ipairs(wildAllocs) do
    if wa.isWildMeld then wildBookAlloc = true; break end
  end
  local allowWilds =
    ((projHandCount <= 1) and (not state.otherFootOnTable or goOut.should or state.hasFoot))
    or needsBlackBooks
    or (wildBookAlloc and not goOut.should)   -- (c) wild book completion

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
    if wildBookAlloc and not goOut.should and not needsBlackBooks and projHandCount > 1 then
      L("Wild plays: allowed — completing wild book (1500 pts, independent of go-out)")
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
  local preWildPruneCount = #wildAllocs   -- used by go-out recovery pass below
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
          local toFree = 2 - proj2
          -- Two trim strategies depending on alloc type:
          --   NEW wild meld (isNew, not completing): trim down to 3-card minimum.
          --   EXISTING wild meld (not isNew): trim as few as possible and let step 2
          --     prune any p3/p4 naturals for the remainder — maximises wilds played.
          --     E.g. hand=6 (1 natural + 5 wilds), toFree=2: trim 1 wild (not 2) so
          --     step 2 prunes the natural, leaving 4 wilds played and a non-wild discard.
          local canTrim, wildTrim
          if wa.isWildMeld then
            if wa.isNew and not wa.completesBook then
              wildTrim = toFree
              canTrim  = (#wa.wilds - wildTrim >= 3)
            elseif not wa.isNew then
              local naturalCanFree = 0
              for _, m in ipairs(melds) do
                if m.priority >= 3 then naturalCanFree = naturalCanFree + m.count end
              end
              wildTrim = math.max(1, toFree - naturalCanFree)
              canTrim  = (#wa.wilds - wildTrim >= 1)
            end
          end
          if canTrim then
            for k = 1, wildTrim do table.remove(wa.wilds, #wa.wilds) end
            wa.completesBook = false
            wa.reason = wa.reason .. string.format(" (trimmed to %d)", #wa.wilds)
            L(string.format("Wild meld trimmed to %d wilds (hand too small)", #wa.wilds))
            proj2 = proj2 + wildTrim
            if not wa.isNew then
              i = i + 1  -- advance: step 2 handles remaining slack via natural pruning
            end
          else
            proj2 = proj2 + #wa.wilds + #wa.naturalCards
            L(string.format("Wild alloc pruned (hand too small): %s", wa.rank))
            table.remove(wildAllocs, i)
          end
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
      local displayRank2 = (wa.isWildMeld or wa.rank == "__wild__") and "wild-meld" or wa.rank
      L(string.format("  [w%d] %s — %s (recomputed after pruning)", wa.priority, displayRank2, wa.reason))
    end

    -- The recomputed wildAllocs may consume cards that the pruning step had freed,
    -- pulling projHandCount back below 2 without a go-out.  Re-run the size guard.
    if not goOut.should then
      local consumed3 = 0
      for _, m  in ipairs(melds)      do consumed3 = consumed3 + m.count                    end
      for _, wa in ipairs(wildAllocs) do consumed3 = consumed3 + #wa.wilds + #wa.naturalCards end
      local proj3 = state.handCount - consumed3
      if proj3 < 2 then
        table.sort(wildAllocs, function(a, b) return a.priority > b.priority end)
        local i = 1
        while proj3 < 2 and i <= #wildAllocs do
          local wa = wildAllocs[i]
          local toFree3 = 2 - proj3
          -- Extending existing wild meld: trim in-place rather than removing entirely.
          if wa.isWildMeld and not wa.isNew and (#wa.wilds - toFree3 >= 1) then
            for k = 1, toFree3 do table.remove(wa.wilds, #wa.wilds) end
            wa.completesBook = false
            wa.reason = wa.reason .. string.format(" (trimmed to %d)", #wa.wilds)
            L(string.format("Wild alloc re-trimmed to %d wilds (hand too small after recompute)", #wa.wilds))
            proj3 = proj3 + toFree3
            i = i + 1
          else
            proj3 = proj3 + #wa.wilds + #wa.naturalCards
            L(string.format("Wild alloc re-pruned after recompute (hand too small): %s", wa.rank))
            table.remove(wildAllocs, i)
          end
        end
      end
    end
  end

  -- Go-out recovery pass: if all wildAllocs were pruned by the "keep 2 cards" rule but
  -- the player is post-foot with 2+ projected red books and still needs black books,
  -- try an alternate wild allocation that suppresses wild book completion.  A 2-black-book
  -- + go-out path (600 + 500 pts) may be more valuable than a wild book (1500 pts)
  -- that cannot actually be completed because the hand constraint fires.
  if #wildAllocs == 0 and preWildPruneCount > 0
     and not goOut.should and not state.hasFoot
     and projRedFromMelds >= 2 and state.bookCounts.black < 2
     and state.wildCount > 0 then
    L("Go-out recovery: wild allocs pruned; retrying with suppressWildBook=true")
    local altAllocs = evalWildAllocations(state, melds, function() end, projRedFromMelds, true)
    local altProjBlack = state.bookCounts.black
    local altConsumed  = 0
    for _, m in ipairs(melds) do altConsumed = altConsumed + m.count end
    for _, wa in ipairs(altAllocs) do
      altConsumed = altConsumed + #wa.wilds + #wa.naturalCards
      if wa.completesBook and not wa.isWildMeld and wa.rank ~= "__wild__" then
        altProjBlack = altProjBlack + 1
      end
    end
    local altProjHand = state.handCount - altConsumed
    if altProjHand <= 1 and altProjBlack >= 2 then
      L(string.format("Go-out recovery: alt plan → black=%d hand=%d — GO OUT",
        altProjBlack, altProjHand))
      wildAllocs    = altAllocs
      projHandCount = altProjHand
      goOut = {should=true, reason=string.format(
        "recovery: suppressed wild book, achieved black=%d hand=%d", altProjBlack, altProjHand)}
      for _, wa in ipairs(wildAllocs) do
        local dr = (wa.isWildMeld or wa.rank == "__wild__") and "wild-meld" or wa.rank
        L(string.format("  [w%d] %s — %s (recovery alloc)", wa.priority, dr, wa.reason))
      end
    else
      L(string.format("Go-out recovery: alt plan gives black=%d hand=%d — cannot go out",
        altProjBlack, altProjHand))
    end
  end

  local discard
  if goOut.should and projHandCount == 0 then
    discard = {card=nil, reason="going out — no discard needed"}
  else
    discard = evalDiscard(state, melds, wildAllocs, L)
  end

  -- Wild-discard prevention: if the planned discard is a wild card AND there are
  -- non-book melds (priority >= 2) being played, try removing them (least important
  -- first) until a non-wild discard is available.  Keeping the naturals in hand
  -- lets evalDiscard choose them over a wild.
  -- Priority 2 (p2) plays are included: when their paired wild allocs were pruned due
  -- to hand size, a p2 play is effectively just a meld extension — not worth forcing
  -- a wild discard to keep it.  (If wilds were successfully allocated for p2, there
  -- would be no wild discard and this block would not trigger.)
  if not goOut.should and discard.card and discard.card.color == "Wild" then
    local pruneable = {}
    for i, m in ipairs(melds) do
      if m.priority >= 2 then table.insert(pruneable, {idx=i, m=m}) end
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
      -- Recompute wild allocs when the hand would be nearly empty OR when we're
      -- building black books (allowWilds is true for the needsBlackBooks path).
      local tryNeedsBlacks = not state.hasFoot and projRedFromMelds >= 2 and state.bookCounts.black < 2
      local tryWA = {}
      if tryProjHand <= 1 or tryNeedsBlacks then
        tryWA = evalWildAllocations(state, tryMelds, function() end, projRedFromMelds)
        for _, wa in ipairs(tryWA) do
          tryConsumed = tryConsumed + #wa.wilds + #wa.naturalCards
        end
        tryProjHand = state.handCount - tryConsumed
      end
      local tryDiscard = evalDiscard(state, tryMelds, tryWA, L)
      if tryDiscard.card and tryDiscard.card.color ~= "Wild" then
        L(string.format("Pruned %s meld (kept naturals to avoid discarding wild)", entry.m.rank))
        melds         = tryMelds
        wildAllocs    = tryWA
        discard       = tryDiscard
        projHandCount = tryProjHand
        -- Re-check go-out: pruning + recomputed wilds may complete 2 black books.
        if not goOut.should and not state.hasFoot and projHandCount <= 1 then
          local newProjBlack = state.bookCounts.black
          local counted = {}
          for _, wa in ipairs(wildAllocs) do
            if not wa.isWildMeld and wa.rank and #wa.wilds > 0 and not counted[wa.rank] then
              local mi = state.meldsByRank[wa.rank]
              local baseTotal = mi and (mi.count + (mi.embeddedWilds or 0)) or 0
              for _, m in ipairs(melds) do
                if m.rank == wa.rank then baseTotal = baseTotal + m.count end
              end
              local totalWilds = 0
              for _, wa2 in ipairs(wildAllocs) do
                if wa2.rank == wa.rank then totalWilds = totalWilds + #wa2.wilds end
              end
              if baseTotal + totalWilds >= 7 then
                counted[wa.rank] = true
                newProjBlack = newProjBlack + 1
              end
            end
          end
          if projRedFromMelds >= 2 and newProjBlack >= 2 then
            goOut = {should=true, reason=string.format(
              "empties hand after meld pruning (red=%d black=%d)", projRedFromMelds, newProjBlack)}
            L("Go out: YES (after meld pruning) — " .. goOut.reason)
          end
        end
        break
      end
    end
  end

  -- Final safety check: if all plays consumed all but 1 card and the remaining card
  -- is a WILD that would be discarded without going out, scrap the plays — discarding
  -- your last wild to empty the hand wastes it.  A natural card as the final discard
  -- is fine: the hand empties and you draw next turn (foot already picked up) or the
  -- foot was never on the table and you just end with a valid discard.
  if not goOut.should and not state.hasFoot
     and discard.card and discard.card.color == "Wild"
     and (projHandCount - 1 == 0) then
    L("Plays scrapped — discarding last card without going out; re-evaluating from full hand")
    melds         = {}
    wildAllocs    = {}
    projHandCount = state.handCount
    discard       = evalDiscard(state, {}, {}, L)
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
        existingCount=m.existingCount,
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
      local actualTotal = (d.existingCount or 0) + d.natCount + d.wildCount
      if d.completes and actualTotal >= 7 then
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

function executeTurnPlan(plan)
  if not plan.ok then return end
  local sColor = plan.color
  pcall(function()
    -- Do NOT clear here — clearing every execution would wipe a crash trace before it can be
    -- copied.  Append a separator instead; the buffer self-trims (capped).  Use traceClear()
    -- manually (or delete the tab) for a fresh start.
    trace("")
    trace("=== execute plan: " .. tostring(sColor) .. " melds=" .. #(plan.melds or {}) ..
          " wilds=" .. #(plan.wildAllocs or {}) .. " @t=" .. tostring(Time and Time.time or "?") .. " ===")
    dumpPlan(plan)
    dumpOrphans("pre-exec")
    cardCensus("pre-exec")
  end)

  -- Returns a random inter-play pause when Enhance is enabled, else 0.
  local function enhancePause()
    if not gEnhanceEnabled then return 0 end
    return ENHANCE_PAUSE_MIN + math.random() * (ENHANCE_PAUSE_MAX - ENHANCE_PAUSE_MIN)
  end

  -- Drop any object outside this meld's own column (lateral offset > ~1.5 from anchorPos) so a
  -- proximity/rank scan can't sweep cards — rank OR wild — out of an ADJACENT meld column into
  -- the book being formed.  Position-based, so it filters stray 9s and stray wilds alike; an
  -- in-column wild (legitimately part of this meld) sits at ~0 offset and is kept.
  local function filterToColumn(objs, anchorPos)
    if not anchorPos then return objs end
    local decode  = getPlayerDecodeDir(sColor)
    local latAxis = (decode and decode[1]) or "x"
    local out = {}
    for _, obj in ipairs(objs) do
      local keep = false
      pcall(function()
        local p = obj.getPosition()
        if p and math.abs(p[latAxis] - anchorPos[latAxis]) <= 1.5 then keep = true end
      end)
      if keep then table.insert(out, obj) end
    end
    return out
  end

  -- When a collection of meld objects totals 7+ cards, stack them so TTS merges
  -- them into a single Deck and checkAndMoveBooks can find and rotate it.
  -- For < 7 cards, fall through to spread4 as before.
  local function stackOrSpread(objs, stackPos)
    local totalQty = 0
    for _, obj in ipairs(objs) do
      local q = 1
      pcall(function() local qq = obj.getQuantity(); if qq and qq >= 1 then q = qq end end)
      totalQty = totalQty + q
    end
    if totalQty >= 7 then
      -- Co-locate the cards and let TTS physics fuse them into a Deck.  Physics is reliable
      -- at FORMING a deck from loose cards (building one via putObject from a single-card
      -- base is flaky and was leaving books unformed); its only weakness is occasionally
      -- leaving one card unmerged.  So after a short settle, reclaimColumnStragglers
      -- putObjects any leftover loose card INTO the formed Deck (reliable deck-base merge)
      -- before the book is moved.
      for _, obj in ipairs(objs) do
        pcall(function() obj.setPosition(stackPos) end)
      end
      -- Settle (2.0s) lets the co-located cards fuse into one Deck before we reclaim; the
      -- 2.0s pause after reclaim lets that merge finish before checkAndMoveBooks carries the
      -- book off — otherwise it can move as two pieces, shedding a card half-way.
      Wait.time(function()
        pcall(function() reclaimColumnStragglers(sColor, stackPos) end)
        Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 2.5)
      end, 2.0)
      Wait.time(function()
        pcall(function() reclaimColumnStragglers(sColor, stackPos) end)
        Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 2.5)
      end, 4.0)
    else
      local anchorPos
      pcall(function() anchorPos = objs[1].getPosition() end)
      spread4(sColor, anchorPos or stackPos, objs)
    end
  end

  -- Natural meld plays (staggered so computeNewLinePosition sees placed cards correctly).
  -- Pass skipOpeningCheck=true: evalMeldsToPlay already verified the combined total.
  local t = 0
  local tAnimEnd = 0  -- pure animation end time, excludes enhance pauses after last step
  for _, m in ipairs(plan.melds) do
    local capturedM = m
    if m.partial then
      -- Partial play: move only m.count specific card objects onto the existing meld.
      -- Used when the hand has more cards of a rank than needed to complete a book.
      Wait.time(function()
        pcall(function()
          local pos = getMeldAnchor(sColor, capturedM.rank)
          if not pos then return end
          local dt = 0
          for i = 1, capturedM.count do
            local entry = capturedM.cards[i]
            if not entry then break end
            local capturedCard = entry
            Wait.time(function()
              pcall(function()
                capturedCard.obj.setRotation({0, 180, 0})
                capturedCard.obj.setPosition(pos)
              end)
            end, dt)
            dt = dt + 0.15
          end
          local capturedPos   = pos
          Wait.time(function()
            pcall(function()
              local allObjs = getMeldColumnObjects(sColor, capturedM.rank)
              local safe = {}
              for _, obj in ipairs(allObjs) do
                -- Exclude completed books (qty≥7): already merged; checkAndMoveBooks handles them.
                -- Do NOT access capturedM.cards[i].obj here — TTS merges placed cards into a Deck
                -- immediately, invalidating individual Card references and causing
                -- "Object reference not set" C# errors that escape pcall.
                local qty = 1
                pcall(function() qty = obj.getQuantity() end)
                if qty < 7 and pcall(function() obj.getPosition() end) then
                  table.insert(safe, obj)
                end
              end
              safe = filterToColumn(safe, capturedPos)
              if #safe > 0 then
                local anchorPos
                pcall(function() anchorPos = safe[1].getPosition() end)
                stackOrSpread(safe, anchorPos or capturedPos)
              end
            end)
            -- Unconditional book check: if all 7 cards merged before the zone scan
            -- ran, safe is empty but checkAndMoveBooks finds the Deck(qty≥7) directly.
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 2.0)
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 4.5)
          end, dt + 1.0)
        end)
      end, t)
      tAnimEnd = t + capturedM.count * 0.15 + 1.75
      t = tAnimEnd + enhancePause()
    else
      local capturedRank = m.rank
      local capturedGoingOut = plan.goOut and plan.goOut.should or false
      Wait.time(function()
        layoutHandRank(sColor, capturedRank, true, true, capturedGoingOut, true)
      end, t)
      tAnimEnd = t + (m.count * 0.15) + 0.75
      t = tAnimEnd + enhancePause()
    end
  end

  -- Wild allocation plays (each fires after natural melds settle).
  for _, wa in ipairs(plan.wildAllocs or {}) do
    local capturedWa = wa
    if wa.naturalsAlreadyPlaced then
      -- Naturals were placed by layoutHandRank; find the meld dynamically
      -- and drop wilds onto it without re-touching the natural card objects.
      Wait.time(function()
        pcall(function()
          local capturedRank = capturedWa.rank
          local pos = getMeldAnchor(sColor, capturedRank)
          if not pos then return end
          local dt = 0
          for _, card in ipairs(capturedWa.wilds) do
            local capturedCard = card
            Wait.time(function()
              pcall(function()
                capturedCard.obj.setRotation({0, 180, 0})
                capturedCard.obj.setPosition(pos)
              end)
            end, dt)
            dt = dt + 0.15
          end
          local capturedPos = pos
          Wait.time(function()
            pcall(function()
              -- Zone scan: finds natural rank cards + nearby wilds.
              -- Do NOT loop over capturedWa.wilds references here — those card objects
              -- are invalidated the moment TTS merges them into the existing meld Deck,
              -- causing "Object reference not set" C# errors that escape pcall.
              local allObjs = getMeldColumnObjects(sColor, capturedRank)
              local safe = {}
              local seenGuids = {}
              for _, obj in ipairs(allObjs) do
                local qty = 1
                pcall(function() qty = obj.getQuantity() end)
                if qty < 7 and pcall(function() obj.getPosition() end) then
                  local guid; pcall(function() guid = obj.getGUID() end)
                  if guid and not seenGuids[guid] then
                    seenGuids[guid] = true
                    table.insert(safe, obj)
                  end
                end
              end
              -- Proximity supplement for recently placed wilds not yet zone-registered.
              local nearby = getCardsNearPos(sColor, capturedPos, 3.0)
              for _, obj in ipairs(nearby) do
                local qty = 1
                pcall(function() qty = obj.getQuantity() end)
                if qty < 7 then
                  local guid; local ok = pcall(function() guid = obj.getGUID() end)
                  if ok and guid and not seenGuids[guid] then
                    seenGuids[guid] = true
                    table.insert(safe, obj)
                  end
                end
              end
              safe = filterToColumn(safe, capturedPos)
              if #safe > 0 then stackOrSpread(safe, capturedPos) end
            end)
            -- Unconditional book checks: if cards merged before the scan ran,
            -- safe may be incomplete, but checkAndMoveBooks finds the Deck directly.
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 2.0)
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 4.5)
          end, dt + 1.0)
        end)
      end, t)
      tAnimEnd = t + #wa.wilds * 0.15 + 1.75
      t = tAnimEnd + enhancePause()

    elseif wa.isNew then
      -- New meld: place 2 naturals + 1 wild at a fresh meld slot.
      Wait.time(function()
        pcall(function()
          local colorZones = getPlayerZones(sColor)
          local rotY       = getPlayerRotY(sColor)
          local pos = computeNewLinePosition(sColor, colorZones, rotY, function() end)
          if not pos then return end
          local allCards = {}
          for _, c in ipairs(capturedWa.naturalCards) do table.insert(allCards, c) end
          for _, c in ipairs(capturedWa.wilds)        do table.insert(allCards, c) end
          local dt = 0
          for _, card in ipairs(allCards) do
            local capturedCard = card
            Wait.time(function()
              pcall(function()
                -- setRotation before setPosition releases the card from TTS hand zone
                -- management, preventing "Object reference not set" C# errors.
                capturedCard.obj.setRotation({0, 180, 0})
                capturedCard.obj.setPosition(pos)
              end)
            end, dt)
            dt = dt + 0.15
          end
          -- Use position-based scan so spread4 sees naturals AND wilds
          -- even if TTS hasn't physics-merged them into one Deck yet.
          -- Extra delay (1.0s) gives TTS time to merge before we scan.
          local capturedPos = pos
          Wait.time(function()
            pcall(function()
              local nearby = getCardsNearPos(sColor, capturedPos, 3.0)
              local safe = {}
              for _, obj in ipairs(nearby) do
                if pcall(function() obj.getPosition() end) then table.insert(safe, obj) end
              end
              safe = filterToColumn(safe, capturedPos)
              if #safe > 0 then stackOrSpread(safe, capturedPos) end
            end)
          end, dt + 1.0)
        end)
      end, t)
      tAnimEnd = t + (#wa.naturalCards + #wa.wilds) * 0.15 + 1.75
      t = tAnimEnd + enhancePause()

    else
      -- Wild-only play onto existing meld.
      Wait.time(function()
        pcall(function()
          -- Re-fetch the meld position LIVE by rank instead of using the captured meldObj.
          -- A prior play this turn may have completed this meld into a book and MOVED it,
          -- which invalidates meldObj; calling a method on it throws a C# "Object reference
          -- not set" that escapes pcall.  getMeldAnchor re-scans current melds/books (nil if gone).
          trace("wild-on-meld rank=" .. tostring(capturedWa.rank) .. ": fetching live anchor")
          local pos = getMeldAnchor(sColor, capturedWa.rank)
          if not pos then trace("  anchor nil (meld moved/gone) — skip wild") return end
          trace("  anchor=" .. dump(pos) .. " placing " .. #capturedWa.wilds .. " wild(s)")
          local dt = 0
          for _, card in ipairs(capturedWa.wilds) do
            local capturedCard = card
            Wait.time(function()
              pcall(function()
                capturedCard.obj.setRotation({0, 180, 0})
                capturedCard.obj.setPosition(pos)
              end)
            end, dt)
            dt = dt + 0.15
          end
          -- Position-based sweep anchored near the wild meld deposit position.
          -- getMeldColumnObjects(rank) would find wilds embedded in OTHER rank melds
          -- (e.g. a Joker inside the 9s meld), making spread4 anchor at the wrong
          -- meld and pull cards across the table.  getMeldColumnForSweep stops at
          -- book boundaries and stays within the same column.
          local capturedPos = pos
          Wait.time(function()
            pcall(function()
              -- Zone scan primary (no Physics.cast / no stale-reference risk).
              -- getMeldColumnObjects returns natural-rank cards + wilds embedded in
              -- the same meld column.  For all-wild melds (Joker/2 rank) the Deck
              -- has no natural rank so getMeldColumnObjects returns nothing — the
              -- proximity supplement below picks it up instead.
              local capturedRank = capturedWa.rank
              local allObjs = getMeldColumnObjects(sColor, capturedRank)
              local safe = {}
              local seenGuids = {}
              for _, obj in ipairs(allObjs) do
                local qty = 1
                pcall(function() qty = obj.getQuantity() end)
                if qty < 7 then
                  local guid; local ok = pcall(function() guid = obj.getGUID() end)
                  if ok and guid and not seenGuids[guid] then
                    seenGuids[guid] = true
                    table.insert(safe, obj)
                  end
                end
              end
              -- Proximity supplement: catches all-wild Decks (not returned by rank scan)
              -- and any cards placed so recently they haven't zone-registered yet.
              local nearby = getCardsNearPos(sColor, capturedPos, 3.0)
              for _, obj in ipairs(nearby) do
                local qty = 1
                pcall(function() qty = obj.getQuantity() end)
                if qty < 7 then
                  local guid; local ok = pcall(function() guid = obj.getGUID() end)
                  if ok and guid and not seenGuids[guid] then
                    seenGuids[guid] = true
                    table.insert(safe, obj)
                  end
                end
              end
              -- Column-aware guard.  Both scans above gather wilds by RANK (getTableCardsOfRank
              -- returns rank-2 wilds embedded in OTHER melds too) or by a flat 3.0 radius — either
              -- can reach into an ADJACENT meld column and pull a wild embedded there into this
              -- wild book.  That over-fills the book past 7 AND strips the neighbour meld of its
              -- black-book wild.  Keep only cards in the wild meld's OWN column: lateral-axis
              -- offset from the deposit point within half a column gap (inter-column spacing is
              -- ~3+ units; in-column wilds sit at ~0 offset, so 1.5 cleanly separates them).
              do
                local decode  = getPlayerDecodeDir(sColor)
                local latAxis = (decode and decode[1]) or "x"
                local LAT_BAND = 1.5
                local filtered = {}
                for _, obj in ipairs(safe) do
                  local keep = false
                  pcall(function()
                    local opos = obj.getPosition()
                    if opos and math.abs(opos[latAxis] - capturedPos[latAxis]) <= LAT_BAND then
                      keep = true
                    end
                  end)
                  if keep then table.insert(filtered, obj) end
                end
                safe = filtered
              end
              safe = filterToColumn(safe, capturedPos)
              if #safe > 0 then stackOrSpread(safe, capturedPos) end
            end)
            -- Unconditional book check: getTableCardsOfRank skips all-wild Decks (no
            -- natural rank), so if the 7 wilds merged before the scan, safe is empty
            -- but checkAndMoveBooks finds the Deck(qty≥7) in zone 1 directly.
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 2.0)
            Wait.time(function() pcall(function() checkAndMoveBooks(sColor) end) end, 4.5)
          end, dt + 1.0)
        end)
      end, t)
      tAnimEnd = t + #wa.wilds * 0.15 + 1.75
      t = tAnimEnd + enhancePause()
    end
  end

  -- Discard fires after all melds and wild plays have finished.
  -- Skipped only when going out with no discard.  When picksUpFoot is also true,
  -- the discard runs first and foot pickup fires after it settles (extra delay below).
  if plan.discard.card then
    Wait.time(function()
      pcall(function()
        UI.setAttribute("btnDiscard", "text", "Discard")
        UI.setAttribute("btnDiscard", "textColor", "#FFFFFF")
      end)
      pcall(function()
        local cardObj    = plan.discard.card.obj
        local discardPos = obj_Zone_Discard.getPosition()
        -- Instantly raise the card out of the hand zone so TTS stops managing
        -- its position, then smooth-move it down to the discard pile.
        cardObj.setPosition({discardPos.x, discardPos.y + 5, discardPos.z})
        cardObj.setRotation({0, 180, 0})
        Wait.time(function()
          pcall(function() cardObj.setPositionSmooth(discardPos) end)
        end, 0.1)
        -- Fire discard side-effects after the card has arrived and
        -- onObjectEnterScriptingZone has had time to add it to tableDiscard.
        Wait.time(function()
          pcall(function() onDiscardComplete(sColor, cardObj) end)
        end, 0.6)
      end)
    end, tAnimEnd + 0.5)
  end

  -- Post-play sweep: re-spread any meld piles that TTS physics-merged into a Deck
  -- during card placement.  Fires after all meld/wild plays and the discard have settled.
  Wait.time(function()
    pcall(function() sweepMeldsForPlayer(sColor) end)
  end, t + GT_SWEEP_SETTLE_DELAY)

  -- Foot pickup: hand emptied (with or without a discard) → auto-deal foot, sort, re-plan.
  -- When a discard preceded this, add extra time for the card to reach the discard pile
  -- and onDiscardComplete to fire before we look for the face-down foot pile.
  if plan.picksUpFoot then
    local footDelay = plan.discard.card and (t + 1.5) or (t + 0.5)
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
              if sColor == "White" then
                gPlanResult = buildTurnPlan(sColor)
                showPlanPanel(gPlanResult)
              end
            end, 0.75)
          end)
        else
          pcall(function() sortHand(nil, sColor) end)
        end
      end, 2.0)
    end, footDelay)
  end
end

function printTurnPlan(plan, sColor)
  for _, line in ipairs(plan.log) do
    printToColor(line, sColor)
  end
end
