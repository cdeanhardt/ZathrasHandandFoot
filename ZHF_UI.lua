--==============================================================================
-- ZHF_UI.lua
-- All click_* button handlers, panel visibility, table-surface button creation,
-- plan-panel rendering.  Bundled into Global.-1.lua via require("ZHF_UI").
--==============================================================================

function setPanelVisibility()
  -- set the UI panel to be visible to some players while not to others
  -- based on their current preference in playerStuff
  local sVisible="Yellow"  -- the visibility attribute seemed to need SOMETHING as being empty = everyone, so use "yellow" since its not a player
  for _, player in ipairs(Player.getPlayers()) do
    if (playerStuff[player.color].bScoreVisible) then
      sVisible = sVisible .. iif(sVisible=="","","|") .. player.color
      debug("visible = " .. sVisible,"panel")
    end
  end
  debug("visibility...","panel")
  debug(UI.getAttribute("ScoreSheetPanel","visibility"),"panel" )
  --UI.setAttribute("ScoreSheetPanel","visibility",sVisible)
  UI.setAttribute("SubPanel","visibility",sVisible)
  UI.setAttribute("ScoreTable","visibility",sVisible)
end

function ClosePanel(oPlayer)
    -- called when a player chooses to close the panel.
    -- oPlayer - the player instance who is closing their panel
    playerStuff[oPlayer.color].bScoreVisible = not playerStuff[oPlayer.color].bScoreVisible
    setPanelVisibility()
end

function setSortOrder(bLeft, bAceHigh)
  -- We're about to sort some cards, so based on preferences, set up the
  -- refcardorderindex for use in the sort
  -- bLeft    - Low to high is Left to Right (otherwise Right to Left)
  -- bAceHigh - Ace his higher than the king (otherwise lower than two)
  if bAceHigh then
    if (bLeft) then
      for k,v in pairs(refCardOrderLAceH) do
        refCardOrderIndex[v]=k
      end
    else
      for k,v in pairs(refCardOrderRAceH) do
        refCardOrderIndex[v]=k
      end
    end
  else
    if (bLeft) then
      for k,v in pairs(refCardOrderLAceL) do
        refCardOrderIndex[v]=k
      end
    else
      for k,v in pairs(refCardOrderRAceL) do
        refCardOrderIndex[v]=k
      end
    end
  end
end

function click_DoNothing(_, color)
-- a null function as one is required for buttons but not always needed
end

function setActionPanelVisibility()
  -- Action panel is only for White.
  -- Use active=true/false (not just visibility) because TTS doesn't reliably
  -- re-evaluate visibility= when a player changes seats.
  -- Use Player["White"].seated (canonical TTS property) rather than iterating
  -- Player.getPlayers(), which can lag behind the actual seat state.
  --
  -- IMPORTANT: Suppress toggle callbacks while changing active state.
  -- TTS fires onValueChanged on child Toggles when a panel is activated or
  -- deactivated. In hotseat mode the current seated player at that moment is
  -- whoever just swapped in, which was silently setting their bAutodraw = true.
  Wait.time(function()
    local ok, whiteSeated = pcall(function() return Player["White"].seated end)
    gSuppressToggleCallbacks = true
    if ok and whiteSeated then
      UI.setAttribute("ActionPanel", "visibility", "White")
      UI.setAttribute("ActionPanel", "active", "true")
    else
      UI.setAttribute("ActionPanel", "active", "false")
    end
    Wait.time(function() gSuppressToggleCallbacks = false end, 0.5)
  end, 0.3)
end

function triggerAutodraw(sColor)
  if sColor ~= "White" then return end
  if not mainDeck then return end

  -- Random 1–3 second pause before drawing (feels more natural).
  local drawDelay = 1.0 + math.random() * 2.0

  -- Snapshot hand count AND GUIDs before dealing.
  local preCount = 0
  local preDraw = {}
  pcall(function()
    local objs = Player[sColor].getHandObjects()
    preCount = #objs
    for _, obj in ipairs(objs) do preDraw[obj.guid] = true end
  end)

  Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, drawDelay)
  Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, drawDelay + 0.5)

  -- Report drawn cards (cosmetic — fixed timer is fine here).
  Wait.time(function()
    pcall(function()
      local drawn = {}
      for _, obj in ipairs(Player[sColor].getHandObjects()) do
        if not preDraw[obj.guid] then
          local ok, cl, rk, su = pcall(function()
            local c, r, s = cardDeets(obj)
            return c, r, s
          end)
          if ok then table.insert(drawn, rk .. " of " .. (su or "?")) end
        end
      end
      if #drawn > 0 then
        printToColor("Drew: " .. table.concat(drawn, ", "), sColor)
      end
    end)
  end, drawDelay + 1.5)

  -- After second deal fires, poll until both cards register (or 4 s timeout),
  -- then sort → handle red 3s → sort again → plan.
  Wait.time(function()
    waitForHandGrowth(sColor, preCount + 2, 4.0, function()
      pcall(function() sortHand(nil, sColor) end)
      Wait.time(function()
        handleRedThrees(sColor, function()
          pcall(function() sortHand(nil, sColor) end)
          Wait.time(function()
            gPlanResult = buildTurnPlan(sColor)
            showPlanPanel(gPlanResult)
          end, 0.75)
        end)
      end, 0.5)
    end)
  end, drawDelay + 0.6)
end

function click_ToggleAutodraw(player, value)
  if gSuppressToggleCallbacks then return end
  local ps = playerStuff["White"]
  if ps then
    ps.bAutodraw = (value == "True")
    printToColor("Autodraw " .. (value == "True" and "ON" or "OFF"), "White")
  end
end

function click_ToggleActionPanel(player)
  local current = UI.getAttribute("ActionSubPanel", "active")
  UI.setAttribute("ActionSubPanel", "active", current == "true" and "false" or "true")
end

function click_ActionPlayHand(player)
  autoPlayMatchingCards(player.color)
end

function click_ActionPlayAndLay(player)
  local sColor = player.color
  handleRedThrees(sColor, function()
    -- Compute how long layoutHandAll will take (using current hand state).
    local eligible = getEligibleRanks(sColor)
    local layoutTime = 0
    for _, rank in ipairs(eligible) do
      local plan = planLayoutRank(sColor, rank)
      local nCards = (plan.ok and plan.cards) and #plan.cards or 7
      layoutTime = layoutTime + (nCards * 0.15) + 0.75
    end
    layoutHandAll(sColor, true)
    -- After layout finishes (plus a small buffer), play matching hand cards.
    Wait.time(function()
      autoPlayMatchingCards(sColor, true)
    end, layoutTime + 1.0)
  end)
end

function click_ActionLayoutAllHand(player)
  layoutHandAll(player.color)
end

function click_ActionDrawSortPlayLay(player)
  local sColor = player.color

  local preCount = 0
  pcall(function() preCount = #Player[sColor].getHandObjects() end)

  -- Draw 2 cards from the main deck.
  if mainDeck then
    pcall(function() mainDeck.deal(1, sColor) end)
    Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, 0.5)
  end

  -- Poll until both cards register (or 4 s timeout),
  -- then sort → handle red 3s → sort again → play hand.
  Wait.time(function()
    waitForHandGrowth(sColor, preCount + 2, 4.0, function()
      pcall(function() sortHand(nil, sColor) end)
      Wait.time(function()
        handleRedThrees(sColor, function()
          pcall(function() sortHand(nil, sColor) end)
          -- Brief pause for sort to visually complete, then play hand.
          Wait.time(function()
            local playPlan = planAutoPlay(sColor)
            local playDuration = 0
            if playPlan.ok then
              executeAutoPlay(sColor, playPlan)
              for _, move in ipairs(playPlan.moves) do
                playDuration = playDuration + (#move.cards * 0.75) + 0.75
              end
            end

            -- Layout all eligible ranks after play finishes.
            Wait.time(function()
              layoutHandAll(sColor, true)
            end, playDuration + 0.5)

          end, 0.5)
        end)
      end, 0.5)
    end)
  end, 0.6)
end

function updateDiscardButton(sColor)
  local label = "Discard"
  pcall(function()
    local plan = buildTurnPlan(sColor)
    if plan and plan.discard and plan.discard.card then
      local c = plan.discard.card
      local r = _RANK_SHORT[c.rank] or c.rank
      local s = _SUIT_SHORT[c.suit] or ""
      label = "Discard " .. r .. s
    end
  end)
  pcall(function()
    UI.setAttribute("btnDiscard", "text", label)
    UI.setAttribute("btnDiscard", "textColor", "#FFFFFF")
  end)
end

function click_ActionDraw(player)
  local sColor = player.color
  if not mainDeck then return end

  -- Snapshot count and GUIDs already in hand before dealing.
  local preCount = 0
  local preDraw = {}
  pcall(function()
    local objs = Player[sColor].getHandObjects()
    preCount = #objs
    for _, obj in ipairs(objs) do preDraw[obj.guid] = true end
  end)

  pcall(function() mainDeck.deal(1, sColor) end)
  Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, 0.5)

  -- Report drawn cards (cosmetic — fixed timer is fine here).
  Wait.time(function()
    pcall(function()
      local drawn = {}
      for _, obj in ipairs(Player[sColor].getHandObjects()) do
        if not preDraw[obj.guid] then
          local ok, cl, rk, su = pcall(function()
            local c, r, s = cardDeets(obj)
            return c, r, s
          end)
          if ok then
            table.insert(drawn, rk .. " of " .. (su or "?"))
          end
        end
      end
      if #drawn > 0 then
        printToColor("Drew: " .. table.concat(drawn, ", "), sColor)
      end
    end)
  end, 1.5)

  -- Poll until both cards register (or 4 s timeout),
  -- then sort → handle red 3s → sort again → update discard button.
  Wait.time(function()
    waitForHandGrowth(sColor, preCount + 2, 4.0, function()
      pcall(function() sortHand(nil, sColor) end)
      Wait.time(function()
        handleRedThrees(sColor, function()
          Wait.time(function()
            pcall(function() sortHand(nil, sColor) end)
            -- After sort settles, compute and display the suggested discard.
            Wait.time(function() updateDiscardButton(sColor) end, 1.0)
          end, 0.5)
        end)
      end, 0.5)
    end)
  end, 0.6)
end

function click_ActionDiscard(player)
  local sColor = player.color
  local ok, state = pcall(function() return snapshotState(sColor) end)
  if not ok or not state then
    broadcastToColor("Could not read hand state", sColor)
    return
  end
  local result = evalDiscard(state, {}, nil)
  if not result.card then
    broadcastToColor("Nothing to discard: " .. (result.reason or "?"), sColor)
    return
  end
  local cardObj = result.card.obj
  broadcastToColor("Discarding: " .. result.card.rank .. " of " .. (result.card.suit or "?")
    .. " — " .. result.reason, sColor)
  pcall(function()
    UI.setAttribute("btnDiscard", "text", "Discard")
    UI.setAttribute("btnDiscard", "textColor", "#FFFFFF")
  end)
  pcall(function()
    local discardPos = obj_Zone_Discard.getPosition()
    -- Lift the card above the hand zone so TTS releases it from hand management,
    -- then smooth-move it to the discard pile.
    cardObj.setPosition({discardPos.x, discardPos.y + 5, discardPos.z})
    cardObj.setRotation({0, 180, 0})
    Wait.time(function()
      pcall(function() cardObj.setPositionSmooth(discardPos) end)
    end, 0.1)
    Wait.time(function()
      pcall(function() onDiscardComplete(sColor, cardObj) end)
    end, 0.7)
  end)
end

-- Stored  plan from the last click_ActionPlan call; held so click_PlanExecute can use it.
gPlanResult = nil

-- Rolling history of the last 5 plan display strings (index 1 = most recent).
gPlanHistory    = {}
gPlanHistoryIdx = 1   -- which history slot is currently shown in the panel

-- Wait ID for the auto-exec countdown; non-nil while a countdown is running.
gAutoExecWaitId  = nil
-- Tracks the Auto Exec toggle state; set by click_ToggleAutoExec.
gAutoExecEnabled = false
-- Tracks the Enhance toggle state; set by click_ToggleEnhance.
gEnhanceEnabled = true
-- Tracks whether the expandable ActionPanel buttons are visible.
gActionPanelExpanded = false
-- True during startup/load to suppress XML UI toggle callbacks (which fire with
-- the XML-default isOn="false" and would overwrite preferences restored from save).
gSuppressToggleCallbacks = true

local AUTOEXEC_BAR_WIDTH = 404  -- must match progressBarBg width in XML
local AUTOEXEC_TICK      = 0.05 -- seconds per tick (20 ticks/sec)

-- Inter-play pause injected between distinct meld/wild plays when Enhance is enabled.
ENHANCE_PAUSE_MIN = 0.5  -- seconds (minimum random pause)
ENHANCE_PAUSE_MAX = 2.0  -- seconds (maximum random pause)

-- Cancel any running auto-exec countdown without closing the panel.
local function cancelAutoExecTimer()
  if gAutoExecWaitId then
    Wait.stop(gAutoExecWaitId)
    gAutoExecWaitId = nil
  end
  UI.setAttribute("progressBarFill", "width", "0")
end

-- Start a random countdown that auto-executes the plan on expiry.
-- minSec/maxSec default to 5/8; pass 3/6 when no melds are on the table yet.
local function startAutoExecTimer(minSec, maxSec)
  cancelAutoExecTimer()
  local lo = minSec or 5
  local hi = maxSec or 8
  local duration   = lo + math.random() * (hi - lo)
  local totalTicks = math.ceil(duration / AUTOEXEC_TICK)
  local remaining  = totalTicks
  UI.setAttribute("progressBarFill", "width", tostring(AUTOEXEC_BAR_WIDTH))

  local function tick()
    remaining = remaining - 1
    local w = math.max(0, math.floor(AUTOEXEC_BAR_WIDTH * remaining / totalTicks))
    UI.setAttribute("progressBarFill", "width", tostring(w))
    if remaining <= 0 then
      gAutoExecWaitId = nil
      click_PlanExecute(nil)
    else
      gAutoExecWaitId = Wait.time(tick, AUTOEXEC_TICK)
    end
  end

  gAutoExecWaitId = Wait.time(tick, AUTOEXEC_TICK)
end

function buildStateContext(plan)
  if not plan or not plan.state then return "" end
  local s = plan.state
  local out = {}
  local function L(line) table.insert(out, line) end

  L("")
  L("=== STATE ===")

  -- Basic player info
  L(string.format("player=%s hand=%d wilds=%d foot=%s hand#=%s",
    s.color, s.handCount, s.wildCount,
    s.hasFoot and "on-table" or "picked-up",
    tostring(giHand or "?")))

  -- Per-player foot status
  pcall(function()
    if playerList and #playerList > 0 then
      local parts = {}
      for _, color in ipairs(playerList) do
        table.insert(parts, color .. "=" .. (playerHasFoot(color) and "on-table" or "picked-up"))
      end
      L("footStatus: " .. table.concat(parts, " "))
    end
  end)

  -- Books (each type with rank and card count)
  local bookLines = {}
  for _, btype in ipairs({"red","black","wild"}) do
    local blist = s.books[btype]
    if #blist > 0 then
      local entries = {}
      for _, b in ipairs(blist) do
        local qty = 0
        pcall(function() qty = b.obj.getQuantity() end)
        local rk = (_SC_RANK[b.rank] or b.rank or "?")
        table.insert(entries, rk .. "×" .. qty)
      end
      table.insert(bookLines, btype .. "=" .. #blist .. "[" .. table.concat(entries, ",") .. "]")
    else
      table.insert(bookLines, btype .. "=0")
    end
  end
  L("books: " .. table.concat(bookLines, " "))

  -- Open melds on table (non-book, non-red-3) — grouped by rank so spread cards sum correctly.
  local meldByRank = {}
  local meldRankOrder = {}
  for _, meld in ipairs(s.melds) do
    if not meld.isBook and meld.rank ~= "3" then
      local rank = meld.rank
      if not meldByRank[rank] then
        meldByRank[rank] = {qty=0, wildCt=0, embeddedWildCt=0, positions={}}
        table.insert(meldRankOrder, rank)
      end
      pcall(function()
        if meld.obj.tag == "Card" then
          meldByRank[rank].qty = meldByRank[rank].qty + 1
          local cl = cardDeets(meld.obj)
          if cl == "Wild" then meldByRank[rank].wildCt = meldByRank[rank].wildCt + 1 end
          local p = meld.obj.getPosition()
          table.insert(meldByRank[rank].positions, string.format("(%.1f,%.1f)", p.x, p.z))
        elseif meld.obj.tag == "Deck" then
          meldByRank[rank].qty = meldByRank[rank].qty + meld.obj.getQuantity()
          for _, c in ipairs(meld.obj.getObjects()) do
            local nm = c.description and string.match(c.description, "^([%a%d]+)") or ""
            if nm == "2" or nm == "Joker" then meldByRank[rank].wildCt = meldByRank[rank].wildCt + 1 end
          end
          local p = meld.obj.getPosition()
          table.insert(meldByRank[rank].positions, string.format("deck(%.1f,%.1f)", p.x, p.z))
        end
        -- Embedded wilds: separate wild Card objects absorbed into this column by getMelds.
        -- These are not in s.melds themselves but are tracked on the first entry of their rank.
        if meld.embeddedWilds and meld.embeddedWilds > 0 then
          meldByRank[rank].embeddedWildCt = meldByRank[rank].embeddedWildCt + meld.embeddedWilds
        end
      end)
    end
  end
  local meldParts = {}
  for _, rank in ipairs(meldRankOrder) do
    local info = meldByRank[rank]
    local totalQty  = info.qty + info.embeddedWildCt
    local totalWild = info.wildCt + info.embeddedWildCt
    -- Skip lone stray cards (not a real meld — minimum valid meld is 3 cards).
    if totalQty >= 2 then
      local rk = _SC_RANK[rank] or rank
      local posStr = #info.positions > 0 and (" @" .. table.concat(info.positions, ",")) or ""
      table.insert(meldParts, rk .. "×" .. totalQty .. (totalWild > 0 and ("(" .. totalWild .. "w)") or "") .. posStr)
    end
  end
  if #meldParts > 0 then
    L("melds:\n  " .. table.concat(meldParts, "\n  "))
  else
    L("melds: (none)")
  end

  -- Hand cards (sorted: naturals by rank value, then wilds)
  local rankOrd = {["Ace"]=14,["King"]=13,["Queen"]=12,["Jack"]=11,["10"]=10,
                   ["9"]=9,["8"]=8,["7"]=7,["6"]=6,["5"]=5,["4"]=4,["3"]=3,
                   ["2"]=2,["Joker"]=1}
  local sorted = {}
  for _, card in ipairs(s.hand) do table.insert(sorted, card) end
  table.sort(sorted, function(a, b)
    local ao = rankOrd[a.rank] or 0
    local bo = rankOrd[b.rank] or 0
    if ao ~= bo then return ao > bo end
    return (a.suit or "") < (b.suit or "")
  end)
  local cardStrs = {}
  for _, card in ipairs(sorted) do
    local rk = _SC_RANK[card.rank] or card.rank or "?"
    local su = _SC_SUIT[card.suit] or "?"
    if card.rank == "Joker" then
      table.insert(cardStrs, "Jo")
    else
      table.insert(cardStrs, rk .. su)
    end
  end
  L("hand: " .. table.concat(cardStrs, " "))

  return table.concat(out, "\n")
end

function planDisplayText(plan)
  local log = (plan and plan.log) or {}
  -- Find "Plays" line in the log.
  local playsIdx = nil
  for i, line in ipairs(log) do
    if line == "Plays" then playsIdx = i; break end
  end

  local text
  if playsIdx then
    -- plays section: "Plays" through end of log (last line is the separator)
    local plays = {}
    for i = playsIdx, #log do table.insert(plays, log[i]) end
    -- analysis section: everything before the blank line that precedes "Plays"
    local analysis = {}
    for i = 1, playsIdx - 2 do table.insert(analysis, log[i]) end
    text = table.concat(plays, "\n")
    if #analysis > 0 then
      text = text .. "\n" .. table.concat(analysis, "\n")
    end
  else
    text = table.concat(log, "\n")
  end

  if text == "" then text = "(no plan output)" end
  pcall(function()
    local stateText = buildStateContext(plan)
    if stateText and stateText ~= "" then
      text = text .. "\n" .. SEP .. stateText
    end
  end)
  return text
end

-- Refresh the 5 history nav buttons to reflect the current history size and selection.
local function updatePlanNavButtons()
  for i = 1, 5 do
    local id = "btnPlanH" .. i
    if i <= #gPlanHistory then
      UI.setAttribute(id, "active", "true")
      if i == gPlanHistoryIdx then
        -- Currently selected: highlighted
        UI.setAttribute(id, "color",     "rgba(0.25,0.25,0.45,0.75)")
        UI.setAttribute(id, "textColor", "#FFFFFF")
      else
        -- Available history: dim
        UI.setAttribute(id, "color",     "rgba(0,0,0,0)")
        UI.setAttribute(id, "textColor", "#666666")
      end
    else
      UI.setAttribute(id, "active", "false")
    end
  end
end

function click_PlanNav(player, value, id)
  local idx = id and tonumber(id:match("btnPlanH(%d+)"))
  if not idx or idx < 1 or idx > #gPlanHistory then return end
  gPlanHistoryIdx = idx
  UI.setAttribute("PlanResultText", "text", gPlanHistory[idx])
  updatePlanNavButtons()
end

-- Populate and show the PlanResultPanel with a composed plan result.
-- Starts the auto-exec countdown if the Auto Exec toggle is on.
-- Hide the plan panel safely even when the mouse is held on it.
-- Setting raycastTarget=false removes the panel from Unity's hit-testing chain,
-- forcing the EventSystem to release any IDragHandler pointer capture on the next
-- frame — even if the mouse button is still held.  After one frame (0.05 s) we
-- call SetActive(false); the capture is already gone so no state is corrupted.
-- raycastTarget is restored to true immediately after so the next SetActive(true)
-- finds the element fully ready for interaction.
-- Default screen position for the plan panel (matches XML offsetXY).
local PLAN_PANEL_DEFAULT_OFFSET = "280 -160"

local function hidePlanPanel(onDone)
  cancelAutoExecTimer()
  -- Snap the panel back to its default position BEFORE deactivating.
  -- TTS's drag component stores isDragging=true and a drag-offset vector as
  -- instance variables that survive active=false/true cycles (OnDisable does NOT
  -- reset them).  When the panel reactivates it wakes up still "dragging" and
  -- routes all pointer events to itself — buttons are visible but unclickable.
  -- Explicitly setting offsetXY forces TTS to recalculate the drag component's
  -- internal state from the new anchor, effectively ending the drag gesture.
  -- allowDragging=false and raycastTarget=false are belt-and-suspenders on top.
  UI.setAttribute("PlanResultPanel", "offsetXY", PLAN_PANEL_DEFAULT_OFFSET)
  UI.setAttribute("PlanResultPanel", "allowDragging", "false")
  UI.setAttribute("PlanResultPanel", "raycastTarget", "false")
  Wait.time(function()
    UI.setAttribute("PlanResultPanel", "active", "false")
    UI.setAttribute("progressBarFill", "width", "0")
    if onDone then onDone() end
  end, 0.15)
end

local function showPlanPanelActive()
  -- Always show at the default position so a mid-drag deactivation can never
  -- leave the panel at an unexpected offset when it reappears.
  UI.setAttribute("PlanResultPanel", "offsetXY", PLAN_PANEL_DEFAULT_OFFSET)
  UI.setAttribute("PlanResultPanel", "allowDragging", "false")
  UI.setAttribute("PlanResultPanel", "raycastTarget", "true")
  UI.setAttribute("PlanResultPanel", "active", "true")
  -- Re-enable dragging after the panel has fully settled so TTS builds a fresh
  -- drag component with no stale state from the previous gesture.
  Wait.time(function()
    UI.setAttribute("PlanResultPanel", "allowDragging", "true")
  end, 0.3)
end

function showPlanPanel(plan)
  -- Hard gate: the plan panel and auto-exec are White-only features.
  if not plan or plan.color ~= "White" then return end
  local displayText = planDisplayText(plan)
  table.insert(gPlanHistory, 1, displayText)
  if #gPlanHistory > 5 then gPlanHistory[6] = nil end
  gPlanHistoryIdx = 1
  local capturedPlan = plan
  hidePlanPanel(function()
    UI.setAttribute("PlanResultText", "text", displayText)
    -- One extra frame between active=false and active=true so Unity fully
    -- processes the deactivation before we re-enable the panel.
    Wait.time(function()
      showPlanPanelActive()
      updatePlanNavButtons()
      if gAutoExecEnabled then
        local state       = capturedPlan and capturedPlan.state
        local noMelds     = not state or #state.melds == 0
        local hasFoot     = state and state.hasFoot
        local discardOnly = capturedPlan and #(capturedPlan.melds or {}) == 0
                                         and #(capturedPlan.wildAllocs or {}) == 0
        local smallHand   = state and not hasFoot and (state.handCount or 99) <= 5
        if discardOnly or smallHand then
          startAutoExecTimer(0.5, 2)
        elseif noMelds or hasFoot then
          startAutoExecTimer(2, 4)
        else
          startAutoExecTimer(2, 5)
        end
      end
    end, 0.05)
  end)
end

function click_FixPlanPanel(player)
  local savedResult = gPlanResult
  local displayText = gPlanHistory[gPlanHistoryIdx] or ""
  hidePlanPanel(function()
    UI.setAttribute("PlanResultText", "text", displayText)
    if savedResult then
      Wait.time(function()
        gPlanResult = savedResult
        showPlanPanelActive()
        updatePlanNavButtons()
      end, 0.05)
    end
  end)
end

function click_ActionPlan(player)
  local sColor = player.color
  if UI.getAttribute("PlanResultPanel", "active") == "true" then
    local capturedPlan = gPlanResult
    gPlanResult = nil
    hidePlanPanel(function()
      if capturedPlan then executeTurnPlan(capturedPlan) end
    end)
    return
  end
  gPlanResult = buildTurnPlan(sColor)
  showPlanPanel(gPlanResult)
end

function click_ToggleAutoExec(player, value)
  gAutoExecEnabled = (value == "True")
end

function click_ToggleEnhance(player, value)
  gEnhanceEnabled = (value == "True")
end

function click_ToggleActionExpanded(player)
  gActionPanelExpanded = not gActionPanelExpanded
  local active = gActionPanelExpanded and "true" or "false"
  local ids = {"btnPlayHand","btnLayoutAllHand","btnPlayAndLay","btnDrawSortPlayLay","btnDiscard"}
  for _, id in ipairs(ids) do
    UI.setAttribute(id, "active", active)
  end
  UI.setAttribute("btnToggleActionExpanded", "text", gActionPanelExpanded and "▲ Less" or "▼ More")
  UI.setAttribute("ActionSubPanel", "height", gActionPanelExpanded and "415" or "230")
end

function click_PlanStop(player)
  cancelAutoExecTimer()
end

function click_PlanClose(player)
  gPlanResult = nil
  hidePlanPanel()
end

function click_PlanCopy(player)
  pcall(function()
    local text = UI.getAttribute("PlanResultText", "text")
    if text and text ~= "" then
      printToColor(text, player.color, {r=0.7, g=0.85, b=1})
    end
  end)
end

function click_PlanExecute(player)
  local capturedPlan = gPlanResult
  gPlanResult = nil
  hidePlanPanel(function()
    if capturedPlan then executeTurnPlan(capturedPlan) end
  end)
end

function click_ToggleScoring(_, color)
  -- Toggle scoring on/off and explicitly kick one off if it's on
  -- clear the display variables if it isn't
  bRunScoring = not bRunScoring
  setButtons()
  if (bRunScoring) then
    countScore()
  else
    text_score_white.TextTool.setValue(" ")
    text_score_blue.TextTool.setValue(" ")
    text_score_green.TextTool.setValue(" ")
    text_score_red.TextTool.setValue(" ")
  end
end

function click_ToggleRules(_, color)
  -- on button press, change which rule set we're using
  giRuleSet = (giRuleSet+1) % giNumRuleSets
  if (giRuleSet == giCaliforniaRules) then
    announceAll("California Rules In Effect")
  else
    announceAll("North Carolina Rules In Effect")
  end
  setButtons()
  Wait.time(function() setButtons() end, 1.0)
end

function click_NewGame(_, color)
  -- on button press, start a countdown to press this button again
  -- to deal a new game (technically, it's a different button but seems to be
  -- the same one to the user)
  giNewgameCountdown=6
  setButtons()
  Wait.time(function() setButtons() end, 1.0)
end

function click_NewGameSure(_, color)
  -- user clicked the newgame button while it was still within the countdown
  -- (otherwise, it would have been changed back to the orig button)
  -- so let's deal!
  if gbHandOver then
    printToAll("Scores are still being calculated — please wait a moment before dealing.", "Yellow")
    return
  end
  local playerList = getSortedSeatedPlayers()
  if (#playerList==1) then
    broadcastToAll("Playing alone? How sad for you.","Yellow")
    broadcastToAll("Also.. it doesn't work.","Yellow")
    broadcastToAll("Maybe try my cousin Solitaire?","Yellow")
    return
  end
  if (#playerList<2 or #playerList>4) then
    broadcastToAll("Only 2-4 players are supported.","Yellow")
    return
  end

  -- Safety check: if White's hand already has 13 cards, cards have probably
  -- already been dealt this hand.  Refuse and warn loudly rather than dealing twice.
  local whiteHandCount = 0
  pcall(function() whiteHandCount = #Player["White"].getHandObjects() end)
  if whiteHandCount == 13 then
    broadcastToAll("!!! WHITE HAS 13 CARDS IN HAND — ALREADY DEALT? !!!", "Red")
    broadcastToAll("Deal cancelled.  Clear the table before starting a new hand.", "Red")
    broadcastToAll("!!! WHITE HAS 13 CARDS IN HAND — ALREADY DEALT? !!!", "Red")
    giNewgameCountdown = 0
    setButtons()
    return
  end

  gbDealing=true
  mainDeck = initializeHand()
  Wait.time(function() initializeVariables() dealDeck(mainDeck) end, 1.0)
  debug("md1: " .. mainDeck.guid)
end

function setButtons()
  -- wipe and recreate the buttons on the surface of the table
  -- which buttons get created and what they do is sometimes
  -- driven by app state and preferences
debug("set buttons","buttons")
goSurface = getObjectFromGUID(UI_TABLETOP_SURFACE)

  goSurface.clearButtons()

  if (bRunScoring) then
    goSurface.createButton({
        click_function="click_ToggleScoring",label="Toggle Scoring" ,function_owner=self,
        position={-15.5,11,17.5}, rotation={0,180,0}, height=175, width=1000,
        color={1,1,0}, tooltip="Toggle Scoring"
    })
  else
    goSurface.createButton({
        click_function="click_ToggleScoring",label="Toggle Scoring" ,function_owner=self,
        position={-15.5,11,17.5}, rotation={0,180,0}, height=175, width=1000,
        color={1,1,1}, tooltip="Toggle Scoring"
    })
  end

  if (giRuleSet == giCaliforniaRules) then
    debug("cali","buttons")
    goSurface.createButton({
        click_function="click_ToggleRules",label="California Rules" ,function_owner=self,
        position={-15.5,11,17}, rotation={0,180,0}, height=175, width=1000,
        color={1,1,0}, tooltip="Switch Rules"
    })
  elseif (giRuleSet==giNorthCarolinaRules) then
    debug("cali","buttons")
    goSurface.createButton({
        click_function="click_ToggleRules",label="North Carolina Rules" ,function_owner=self,
        position={-15.5,11,17}, rotation={0,180,0}, height=175, width=1000,
        color={0,.5,0}, tooltip="Switch Rules"
    })
  end

  if (giNewgameCountdown>6) then
    giNewgameCountdown = giNewgameCountdown - 1
    goSurface.createButton({
        click_function="doNothing",label="Hold... ("..giNewgameCountdown..")" ,function_owner=self,
        position={-15.5,11,16.5}, rotation={0,180,0}, height=175, width=600,
        color={0,1,0}, tooltip=""
    })
    Wait.time(function() setButtons() end, 2.0)
  elseif (giNewgameCountdown<2) then
    giNewgameCountdown=0
    goSurface.createButton({
        click_function="click_NewGame",label="New Game" ,function_owner=self,
        position={-15.5,11,16.5}, rotation={0,180,0}, height=175, width=600,
        color={1,1,1}, tooltip="Start a new game"
    })
  else
    giNewgameCountdown = giNewgameCountdown - 1
    goSurface.createButton({
        click_function="click_NewGameSure",label="Confirm? ("..giNewgameCountdown..")" ,function_owner=self,
        position={-15.5,11,16.5}, rotation={0,180,0}, height=175, width=600,
        color={1,0,0}, tooltip="Be very sure"
    })
    Wait.time(function() setButtons() end, 2.0)
  end

  if gbShowDirButtons then
    pos = {x=-5, y=11, z=-5}
    goSurface.createButton({
        click_function="click_DoNothing",label="x ".. pos.x .. "     z " .. pos.z,function_owner=self,
        position=pos, rotation={0,180,0}, height=475, width=2000, font_size=400,
        color={1,1,0}, tooltip=""
    })
    pos = {x=-5, y=11, z=5}
    goSurface.createButton({
        click_function="click_DoNothing",label="x ".. pos.x .. "     z " .. pos.z,function_owner=self,
        position=pos, rotation={0,180,0}, height=475, width=2000, font_size=400,
        color={1,1,0}, tooltip=""
    })
    pos = {x=5, y=11, z=-5}
    goSurface.createButton({
        click_function="click_DoNothing",label="x ".. pos.x .. "     z " .. pos.z,function_owner=self,
        position=pos, rotation={0,180,0}, height=475, width=2000, font_size=400,
        color={1,1,0}, tooltip=""
    })
    pos = {x=5, y=11, z=5}
    goSurface.createButton({
        click_function="click_DoNothing",label="x ".. pos.x .. "     z " .. pos.z,function_owner=self,
        position=pos, rotation={0,180,0}, height=475, width=2000, font_size=400,
        color={1,1,0}, tooltip=""
    })
  end

end

