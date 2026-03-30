-- Constants------------------------------------------------------------------------
-- there's no law against these changing during a run but they're not supposed to
gi_NUM_COLUMNS=5            -- number of columns in the UI
gi_NUM_ROWS=4               -- number of rows in the UI
gb_USE_TURNS=true           -- admin boolean for whether to used the turn based system or not
gv_CARD_SIZE = {["x"]=3, ["y"]=1, ["z"]=2} -- Default size of the cards
gt_DECODE_DIR = { [0]={"x",-1}, [90]={"z",-1}, [180]={"x",1}, [270]={"z",1} } -- table used to help decode directions based on rotation (0, 90,180,270)
gt_COLOR_ROT  = {White=0, Blue=180, Green=90, Red=270}  -- hand zone rotY per player color

gt_PANEL_VERTICAL_OFFSET_BY_ROWNUM = {[1]=-43,[2]= -73,[3]= -103,[4]= -133}  -- offset to set the 1st icon at, based on the rownumber
gt_ALIGN_WORDS = {[-3] = "off", [-1]="off", [1]="high", [3]="low"}           -- pretty word to use for how alignment is done, based on special math (see its use)
gt_PLAYER_COLOR_BY_NUM={[1]="White",[2]="Green",[3]="Blue",[4]="Red"}        -- The general order of players on the board, must sync with playerStuff[-].num
gi_RED_BOOK_SCORE = 500
gi_BLACK_BOOK_SCORE = 300
gi_WILD_BOOK_SCORE = 1500
gbHandWonPause = false
gLEFT  = 0
gRIGHT = 1
gUP    = 2
gDOWN  = 3

-- Globals -------------------------------------------------------------------------
-- Values that are set globally and expected to change over time
gbFinishFlag = false        -- a temporary state boolean declaring whether the FinishFlag should be presented
gbPlaySounds=false          -- admin boolean to play sounccube sounds or not (generally not when using turns)
giDiscardSound = 9          -- if playing sounds, use this one for a discard
gbShowDirButtons=false      -- whether to display the x/z buttons useful for debugging orientation
gbDevGhostBoxes=false       -- show ghost boxes from .Cast calls
giCurNumPlayersOnFelt = -1  -- records the number of players in the current surface, to avoid repaints
--PanelHeightBeforeClose=0    -- before someone closes the UI panel, save the height for resetting it
                            -- arguably, this should be by-player but the size of the panel should be
                            -- the same for each of them so there's little harm
giHand=0                    -- Current hand number (zero before first deal)
gfDealDelayMult = .2        -- multiplier for the amount of time to delay each individual deal of a card by (makes it prettier)
gsGoesFirstColor = ""       -- Color of the player who is to go first in current hand
gsFirstToGoFirstColor = ""  -- Color of the player who goes first in the first hand of the game
gfSpreadMult = .8           -- How much gap to put between cards when laying out in a row
gsSortedPlayerScoresheetIndex={}  -- Array indicating which row of the scoresheet an individual color is
                                  -- This is needed b/c sometimes it's just White/Green, skips blue (2 player), etc..
gtScores = {[1]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},  -- Table of scores for the scoreboard
          [2]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
          [3]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
          [4]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0}}
giNewgameCountdown = 6      -- The number of seconds remaining in the countdown for doing a new deal
gfDropShift = .5


-- ==================================================
-- Variables used for debugging
-- ==================================================
gtDebugFlags={
--          ["dropped"]=1,
--["spread"]=1,
--layoutsel=1,
["decal"]=1,
--  vertical2=1,
--["getallscorezones"]=1,
--          ["weird"]=1,
--          ["buttons"]=1,
}


-- Peoplez be liking all sorts of different ways of sorting
refCardOrder = {"Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Joker", } -- The original, not really used
refCardOrderLAceL = {"Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Joker", } -- Low2High is Left2Right, Ace is Low
refCardOrderRAceL = {"Joker", "King", "Queen", "Jack", "10", "9", "8", "7", "6", "5", "4", "3", "2", "Ace" }  -- Low2High is Right2Left, Ace is Low
refCardOrderLAceH = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King","Ace", "Joker", } -- Low2High is Left2Right, Ace is High
refCardOrderRAceH = {"Joker", "Ace", "King", "Queen", "Jack", "10", "9", "8", "7", "6", "5", "4", "3", "2", } -- Low2High is Right2Left, Ace is High
refSuitOrder = {"Clubs", "Spades", "Hearts", "Diamonds", "BW", "Color", }  -- The original code had suit sorting, I left it for future stealing but we don't care about suits
refCardOrderIndex={}  -- Reverse Index of one of the refCardOrders
                      -- Used as a high performance method (i.e. no iteration) to find the index of a given value, such as:
                      -- return refCardOrderIndex["Seven"]
                      -- the index returned depends on which of the tables, above, are used to set the value
                      -- of this table, just before it is used.


-- -----------------------------------------------------------------------------
-- initial code for setting up basic Values
-- Kinda weird to have code outside of a function, but it runs when the code Loads
-- and not again
-- -----------------------------------------------------------------------------
-- Reverse Index of refSuitOrder
-- Used as a high performance method (i.e. no iteration) to find the index of a given value, such as:
-- return refSuitOrderIndex["Diamond"]
local refSuitOrderIndex={}
for k,v in pairs(refSuitOrder) do
  refSuitOrderIndex[v]=k
end




-- =============================================================================
function admin_deckem()
  -- This is a dev utility, it will split the deck into multiple rows,
  -- one per standard deck, with 13 piles of each unique card value
  local aPulled={[1]={}}
  -- SubFunction
  function admin_deckemOneCardPos(oneCard)
    local _, sName, sSuit  = cardDeets(oneCard)
    iPull=1
    while (aPulled[iPull] and aPulled[iPull][oneCard.description]) do
      iPull=iPull+1
    end
    if (not aPulled[iPull]) then
      aPulled[iPull]={}
    end
    aPulled[iPull][oneCard.description]=1
    local iOrd = refCardOrderIndex[sName]
    local tParam = {position={x=30-iOrd*2.5, y=3, z=-25+(iPull-1)*3.5}, flip=true, rotation={0,0,0}, guid=oneCard.guid, smooth=false}
    return tParam
  end

  admin_sinkWalls()
  mainDeck = initializeHand()
  if (mainDeck) then
    mainDeck.setPosition({-30, 3, 30})
    setSortOrder(true,true)
    local tDeckCards = mainDeck.getObjects()
    for i, oneCard in ipairs(tDeckCards) do
      local tParam = admin_deckemOneCardPos(oneCard)
      if (mainDeck.getQuantity()==0) then
        oneCard = mainDeck.remainder
        oneCard.flip()
        oneCard.setPosition(tParam.position)
      else
        mainDeck.takeObject(tParam)
      end
    end
  else
    log ("Error: no MainDeck?!?")
  end
  log("x")
end



-- =============================================================================
function recordScores()
  -- execute a tally of scores and update the current hand on the scoresheet
  debug("recording scores","panel")
  debug(dump(gtScores),"panel")

    bRunScoring= true
    setButtons()
    local fourScores = countScoreInternal()
    countScore()

    for sColor, iScore in pairs(fourScores) do
      local i = playerStuff[sColor].num
      debug("scolor=".. sColor,"panel")
      debug("playernum="..i,"panel")
      debug("score="..iScore,"panel")
      debug("giHand="..giHand,"panel")
      UI.setAttribute("P".. playerStuff[sColor].num .. "R" .. giHand .. "Score","text",iScore)
      gtScores[i][giHand]=iScore
      debug("S[1][1]=" ..gtScores[i][giHand],"panel")
      debug(dump(gtScores),"panel")
    end
    refreshScoresheet()
    debug(dump(gtScores),"panel")

end

-- =============================================================================
function round(fNum, iDec)
  -- There wasn't a round function that let you round to a decimal
  -- technically, it's not a rounding, it always "rounds up" but it's
  -- good enough
  -- fNum - number to be rounded
  -- iDec - number of decimal places to which to round
  if (not iDec) then
    return math.ceil(fNum)
  end
  return math.ceil(fNum * 10^iDec) / 10^iDec
end

-- =============================================================================
function dump(o)
    -- convenience for debugging.
    -- takes a thing (object, table, number..) and returns a string that
    -- represents it the best
    -- o - object to be dumped
    if type(o) == 'table' then
        if (o.x and o.y and o.z) then
          return "(x,y,z) = (".. round(o.x,1) .. "," .. round(o.y,1) .. "," .. round(o.z,1) .. ")"
        else
          local s = '{ '
          for k,v in pairs(o) do
                  if type(k) ~= 'number' then k = '"'..k..'"' end
                  s = s .. '['..k..'] = ' .. dump(v) .. ','
          end
          return s .. '} '
      end
    else
        if (tonumber(o)) then
          o = round(tonumber(o),2)
        end
        if (type(o) == 'userdata'
            and o.tag
            and o.tag=="Card") then
          return "card: " .. o.getDescription()
        else
          return tostring(o)
        end
    end
end
----
-- =============================================================================
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

-- =============================================================================
function ClosePanel(oPlayer)
    -- called when a player chooses to close the panel.
    -- oPlayer - the player instance who is closing their panel
    playerStuff[oPlayer.color].bScoreVisible = not playerStuff[oPlayer.color].bScoreVisible
    setPanelVisibility()
end



-- =============================================================================
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


-- =============================================================================
function totalScores()
  -- Calculate the total scores from the gtScores table and place them
  -- into the total column of the same table (display on screen will be elsewhere)
  for k, v in pairs(gtScores) do
    local tot = 0
    for i, s in pairs(v) do
      if (tonumber(s)) then
        if (i<5) then
          tot=tot+tonumber(s)
        end
      end
    end
    gtScores[k][5]=tot
  end
end


-- =============================================================================
function refreshScoresheet()
  -- update the scoresheet UI Panel
  -- this goes well beyond just updating the scores.  This sets the number of players,
  -- resizes the panel, sets the "1st" icon, etc

  debug("Refreshing Scoresheet","panel")
  totalScores()

  local iSeatedPlayersBeforeGoesFirst = 0
  local bHitGoesFirst = false
  UI.setAttribute("WindowTitle","text","Score Sheet - Hand " .. giHand)
  for player = 1, gi_NUM_ROWS do
    if (Player[gt_PLAYER_COLOR_BY_NUM[player]].seated) then
      if ((not bHitGoesFirst) and (gsGoesFirstColor != gt_PLAYER_COLOR_BY_NUM[player])) then
        iSeatedPlayersBeforeGoesFirst = iSeatedPlayersBeforeGoesFirst + 1
      end
      if (gsGoesFirstColor == gt_PLAYER_COLOR_BY_NUM[player]) then
        bHitGoesFirst = true
      end
      for hand = 1, gi_NUM_COLUMNS do
        local scoreId = "P".. player .."R".. hand .. "Score"
        debug("updating " .. scoreId,"panel")
        if (gtScores[player] and gtScores[player][hand]) then
          debug("with " .. gtScores[player][hand],"panel")
          UI.setAttribute(scoreId, "text",iif(gtScores[player][hand]==0,"",gtScores[player][hand]))
        else
          UI.setAttribute(scoreId, "text","")
        end
      end
      UI.setAttribute("ScoreRow"..player,"active","true")
      debug("setting ScoreRow"..player..".active = true","seated")
    else
      UI.setAttribute("ScoreRow"..player,"active","false")
      debug("setting ScoreRow"..player..".active = false","seated")
    end
  end

  local pos = 0
  if (gt_PANEL_VERTICAL_OFFSET_BY_ROWNUM[iSeatedPlayersBeforeGoesFirst+1]) then
     pos = gt_PANEL_VERTICAL_OFFSET_BY_ROWNUM[iSeatedPlayersBeforeGoesFirst+1]
     UI.setAttribute("GoesFirst","offsetXY","2 " .. pos)
     UI.setAttribute("GoesFirst","active","true")
  end

  setPlayerNamesOnScoresheet()
  setActionPanelVisibility()

end

-- =============================================================================
function setPlayerNamesOnScoresheet()
  -- Set up the panel with the right players and their names/nicks
  UI.setAttribute("ScoreRow1","active","false")
  UI.setAttribute("ScoreRow2","active","false")
  UI.setAttribute("ScoreRow3","active","false")
  UI.setAttribute("ScoreRow4","active","false")
  debug("setting ScoreRow1"..".active = false","seated")
  debug("setting ScoreRow2"..".active = false","seated")
  debug("setting ScoreRow3"..".active = false","seated")
  debug("setting ScoreRow4"..".active = false","seated")
  playerList = getSortedSeatedPlayers()
  debug("sortedseated players = ...","seated")
  debug(playerList,"seated")
  gsSortedPlayerScoresheetIndex={}
  for iP, playerColor in ipairs(playerList) do
    local num = playerStuff[playerColor].num
    local nick = playerStuff[playerColor].nick
    if (not nick or nick=="") then
      nick = Player[playerColor].steam_name
    end
    UI.setAttribute("Player"..num,"text",nick)
    UI.setAttribute("ScoreRow"..num,"active","true")
    gsSortedPlayerScoresheetIndex[playerColor] = iP
    debug("setting ScoreRow"..num..".active = true","seated")
  end
  UI.setAttribute("ScoreTable","height",(1+#playerList)*30)
  UI.setAttribute("SubPanel","height",(1+#playerList)*30+20)
end

-- =============================================================================
function onPlayerChangeColor( player_color)
  -- This is a TTS Event, called when someone changes colors (sits, stands, etc..)
  -- we want to change the score panel.  If they change to grey, let's do Nothing
  -- they are probably just resetting their own interface and rejiggering the
  -- panel can screw things up
  if (player_color != 'Grey') then
    setPlayers()
    setPlayerNamesOnScoresheet()
    setActionPanelVisibility()
  end
end

-- =============================================================================
function debug(str, grp)
  -- for debugging, this does a "log" but only if the grp passed in is in the
  -- gtDebugFlags table.  This lets you leave debug statements in the code all
  -- over the place but not be overloading the output with noise you don't need
  -- at the moment
  -- str - Message to be displayed
  -- grp - the name of the debug flag to look for
  if grp then
    if (gtDebugFlags[grp]) then
      --writeToNotebookTab(str)
      log(str)
    end
  else
    -- log(str)
  end
end

-- =============================================================================
function click_DoNothing(_, color)
-- a null function as one is required for buttons but not always needed
end

-- =============================================================================
function setActionPanelVisibility()
  -- Action panel is only for White.
  -- Use active=true/false (not just visibility) because TTS doesn't reliably
  -- re-evaluate visibility= when a player changes seats.
  -- Use Player["White"].seated (canonical TTS property) rather than iterating
  -- Player.getPlayers(), which can lag behind the actual seat state.
  Wait.time(function()
    local ok, whiteSeated = pcall(function() return Player["White"].seated end)
    if ok and whiteSeated then
      UI.setAttribute("ActionPanel", "visibility", "White")
      UI.setAttribute("ActionPanel", "active", "true")
    else
      UI.setAttribute("ActionPanel", "active", "false")
    end
  end, 0.3)
end

-- onPlayerTurnStart fires when the turn system advances to a new player.
-- Use it as a second trigger for panel visibility so that returning to the
-- White seat after another player's turn reliably restores the panel even
-- if onPlayerChangeColor fires in an unexpected order in hotswap mode.
function onPlayerTurnStart(player_color, prev_player_color)
  setActionPanelVisibility()
end

-- =============================================================================
-- Action Panel handlers
-- The panel is declared in Global.-1.xml (id="ActionPanel").
-- onClick receives a player object; extract .color for game functions.

function click_ToggleActionPanel(player)
  local current = UI.getAttribute("ActionSubPanel", "active")
  UI.setAttribute("ActionSubPanel", "active", current == "true" and "false" or "true")
end

function click_ActionPlayHand(player)
  autoPlayMatchingCards(player.color)
end

-- "Play and Lay": layout all eligible ranks, then play any newly-matched hand
-- cards onto the table.  Red 3s are handled once up front; both sub-operations
-- receive skipRedThrees=true so they don't repeat the check.
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

-- "Draw, Sort, Play Lay": draw 2, sort, play hand, then layout all.
-- Sequence: deal → wait for cards to arrive → red 3s → sort →
--           play hand onto existing melds → layout remaining eligible ranks.
function click_ActionDrawSortPlayLay(player)
  local sColor = player.color

  -- Draw 2 cards from the main deck.
  if mainDeck then
    pcall(function() mainDeck.deal(1, sColor) end)
    Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, 0.5)
  end

  -- Wait for cards to arrive in hand, then handle red 3s and continue.
  Wait.time(function()
    handleRedThrees(sColor, function()
      -- Sort is synchronous — runs immediately after red 3s are cleared.
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
  end, 2.5)
end

-- Draw 2 cards from the main deck then handle any red 3s that arrive.
function click_ActionDraw(player)
  local sColor = player.color
  if not mainDeck then return end

  -- Snapshot GUIDs already in hand before dealing.
  local preDraw = {}
  pcall(function()
    for _, obj in ipairs(Player[sColor].getHandObjects()) do
      preDraw[obj.guid] = true
    end
  end)

  pcall(function() mainDeck.deal(1, sColor) end)
  Wait.time(function() pcall(function() mainDeck.deal(1, sColor) end) end, 0.5)

  -- After both cards have landed: report drawn cards to player, then sort.
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

  Wait.time(function()
    handleRedThrees(sColor, function()
      Wait.time(function() sortHand(nil, sColor) end, 0.5)
    end)
  end, 2.5)
end

-- Stored plan from the last click_ActionPlan call; held so click_PlanExecute can use it.
gPlanResult = nil

-- Build the turn plan, populate the result panel, and show it.
function click_ActionPlan(player)
  local sColor = player.color
  gPlanResult = buildTurnPlan(sColor)
  -- InputField text: join log lines with newline characters.
  -- Set text before making the panel active so layout is correct on first show.
  local text = table.concat(gPlanResult.log, "\n")
  if text == "" then text = "(no plan output)" end
  UI.setAttribute("PlanResultText", "text", text)
  Wait.time(function()
    UI.setAttribute("PlanResultPanel", "active", "true")
  end, 0.05)
end

-- Close the plan result panel without executing.
function click_PlanClose(player)
  UI.setAttribute("PlanResultPanel", "active", "false")
  gPlanResult = nil
end

-- Execute the stored plan, then close the panel.
function click_PlanExecute(player)
  UI.setAttribute("PlanResultPanel", "active", "false")
  if gPlanResult then
    executeTurnPlan(gPlanResult)
    gPlanResult = nil
  end
end

-- =============================================================================
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


-- =============================================================================
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


-- =============================================================================
function click_NewGame(_, color)
  -- on button press, start a countdown to press this button again
  -- to deal a new game (technically, it's a different button but seems to be
  -- the same one to the user)
  giNewgameCountdown=6
  setButtons()
  Wait.time(function() setButtons() end, 1.0)
end

-- =============================================================================
function click_NewGameSure(_, color)
  -- user clicked the newgame button while it was still within the countdown
  -- (otherwise, it would have been changed back to the orig button)
  -- so let's deal!
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
  else
    gbDealing=true
    mainDeck = initializeHand()
    Wait.time(function() initializeVariables() dealDeck(mainDeck) end, 1.0)
    debug("md1: " .. mainDeck.guid)
  end
end

-- =============================================================================
function ClearScores()
  -- name says it all.. reset the scores in the array to zero
  gtScores = {[1]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [2]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [3]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [4]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0}}
end

-- =============================================================================
function resetScoresheet()
  -- clear scores and redisplay the scoresheet
  ClearScores()
  refreshScoresheet()
end

-- =============================================================================
function setHand(iNewHand)
  -- a new hand is being requested.  The number might have been indexed beyond
  -- 4, if so, it means a new game and we'll clear the scores.
  giHand=iNewHand
  copyScores()
  if (giHand>4) then
    giHand=1
    printToAll("Starting a new game!")
    printToAll("previous scores were recorded to a notebook tab")
    ClearScores()
  end
end

-- =============================================================================
function getSortedSeatedPlayers()
  -- get the seated players and return a table of them, sorted by
  -- the seat number in playerStuff (clockwise from white=1)
  local lplayerList = getSeatedPlayers()
  table.sort(lplayerList,function (e1, e2) return playerStuff[e1].num < playerStuff[e2].num end )
  return lplayerList
end

-- =============================================================================
function setPlayers(tPlayerList)
  -- Make sure the table is primed for the number of players we have
  -- (score zones, etc.. )  if we're not passed a list of players
  -- then get our own
  if (not tPlayerList) then
    tPlayerList = getSortedSeatedPlayers()
  end
  if (#tPlayerList!=giPlayerCount) then
    giPlayerCount=#tPlayerList
  end
  layoutScoreZones(giPlayerCount)

end


-- =============================================================================
function dealDeck(oMainDeck)
  -- one of the main functions.. this deals out the cards to all playerStuff
  -- mainDeck - the deck from which to deal
--   gbDealing = true  -now done before this call by the click function
  bRunScoring= false
  playerList = getSortedSeatedPlayers()
  if (not giPlayerCount) then
    giPlayerCount = #playerList
  end
  setPlayers(playerList)
  setButtons()
  setCardDecal()
  text_score_white.TextTool.setValue(" ")
  text_score_blue.TextTool.setValue(" ")
  text_score_green.TextTool.setValue(" ")
  text_score_red.TextTool.setValue(" ")
  setHand(giHand+1)
  refreshScoresheet()

  textDiscardValue.TextTool.setValue(" ")
  textDiscardValue.TextTool.setFontColor("Black")

  --log ("oMainDeck g:" .. oMainDeck.guid)
  --log("foot deal")
  for i = 1,giStartFootCards do
    for iP, playerColor in ipairs(playerList) do
--      log(objScoreZones[giPlayerCount][playerColor].footPos)
      Wait.time(function() local card = oMainDeck.dealToColorWithOffset({objScoreZones[giPlayerCount]["Colors"][playerColor].footPos[1],objScoreZones[giPlayerCount]["Colors"][playerColor].footPos[2]+(i),objScoreZones[giPlayerCount]["Colors"][playerColor].footPos[3]} ,false, playerColor)  end, (iP/#playerList/2 + i/2)*gfDealDelayMult )
    end
  end
  --log("hand deal")
  for j=1,giStartHandCards do
    for iP2, splayerColor in ipairs(playerList) do
--      Wait.time(function() addToPlayer(playerColor, oMainDeck.dealToColorWithOffset({0,1,0}, true, playerColor)) end, giStartFootCards/3 + i/3)
      Wait.time(function() oMainDeck.deal(1,splayerColor) end, (giStartFootCards/2 +2+ iP2/#playerList/2 + j/2)*gfDealDelayMult)
    --local dealt= oMainDeck.dealToColorWithOffset({0,1,0}, true, playerColor)
      --addToPlayer(playerColor, dealt)
    end
  end
  -- Wait a while till we're pretty sure we're done dealing and then reflect that
  Wait.time(function() doneDealing(oMainDeck) end, (giStartFootCards/2 + giStartHandCards/2 +  3)*gfDealDelayMult+1)
end

-- =============================================================================
function doneDealing(oMainDeck)
  -- we're done dealing, do wrapup stuff (flip first discard, etc.)

  if (giRuleSet == giCaliforniaRules) then
      -- flip out the discard.  if it's wild or red-3, shuffle it in and try again
      local obj = oMainDeck.takeObject({position = obj_Zone_Discard.getPosition(), flip=true})
      local shortColor, shortName, _ = cardDeets(obj)
      if (shortColor == "Wild") or (shortColor == "Red" and shortName=="3") then
        oMainDeck.putObject(obj)
        oMainDeck.shuffle()
        doneDealing(oMainDeck)
        return
      end
  end

  if (giHand==1) then
    gsFirstToGoFirstColor = whoIsFirst()
  end
  playerList = getSortedSeatedPlayers()
  debug("Trying-----------"..gsFirstToGoFirstColor, "order")
  debug("firsttogofirst="..gsFirstToGoFirstColor,"first")

-- No first to go first if resettting the table mid-Game
  debug("firsttogofirst.index="..gsSortedPlayerScoresheetIndex[gsFirstToGoFirstColor],"first")
  debug("hand="..giHand,"first")
  debug("#playerList="..#playerList,"first")
  local iFirstIndex = ((gsSortedPlayerScoresheetIndex[gsFirstToGoFirstColor]+giHand-2)%#playerList)+1
  debug("playerlist...","first")
  debug(playerList,"first")
  debug("firstindex="..iFirstIndex,"first")
  debug("t1", "seated")
  gsGoesFirstColor = playerList[iFirstIndex]
  debug("t2", "seated")
  if (gb_USE_TURNS) then
    debug("t2.1", "seated")
    Turns.turn_color=gsGoesFirstColor
  end
  debug("t3", "seated")
  debug("gsGoesFirst="..gsGoesFirstColor,"first")
  refreshScoresheet()
  debug("t4", "seated")
  broadcastToAll(coolName(gsGoesFirstColor) .. " Goes First!")

  Wait.time(function() gbDealing = false end, 2.0)

end

-- =============================================================================
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

-- =============================================================================
function stackCards()
  -- grab up all cards from everywhere and plunk them in a deck in the
  -- center section of the table (for starting over a new game, generally)
  local main = nil
  local tblObj = getAllObjects()
  for _, one in ipairs(tblObj) do
    if (one.tag=="Card") or (one.tag=="Deck") then
      if not ((one.tag=="Deck") and (one.getQuantity()>900)) then
        if (not main) then
          --log("Got Main")
          main = one
          main.setRotation({180,0,0})
          main.setPosition({-2,2,0.35})
        else
          main.putObject(one)
        end
        --log(one.guid)
      end
    end
  end

  if (main) then
  --  Wait.time(function() main.randomize() end,0.25,8)
  end
  debug("**stacking done")
  return main
end

-- =============================================================================
function initializeVariables()
  -- set up values for a new Game
  giInsertCount = 0
  tableDiscard = {}
  textScore.TextTool.setValue(" ")
  textDiscardValue.TextTool.setValue(" ")
  giNewgameCountdown=0
  bScoreShowing=false
  if (giRuleSet == giCaliforniaRules) then
    giStartFootCards=13
    giStartHandCards=13
    giRed3Penalty=100
    giRed3SideStackScore=100
  elseif (giRuleSet == giNorthCarolinaRules) then
    giStartFootCards=11
    giStartHandCards=13
    giRed3Penalty=300
    giRed3SideStackScore=300
  end
  gbInitializing = false
end

-- =============================================================================
function initializeGame()
  -- Start up a brand new game.  Hand = zero, blank the scoresheet and start a new hand
  setHand(0)
  resetScoresheet()
  initializeHand()
end


-- =============================================================================
function initializeHand()
  -- fire up a new hand... save the old scores, restack cards, and shuffle
  gbInitializing = true
  copyScores()
  local maindeck = stackCards()
  initializeVariables()
  debug("Initialized...")
  maindeck.shuffle()   -- one shuffle is enough but many is pretty
  maindeck.shuffle()
  maindeck.shuffle()
  maindeck.shuffle()
  maindeck.shuffle()
  Wait.time(function () maindeck.shuffle() end, 0.5 ,5)  -- a little delay, just to make it last longer.. still just cosmetic after the first
  Wait.time(function () setCardDecal() end, 0.5 ,5)

  return maindeck
end

-- =============================================================================
function SaveScores()
  -- get the scores from the scoresheet and save them to the gtScores table
  for player = 1, gi_NUM_ROWS do
    local scoreT = {}
    for score = 1, gi_NUM_COLUMNS do
      local scoreId = "P".. player .."R".. score .. "Score"
--      debug("saving " .. scoreId, "panel" )
--      debug(UI.getAttribute(scoreId, "text"),"panel")
      table.insert(scoreT, UI.getAttribute(scoreId, "text"))
    end
    gtScores[player] = scoreT;
  end
end

-- =============================================================================
-- ActionQueue: lightweight sequencer for multi-step async operations.
--
-- Usage:
--   local q = ActionQueue.new()
--   q:push(function() ... end, 0.5)   -- step fires 0.5s after previous
--   q:push(function() ... end, 1.0)
--   q:run()
--
-- The queue accumulates absolute Wait.time offsets and fires each step in order.
-- Steps are closures; the queue holds no TTS object references itself.
ActionQueue = {}
ActionQueue.__index = ActionQueue

function ActionQueue.new()
  return setmetatable({steps={}, t=0}, ActionQueue)
end

-- Add a step: fn will be called `delay` seconds after the previous step's
-- scheduled time (or after q:run() is called for the first step).
function ActionQueue:push(fn, delay)
  self.t = self.t + (delay or 0)
  table.insert(self.steps, {fn=fn, t=self.t})
end

-- Schedule all queued steps via Wait.time. Safe to call on an empty queue.
function ActionQueue:run()
  for _, step in ipairs(self.steps) do
    local captured = step.fn
    Wait.time(captured, step.t)
  end
end

-- =============================================================================
function onSave()
  debug("saved-----------", "loaded")
  local t = {
    ["f2gfc"] = gsFirstToGoFirstColor,
    ["scores"] = gtScores,
  }
  saved_data = JSON.encode(t)
  debug("saving-----------", "loaded")
  debug(saved_data, "loaded")

  return saved_data

end


function onLoad(saved_data)
  --  --Load Data
    if saved_data ~= "" then
      debug("Loading saved data!","loaded")
      debug(saved_data,"loaded")
      local loaded_data = JSON.decode(saved_data)
      --Set Global Variables
      gtScores        = loaded_data.scores
      gsFirstToGoFirstColor = loaded_data.f2gfc
    end

  for _, oThing in pairs(self.getObjects()) do
    if oThing.tag == 'Deck'
        and oThing.getQuantity()>200 then
      mainDeck = oThing
    end
    -- look for cardicons that've been saved in development
    -- and wipe them out since they won't be in the aCardIcons array anymore
    if oThing.hasTag("CardIcon") then
      oThing.destruct()
    end
  end
  --  SOUND_CUBE = '8d1d25'
  debug("loaded-----------", "loaded")
  log("Loaded")
  log("+++++++++++++++++++++++++++++++++++++++++++++++++")
  log("*************************************************")
  log("*************************************************")
  SOUND_CUBE = 'a98418' -- This is the new sound cube
  soundCube = getObjectFromGUID(SOUND_CUBE)

  FOOTNOTE_TEXT_WHITE = '342071'
  FOOTNOTE_TEXT_BLUE = '6def21'
  FOOTNOTE_TEXT_GREEN = 'ea9d5a'
  FOOTNOTE_TEXT_RED = 'dd2fa4'
  textFootNotes = {}
  textFootNotes["White"] = getObjectFromGUID(FOOTNOTE_TEXT_WHITE)
  textFootNotes["Green"] = getObjectFromGUID(FOOTNOTE_TEXT_GREEN)
  textFootNotes["Blue"] = getObjectFromGUID(FOOTNOTE_TEXT_BLUE)
  textFootNotes["Red"] = getObjectFromGUID(FOOTNOTE_TEXT_RED)



  WALL_1 = '907e11'
  WALL_2 = '00bb0a'
  WALL_3 = '4d78c6'
  WALL_4 = 'f0f4fa'

  objWalls = {
    [1] = getObjectFromGUID(WALL_1),
    [2] = getObjectFromGUID(WALL_2),
    [3] = getObjectFromGUID(WALL_3),
    [4] = getObjectFromGUID(WALL_4),
  }

  SCORE_TEXT_WHITE = '4a3157'
  SCORE_TEXT_BLUE = '67ea6c'
  SCORE_TEXT_GREEN = '3e97b1'
  SCORE_TEXT_RED= 'e51db7'
  text_score_white = getObjectFromGUID(SCORE_TEXT_WHITE)
  text_score_blue = getObjectFromGUID(SCORE_TEXT_BLUE)
  text_score_green = getObjectFromGUID(SCORE_TEXT_GREEN)
  text_score_red  = getObjectFromGUID(SCORE_TEXT_RED)
  text_score_white.TextTool.setValue(" ")
  text_score_blue.TextTool.setValue(" ")
  text_score_green.TextTool.setValue(" ")
  text_score_red.TextTool.setValue(" ")

  obj_scoretext = {["White"]=text_score_white,["Blue"]=text_score_blue,["Green"]=text_score_green,["Red"]=text_score_red,}


  ZONE_WHITE_SCORE1 = '6346d6'
  ZONE_WHITE_SCORE2 = '2f7232'
  ZONE_BLUE_SCORE2 = '517503'
  ZONE_BLUE_SCORE1 = '24e3af'
  ZONE_GREEN_SCORE1 = '4685c1'

  ZONE_SCORE_A = '6346d6' -- White Big
  ZONE_SCORE_B = '2f7232' -- White Sliver1
  ZONE_SCORE_C = '517503' -- Green big
  ZONE_SCORE_D = '24e3af' -- Blue Sliver1
  ZONE_SCORE_E = '4685c1' -- Blue big
  ZONE_SCORE_F = '23bb9b' -- Red big
  ZONE_SCORE_G = 'ccc9e6' -- Blue Sliver2
  ZONE_SCORE_H = '67630d' -- White Sliver2
  objAllScoreZones={}
  objAllScoreZones[1]=getObjectFromGUID(ZONE_SCORE_A)
  objAllScoreZones[2]=getObjectFromGUID(ZONE_SCORE_B)
  objAllScoreZones[3]=getObjectFromGUID(ZONE_SCORE_C)
  objAllScoreZones[4]=getObjectFromGUID(ZONE_SCORE_D)
  objAllScoreZones[5]=getObjectFromGUID(ZONE_SCORE_E)
  objAllScoreZones[6]=getObjectFromGUID(ZONE_SCORE_F)
  objAllScoreZones[7]=getObjectFromGUID(ZONE_SCORE_G)
  objAllScoreZones[8]=getObjectFromGUID(ZONE_SCORE_H)


  objScoreZones={
      -- Create 2P layout
      [2]= {
        ["Walls"] = {
          [1] = {-- blue tint
            ["scl"] = {0.10, 1.00, 14.21},  ["pos"] = {20.39, 2.00, -0.04},
          },
          [2] = {-- red tint
            ["scl"] = {0.10, 1.00, 14.39},  ["pos"] = {-20.54, 2.00, -0.08},
          },
          [3] = {-- green tint
            ["scl"] = {1,1,1},  ["pos"] = {0, -20, 0},
          },
          [4] = {-- yellow tint
            ["scl"] = {1,1,1},  ["pos"] = {0, -20, 0},
          },
        },
        ["Colors"] = {
          ["White"] = {
            ["footPos"]= {30,1,35},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[1],
                ["scl"] ={70.0, 5.0,30.3,},
                ["pos"] = { 0, 3.5, 20.1,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[2],
                ["scl"] = {29.20, 5.00, 4.37},
                ["pos"] = {-20.80, 3.50, 2.95},
              },
              [3] = {
                ["obj"] = objAllScoreZones[3],
                ["scl"] = {29.20, 5.00, 4.37},
                ["pos"] = {20.78, 3.50, 2.95},
              },
            },
          },
          ["Green"] = {
            ["footPos"]= {},
            ["zones"] = {},
          },
          ["Blue"] = {
            ["footPos"]={-30,1,35},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[4],
                ["scl"] = {70.06, 5.00, 30.20},
                ["pos"] ={0.13, 3.50, -20.90},
              },
              [2] = {
                ["obj"] = objAllScoreZones[5],
                ["scl"] = {29.20, 5.00, 4.37},
                ["pos"] = {-20.32, 3.50, -3.44},
              },
              [3] = {
                ["obj"] = objAllScoreZones[6],
                ["scl"] = {29.20, 5.00, 4.37},
                ["pos"] = {20.78, 3.50, -3.44},
              },
            },
          },
          ["Red"] = {
            ["footPos"]= {},
            ["zones"] = {},
          },
          ["Hide"] = {
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[7],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[8],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
            },
          },
        }, -- end Colors
      }, -- end 2p
      [3]= {
        ["Walls"] = {
          [1] = {-- blue tint
            ["scl"] = {31.39, 1.00, 0.10},  ["pos"] = {5.40, 1.95, -19.98},
          },
          [2] = {-- red tint
            ["scl"] = {31.39, 1.00, 0.10},  ["pos"] = {5.41, 1.95, 20.16},
          },
          [3] = { -- green tint
            ["scl"] ={-30.38, 1.00, -0.10},  ["pos"] = {-20.40, 1.95, -0.09},
          },
          [4] = { -- yellow tint
            ["scl"] = {1,1,1},  ["pos"] = {0, -20, 0},
          },
        },
        ["Colors"] = {
          ["White"] = {
            ["footPos"]= {30,1,35},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[1],
                ["scl"] = { ["x"] = 40.0, ["y"] = 5.0,["z"] = 31.3,},
                ["pos"] = { ["x"] = -16.0,["y"] = 3.5,["z"] = 20.1,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[2],
                ["scl"] = { ["x"] = 31.0, ["y"] = 5.0,["z"] = 3.7,},
                ["pos"] = { ["x"] = -19.9,["y"] = 3.5,["z"] = 2.6,},
              },
            },
          },
          ["Green"] = {
            ["footPos"]={15,1,30},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[3],
                ["scl"] = { ["x"] = 29.5,["y"] = 5.0,["z"] = 71.7,},
                ["pos"] = { ["x"] = 21.2,["y"] = 3.5,["z"] = 0.15,},
              },
            },
          },
          ["Blue"] = {
            ["footPos"]={-30,1,35},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[4],
                ["scl"] = { ["x"] = 40.2,["y"] = 5.0,["z"] = 31.3,},
                ["pos"] = { ["x"] = -15.5,["y"] = 3.5,["z"] = -19.9,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[5],
                ["scl"] = { ["x"] = 31.0,["y"] = 5.0,["z"] = 3.7,},
                ["pos"] = { ["x"] = -19.9,["y"] = 3.5,["z"] = -2.7,},
              },
            },
          },
          ["Red"] = {
            ["footPos"]= {},
            ["zones"] = {},
          },
          ["Hide"] = {
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[6],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[7],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [3] = {
                ["obj"] = objAllScoreZones[8],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
            },
          },
        },
      }, -- end 3p
      [4]= {
        ["Walls"] = {
          [1] = { -- blue tint
            ["scl"] = {31.19, 1.00, 0.10},  ["pos"] = {5.45, 1.95, -19.90},
          },
          [2] = { -- red tint
            ["scl"] = {29.78, 1.00, 0.10},  ["pos"] = {-5.38, 1.95, 20.14},
          },
          [3] = { -- green tint
            ["scl"] = {30.40, 1.00, 0.10},  ["pos"] = {-20.79, 1.95, -4.26},
          },
          [4] = { -- yellow tint
            ["scl"] = {29.59, 1.00, 0.10},  ["pos"] = {20.54, 1.93, 4.43},
          },
        },
        ["Colors"] = {
          ["White"] = {
            ["footPos"]= {-30,1,20},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[1],
                ["scl"] = { ["x"] = 39.8,["y"] = 5.0,["z"] = 30.3,},
                ["pos"] = { ["x"] = 15.3,["y"] = 3.5,["z"] = 20.5,},
              },
            },
          },
          ["Green"] = {
            ["footPos"]= {-30,1,20},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[2],
                ["scl"] = { ["x"] = 28.8, ["y"] = 5.0,["z"] = 38.3,},
                ["pos"] = { ["x"] = 20.8,["y"] =  3.5,["z"] = -15.96,},
              },
            },
          },
          ["Blue"] = {
            ["footPos"]= {-30,1,20},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[3],
                ["scl"] = { ["x"] = 39.8,["y"] = 5.0,["z"] = 30.2,},
                ["pos"] = { ["x"] = -15,["y"] = 3.5,["z"] = -20.9,},
              },
            },
          },
          ["Red"] = {
            ["footPos"]= {-30,1,20},
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[4],
                ["scl"] = { ["x"] = 29.2,["y"] = 5.0,["z"] = 38.9,},
                ["pos"] = { ["x"] = -20.8,["y"] = 3.5,["z"] = 16.9,},
              },
            },
          },
          ["Hide"] = {
            ["zones"] = {
              [1] = {
                ["obj"] = objAllScoreZones[5],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [2] = {
                ["obj"] = objAllScoreZones[6],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [3] = {
                ["obj"] = objAllScoreZones[7],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
              [4] = {
                ["obj"] = objAllScoreZones[8],
                ["scl"] = { ["x"] = 1,["y"] = 1,["z"] = 1,},
                ["pos"] = { ["x"] = -20.6,["y"] = -40.0,["z"] = 16.2,},
              },
            },
          },
        }, -- end Colors
      }, -- end 4P
  }

--  ["Hide"] = {
--    [1] = {
--      ["obj"] = objAllScoreZones[x],
--      ["scl"] = ,
--      ["pos"] = ,
--    },
  -- Create 4P layout



  obj_scorezone = {}
  obj_scorezone["White"]={[1]=getObjectFromGUID(ZONE_WHITE_SCORE1),[2]=getObjectFromGUID(ZONE_WHITE_SCORE2)}
  obj_scorezone["Green"]={[1]=getObjectFromGUID(ZONE_GREEN_SCORE1)}
  obj_scorezone["Blue"]={[1]=getObjectFromGUID(ZONE_BLUE_SCORE1),[2]=getObjectFromGUID(ZONE_BLUE_SCORE2)}

  -- writeToNotebookTab("Scale",1)
  -- writeToNotebookTab("1:" .. dump(objAllScoreZones[1].getScale()),1)
  -- writeToNotebookTab("2:" .. dump(objAllScoreZones[2].getScale()),1)
  -- writeToNotebookTab("3:" .. dump(objAllScoreZones[3].getScale()),1)
  -- writeToNotebookTab("4:" .. dump(objAllScoreZones[4].getScale()),1)
  -- writeToNotebookTab("5:" .. dump(objAllScoreZones[5].getScale()),1)
  -- writeToNotebookTab("6:" .. dump(objAllScoreZones[6].getScale()),1)
  -- writeToNotebookTab("7:" .. dump(objAllScoreZones[7].getScale()),1)
  -- writeToNotebookTab("8:" .. dump(objAllScoreZones[8].getScale()),1)
  -- writeToNotebookTab("Position",1)
  -- writeToNotebookTab("1:" .. dump(objAllScoreZones[1].getPosition()),1)
  -- writeToNotebookTab("2:" .. dump(objAllScoreZones[2].getPosition()),1)
  -- writeToNotebookTab("3:" .. dump(objAllScoreZones[3].getPosition()),1)
  -- writeToNotebookTab("4:" .. dump(objAllScoreZones[4].getPosition()),1)
  -- writeToNotebookTab("5:" .. dump(objAllScoreZones[5].getPosition()),1)
  -- writeToNotebookTab("6:" .. dump(objAllScoreZones[6].getPosition()),1)
  -- writeToNotebookTab("7:" .. dump(objAllScoreZones[7].getPosition()),1)
  -- writeToNotebookTab("8:" .. dump(objAllScoreZones[8].getPosition()),1)

  ZONE_DISCARD = 'b73d1b'
  ZONE_WHITE = '99215b'
  ZONE_BLUE = 'db740e'
  ZONE_RED = '344fb9'
  ZONE_GREEN = 'bc6118'

  obj_Zone_Green = getObjectFromGUID(ZONE_GREEN)
  obj_Zone_Red = getObjectFromGUID(ZONE_RED)
  obj_Zone_Blue = getObjectFromGUID(ZONE_BLUE)
  obj_Zone_White = getObjectFromGUID(ZONE_WHITE)
  obj_Zone_Discard = getObjectFromGUID(ZONE_DISCARD)
  tDiscardProps={position={x=2.85, y=4.03, z=0.19},scale={3.73, 5.10, 4.09}, rotation={0.00, 358.87, 0.00}}
  obj_Zone={}
  obj_Zone["Green"] = obj_Zone_Green
  obj_Zone["Red"] = obj_Zone_Red
  obj_Zone["Blue"] = obj_Zone_Blue
  obj_Zone["White"] = obj_Zone_White
  for sColor, zone in pairs(obj_Zone) do
    local c = sColor
    zone.addContextMenuItem("Layout All Hand",  function() layoutHandAll(c)         end, false)
  end

  objTable = getObjectFromGUID('bd69bd')

  bMaskActions=false
  TEXT_DISCARD_LABEL = 'e12cfa'
  TEXT_DISCARD_VALUE = '48206b'
  TEXT_SCORE = '0c201a'
  UI_TABLETOP_SURFACE = '4ee1f2'
  UI_CENTER_DECK = '27f04c'

  goSurface = getObjectFromGUID(UI_TABLETOP_SURFACE)

  giNewgameCountdown = 0
  gbSpreading = false
  gbDealing = false
  fromdeck={}
  fromdiscard={}
  --mainDeck = getObjectFromGUID(UI_CENTER_DECK);
  giCaliforniaRules = 0
  giNorthCarolinaRules = 1
  giNumRuleSets=2
  giRuleSet = giCaliforniaRules
  if (giRuleSet == giCaliforniaRules) then
    announceAll("California Rules In Effect")
  else
    announceAll("North Carolina Rules In Effect")
  end
  setButtons()

  textDiscardLabel = getObjectFromGUID(TEXT_DISCARD_LABEL)
  textDiscardValue = getObjectFromGUID(TEXT_DISCARD_VALUE)
  textScore = getObjectFromGUID(TEXT_SCORE)
  -- tablePlayerCards = nil
  -- tablePlayerDecks = nil

  abAutoLayout={}
  abAutoLayout["White"]=true
  abAutoLayout["Red"]=true
  abAutoLayout["Blue"]=true
  abAutoLayout["Green"]=false


  if not (playerStuff) then
    playerStuff={
      ["White"] ={num=1,
                  bShowFootNotes=false,   bQueuedFootNoteCheck=false,
                  bScoreVisible=true,
                  bAlign=1,
                  bAutoLayout=true,
                  bMaskActions=false,
                  bReallySort = false, iSortWaiter=0,  bSortLowLeft = true,   bSortAceHigh=true, sSortMetaOrder="wbpa3r>",
                  bSpreading=false, bSpreadQueued=false,
                  footPos={30,1,35},
                  drawcount=0,
                  drawcountdisc=0,
                  drawcountqueued=false,
                  footReminder=""},
      ["Green"] = {num=2,
                  bShowFootNotes=false, bQueuedFootNoteCheck=false,
                  bScoreVisible=true,
                  bAlign=1,
                  bAutoLay9out=true,
                  bMaskActions=false,
                  bReallySort = false, iSortWaiter=0, bSortLowLeft = true, bSortAceHigh=true, sSortMetaOrder="3apbwl<",
                  bSpreading=false, bSpreadQueued=false,
                  footPos={15,1,30},
                  drawcount=0,
                  drawcountdisc=0,
                  drawcountqueued=false,
                  footReminder=""},
      ["Blue"] = {num=3,
                  bShowFootNotes=true, bQueuedFootNoteCheck=false,
                  bScoreVisible=true,
                  bAlign=1,
                  bAutoLayout=true,
                  bMaskActions=false,
                  bReallySort = false, iSortWaiter=0, bSortLowLeft = true, bSortAceHigh=true, sSortMetaOrder="ar",
                  bSpreading=false, bSpreadQueued=false,
                  footPos={-30,1,35},
                  drawcount=0,
                  drawcountdisc=0,
                  drawcountqueued=false,
                  footReminder=""},
      ["Red"] = {num=4,
                  bShowFootNotes=true, bQueuedFootNoteCheck=false,
                  bScoreVisible=true,
                  bAlign=1,
                  bAutoLayout=true,
                  bMaskActions=false,
                  bReallySort = false, iSortWaiter=0, bSortLowLeft = true, bSortAceHigh=true, sSortMetaOrder="a",
                  bSpreading=false, bSpreadQueued=false,
                  footPos={-30,1,35},
                  drawcount=0,
                  drawcountdisc=0,
                  drawcountqueued=false,
                  footReminder=""},
    }

    -- Establish playerPrefs / playerState as named views into playerStuff.
    -- All three names reference the SAME per-player table for now so existing
    -- code using playerStuff[color] continues to work unchanged.
    --
    -- Intended field groupings (for new engine code and future split):
    --   playerPrefs[color]:  num, bShowFootNotes, bQueuedFootNoteCheck,
    --     bScoreVisible, bAlign, bAutoLayout, nick, sSortMetaOrder,
    --     bSortAceHigh, bSortLowLeft, bReallySort, iSortWaiter
    --   playerState[color]:  bSpreading, bSpreadQueued, bMaskActions,
    --     drawcount, drawcountdisc, drawcountqueued, footPos, footReminder
    --
    -- Full field-level separation (metatable proxy) is deferred until a
    -- dedicated audit/test pass can cover all ~100 playerStuff call sites.
    playerPrefs = playerStuff
    playerState = playerStuff
  end
    processSortCommand("White", playerStuff["White"].sSortMetaOrder)
    processSortCommand("Red", playerStuff["Red"].sSortMetaOrder)
    processSortCommand("Blue", playerStuff["Blue"].sSortMetaOrder)
    processSortCommand("Green", playerStuff["Green"].sSortMetaOrder)
    displaySort("White", "White", playerStuff["White"].sSortMetaOrder)
    displaySort("Red", "Red", playerStuff["Red"].sSortMetaOrder)
    displaySort("Green", "Green", playerStuff["Green"].sSortMetaOrder)
    displaySort("Blue", "Blue", playerStuff["Blue"].sSortMetaOrder)

--  end

addHotkey("Fix Books", function (playerColor, object, pointerPosition, isKeyUp)
  if (isKeyUp) then
    fixBooks()
    Player[playerColor].print("Fix Books", {r=0, g=1, b=1})
  end
end, true)

addHotkey("Dev Trigger", function (playerColor, object, pointerPosition, isKeyUp)
  if (isKeyUp) then
    finishFlag()
  end
end, true)

  addHotkey("Toggle Scoring", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      setCardDecal()
      click_ToggleScoring(_, playerColor)
      --objTable.call("updateSurfaceByURL","seconddb.com/GreenFeltFullSquare2pv2.png")
      --tb.call("click_loadMemory_wrapper", {1, "White", 3})
    end
  end, true);

  -- addHotkey("Deckem (RUINS GAME)", function (playerColor, object, pointerPosition, isKeyUp)
  --   if (isKeyUp) then
  --     admin_deckem()
  --   end
  -- end, true);

  addHotkey("Layout Selection (DESTRUCTIVE)", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      vRot = obj_Zone[playerColor].getRotation()
      layoutLargeSelection(playerColor, vRot)
    end
  end, true);


  addHotkey("Sort Hand", function (playerColor, object, pointerPosition, isKeyUp)
  if (isKeyUp) then
--      if (playerStuff[playerColor].bReallySort) then
      if (true) then
        playerStuff[playerColor].bReallySort = false
        playerStuff[playerColor].iSortWaiter = 0
        Wait.stop(playerStuff[playerColor].iSortWaiter)
        sortHand(self, playerColor)
      else
        Player[playerColor].broadcast("Press again to sort (10s)")
        playerStuff[playerColor].bReallySort=true
        playerStuff[playerColor].iSortWaiter = Wait.time(function() playerStuff[playerColor].bReallySort=false; playerStuff[playerColor].iSortWaiter = 0 end,10.0)
      end
  end
end, true)



  addHotkey("Draw 2", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      if mainDeck then
--        mainDeck.deal(1,playerColor)
--        mainDeck.deal(1,playerColor)
        if (not gbHandWonPause) then
          mainDeck.deal(1,playerColor)
          Wait.time(function() mainDeck.deal(1,playerColor) end, 0.25)
        else
          broadcastToColor("Drawing temporarily disabled.\nWas there a winner?", playerColor, "Yellow" )
        end
      end
    end
  end, true)

  addHotkey("Calc ## Scores", function (playerColor, object, pointerPosition, isKeyUp)
    checkNotes()
  end, true)

  addHotkey("Draw 1", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      if mainDeck then
--        mainDeck.deal(1,playerColor)
--        mainDeck.deal(1,playerColor)
        if (not gbHandWonPause) then
        mainDeck.deal(1,playerColor)
        else
          broadcastToColor("Drawing temporarily disabled.\nWas there a winner?", playerColor, "Yellow" )
        end
      end
    end
  end, true)

  addHotkey("Layout Pretty", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      spread3("s",playerColor,1)
    end
  end, true)

  addHotkey("Toggle AutoAlign", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      playerStuff[playerColor].bAlign=playerStuff[playerColor].bAlign*-1
      broadcastToColor("Alignment set to " .. gt_ALIGN_WORDS[playerStuff[playerColor].bAlign],playerColor)
    end
  end, true);

  addHotkey("Toggle Auto Layout", function (playerColor, object, pointerPosition, isKeyUp)
    if (isKeyUp) then
      playerStuff[playerColor].bAutoLayout = not playerStuff[playerColor].bAutoLayout
      if (playerStuff[playerColor].bAutoLayout) then
        Player[playerColor].print("Auto Layout On")
      else
        Player[playerColor].print("Auto Layout Off")
      end
    end
  end, true)

  addHotkey("Mask Movements", function(playerColor, object, pointerPosition, isKeyUp)
      local action = isKeyUp and "released" or "pressed"
      playerStuff[playerColor].bMaskActions = not isKeyUp
      if (playerStuff[playerColor].bMaskActions) then
        print(playerColor .. " " .. action .. " the hotkey... Masking Actions")
      else
        print(playerColor .. " " .. action .. " the hotkey... Not Masking Actions")
      end
      setButtons()
  end, true)

--  refreshScoresheet()
  --initializeGame()
  Wait.time(function () startLuaCoroutine(self, 'hoverTroll') end, 1,-1)
  -- Wait.time(function () startLuaCoroutine(self, 'checkNotes') end, 5,-1)
  Wait.time(function () setPlayers() end, 1)

  -- autodeal
  --click_NewGameSure(_, "White")
end

-- =============================================================================
function fixBooks()
  debug("Fix Books", "fixbooks")
  for sColor, oScoreZones in pairs(objScoreZones[giPlayerCount]["Colors"]) do
    debug("Starting Score " .. sColor,"score")
    if (sColor!="Hide" and Player[sColor].seated) then
      for _, oPlayZone in pairs(oScoreZones.zones) do
        for _, oObject in pairs(oPlayZone.obj.getObjects()) do
          if (oObject.tag=="Deck") then
            scoreTarget(oObject)
          end
        end
      end
    end
  end
end



-- =============================================================================
function moveRelative(vToMove, fDist, iDir, fYRot)
  if (iDir == gLEFT) then
    vToMove.x = vToMove.x - fDist*math.cos(math.rad(fYRot))
    vToMove.z = vToMove.z + fDist*math.sin(math.rad(fYRot))
  elseif (iDir == gRIGHT) then
    vToMove.x = vToMove.x + fDist*math.cos(math.rad(fYRot))
    vToMove.z = vToMove.z - fDist*math.sin(math.rad(fYRot))
  elseif (iDir == gUP) then
    vToMove.x = vToMove.x + fDist*math.sin(math.rad(fYRot))
    vToMove.z = vToMove.z + fDist*math.cos(math.rad(fYRot))
  elseif (iDir == gDOWN) then
    vToMove.x = vToMove.x - fDist*math.sin(math.rad(fYRot))
    vToMove.z = vToMove.z - fDist*math.cos(math.rad(fYRot))
  else
    log ("Error, dir not understood (" .. iDir .. ")")
  end
  return vToMove
end


-- =============================================================================
function finishFlag()
  log("flagging")
  gbFinishFlag = true
  local oSurface = getObjectFromGUID(UI_TABLETOP_SURFACE)
  local params = {
    name     = "FinishFlag2",
--    url      = "https://steamusercontent-a.akamaihd.net/ugc/1877457015605612653/49761BB03C0CFFB4A8DB96C806666BBB4A01AEEF/",
    --url      = "https://steamusercontent-a.akamaihd.net/ugc/1877457015605751193/879FF1D984080D65C9AA792BBC1F978D916E085A/",
    url      = "https://steamusercontent-a.akamaihd.net/ugc/1743476829258119278/0155E19E26C55460DBCBDC3389717EEF77444FC2/",
    position = {0,10.49,0.05},
    rotation = {90,0,0},
    scale    = {5.25,4.2,1},
  }
  oSurface.addDecal(params)
end

-- =============================================================================
function setCardDecal()
  -- Alpha Heart = "https://steamusercontent-a.akamaihd.net/ugc/1884211780465986822/C3A1927763B19AC38548F92D468B71FB204204E3/"
  -- Alpha Spade = "https://steamusercontent-a.akamaihd.net/ugc/1884211780465989269/6576A4C7F11E788B4CA053CE3E66CB12C8CFFA19/"
  -- Alpha Wild  = "https://steamusercontent-a.akamaihd.net/ugc/1877457015608030809/CA5D7ED15CCEE79E6A3F3FFC81D72B8210817308/",
   local sHeartCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265839918/4ABBBBC09C2E8DEF5E2811200185DBDFCA61FB81/"
   local sSpadeCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265841452/823AF2F0A4B76D72A10C72B2522D8702CFFFB864/"
   local sWildCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265844883/5530CC0F3061DADB729A495442E7F739C2213731/"

  -- local sHeartCard = "HeartCard"
  -- local sSpadeCard = "SpadeCard"
  -- local sWildCard = "WildCard"

  local fSpreadBetweenCards = .75
  local fScoreGapBetweenCards = .3
  local fCardHeight=1.48
  local fRelativeShrinkageFactor = 0.5
--  local fVertOffset = .4/fRelativeShrinkageFactor/10 --0.2
  local fVertOffset = .2
  --fSpreadBetweenCards = fRelativeShrinkageFactor/1.3
--  local vDecalScale = {x=.8,y=1,z=1}
  local vDecalScale = {x=1,y=1,z=1}

   vDecalScale = {vDecalScale.x*fRelativeShrinkageFactor,
                 vDecalScale.y*fRelativeShrinkageFactor,
                 vDecalScale.z*fRelativeShrinkageFactor, }

  local oSurface = getObjectFromGUID(UI_TABLETOP_SURFACE)
  local vSurScale = oSurface.getScale()
  -- Clear all decals
  oSurface.setDecals({})

  if not aCardIcons then
    aCardIcons = {}
  end

  log("destr-s")
  for i, o in ipairs(aCardIcons) do
    log("destr")
    o.destruct()
  end
  aCardIcons = {}
  log("destr-e")

  if gbFinishFlag then
    finishFlag()
  end


  local _, tBookCount = countScoreInternal()
  local lplayerList = getSeatedPlayers()
  for i,sColor in ipairs(lplayerList) do
    debug("doing " .. sColor, "decal")
    local vCenter = obj_scoretext[sColor].getPosition()-oSurface.getPosition()
    debug("scorepos = " .. dump(obj_scoretext[sColor].getPosition()),"decal" )
    debug("surface  = " .. dump(oSurface.getPosition()),"decal" )
    debug("vCenter  = " .. dump(vCenter),"decal")

    local vRot = obj_Zone[sColor].getRotation()
    --vRot.x = 90
    --vRot.y = vRot.y + 180
    local vNewPos = shallowCopy(vCenter);
    vNewPos = moveRelative(vNewPos, fScoreGapBetweenCards, gLEFT, nearestRightAngle(vRot.y) )
    vNewPos = moveRelative(vNewPos, fVertOffset, gUP, nearestRightAngle(vRot.y) )

    for i=1,tBookCount[sColor][gi_RED_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gLEFT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      local object = spawnObject({
        type = "Custom_Tile",
        position = vNewPos,
        rotation = vRot,
        scale = vDecalScale,
        sound = false
      })
      local param = {
        image = sHeartCard,
        thickness = 0.05,
        stackable = false,
      }
      object.setCustomObject(param)
      object.setColorTint({0,0,0,1})
      object.locked = true
      object.addTag("CardIcon")
      table.insert(aCardIcons,object)
    end
    vNewPos = shallowCopy(vCenter);
    vNewPos = moveRelative(vNewPos, fScoreGapBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
    vNewPos = moveRelative(vNewPos, fVertOffset, gUP, nearestRightAngle(vRot.y) )
    for i=1,tBookCount[sColor][gi_BLACK_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      local object = spawnObject({
        type = "Custom_Tile",
        position = vNewPos,
        rotation = vRot,
        scale = vDecalScale,
        sound = false
      })
      local param = {
        image = sSpadeCard,
        thickness = 0.05,
        stackable = false,
      }
      object.setCustomObject(param)
      object.setColorTint({0,0,0,1})
      object.locked = true
      object.addTag("CardIcon")
      table.insert(aCardIcons,object)
    end

    vNewPos = moveRelative(vNewPos, fSpreadBetweenCards*.5, gRIGHT, nearestRightAngle(vRot.y) )
    for i=1,tBookCount[sColor][gi_WILD_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      debug("Putting Wild at " .. dump(vNewPos) .. " scale:".. dump(vDecalScale) .. " for " .. sColor,"decal");
      local object = spawnObject({
        type = "Custom_Tile",
        position = vNewPos,
        rotation = vRot,
        scale = vDecalScale,
        sound = false
      })
      local param = {
        image = sWildCard,
        thickness = 0.05,
        stackable = false,
      }
      object.setCustomObject(param)
      object.setColorTint({0,0,0,1})
      object.locked = true
      object.addTag("CardIcon")
      table.insert(aCardIcons,object)
    end
  end
end
-- =============================================================================
function setCardDecal1()
  -- Alpha Heart = "https://steamusercontent-a.akamaihd.net/ugc/1884211780465986822/C3A1927763B19AC38548F92D468B71FB204204E3/"
  -- Alpha Spade = "https://steamusercontent-a.akamaihd.net/ugc/1884211780465989269/6576A4C7F11E788B4CA053CE3E66CB12C8CFFA19/"
  -- Alpha Wild  = "https://steamusercontent-a.akamaihd.net/ugc/1877457015608030809/CA5D7ED15CCEE79E6A3F3FFC81D72B8210817308/",
   local sHeartCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265839918/4ABBBBC09C2E8DEF5E2811200185DBDFCA61FB81/"
   local sSpadeCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265841452/823AF2F0A4B76D72A10C72B2522D8702CFFFB864/"
   local sWildCard = "https://steamusercontent-a.akamaihd.net/ugc/1743476829265844883/5530CC0F3061DADB729A495442E7F739C2213731/"

  -- local sHeartCard = "HeartCard"
  -- local sSpadeCard = "SpadeCard"
  -- local sWildCard = "WildCard"

  local fSpreadBetweenCards = .25
  local fScoreGapBetweenCards = .3
  local fCardHeight=10.75
  local fRelativeShrinkageFactor = 0.45
  local fVertOffset = .6/fRelativeShrinkageFactor/10 --0.2
  fSpreadBetweenCards = fRelativeShrinkageFactor/1.3
  local vDecalScale = {x=.8,y=1,z=1}
--  local vDecalScale = {x=1,y=1,z=1}

   vDecalScale = {vDecalScale.x*fRelativeShrinkageFactor,
                 vDecalScale.y*fRelativeShrinkageFactor,
                 vDecalScale.z*fRelativeShrinkageFactor, }

  local oSurface = getObjectFromGUID(UI_TABLETOP_SURFACE)
  local vSurScale = oSurface.getScale()
  -- Clear all decals
  oSurface.setDecals({})

  if gbFinishFlag then
    finishFlag()
  end


  local _, tBookCount = countScoreInternal()
  local lplayerList = getSeatedPlayers()
  for i,sColor in ipairs(lplayerList) do
    debug("doing " .. sColor, "decal")
    local vCenter = obj_scoretext[sColor].getPosition()-oSurface.getPosition()
    debug("scorepos = " .. dump(obj_scoretext[sColor].getPosition()),"decal" )
    debug("surface  = " .. dump(oSurface.getPosition()),"decal" )
    debug("vCenter  = " .. dump(vCenter),"decal")

    vCenter.x = vCenter.x / vSurScale.x
    vCenter.z = vCenter.z / vSurScale.z
    local vRot = obj_Zone[sColor].getRotation()
    vRot.x = 90
    vRot.y = vRot.y + 180
    local vNewPos = shallowCopy(vCenter);
    vNewPos = moveRelative(vNewPos, fScoreGapBetweenCards, gLEFT, nearestRightAngle(vRot.y) )
    vNewPos = moveRelative(vNewPos, fVertOffset, gDOWN, nearestRightAngle(vRot.y) )

    for i=1,tBookCount[sColor][gi_RED_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gLEFT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      debug("Putting Heart at " .. dump(vNewPos) .. " for " .. sColor,"decal");
      local params = {
        name     = "HeartCard",
        url      = sHeartCard,
        position = vNewPos,
        rotation = vRot,
        scale    = vDecalScale,
      }
      oSurface.addDecal(params)

    end
    vNewPos = shallowCopy(vCenter);
    vNewPos = moveRelative(vNewPos, fScoreGapBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
    vNewPos = moveRelative(vNewPos, fVertOffset, gDOWN, nearestRightAngle(vRot.y) )
    for i=1,tBookCount[sColor][gi_BLACK_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      debug("Putting Spade at " .. dump(vNewPos) .. " scale:".. dump(vDecalScale) .. " for " .. sColor,"decal");
      local params = {
        name     = "SpadeCard",
        url      = sSpadeCard,
        position = vNewPos,
        rotation = vRot,
        scale    = vDecalScale,
      }
      oSurface.addDecal(params)
    end
    vNewPos = moveRelative(vNewPos, fSpreadBetweenCards*.5, gRIGHT, nearestRightAngle(vRot.y) )
    for i=1,tBookCount[sColor][gi_WILD_BOOK_SCORE] do
      vNewPos = moveRelative(vNewPos, fSpreadBetweenCards, gRIGHT, nearestRightAngle(vRot.y) )
      vNewPos.y = fCardHeight
      debug("Putting Wild at " .. dump(vNewPos) .. " scale:".. dump(vDecalScale) .. " for " .. sColor,"decal");
      local params = {
        name     = "WildCard2",
--        url      = "https://steamusercontent-a.akamaihd.net/ugc/1877457015608170745/6DBE94CFF96CCA92FFCD2AD6F7F0409A85DA1347/",
        url      = sWildCard,
        position = vNewPos,
        rotation = vRot,
        scale    = vDecalScale,
      }
      oSurface.addDecal(params)
    end
  end
end
-- =============================================================================
function admin_sinkWalls()
  for i, oWallProps in pairs(objScoreZones[2]["Walls"]) do
    local p = objWalls[i].getPosition()
    objWalls[i].setPosition({p.x, -5, p.z})
  end
  for sColor, oColors in pairs(objScoreZones[2]["Colors"]) do
    for iZone, oZone in pairs(oColors.zones) do
      local p = oZone.obj.getPosition()
      oZone.obj.setPosition({p.x, -5, p.z})
    end
  end
  obj_Zone_Discard.setPosition({tDiscardProps.position.x,-10, tDiscardProps.position.z })


end


function layoutScoreZones(iPlayers)
  debug("laying out for " .. iPlayers,"weird")
  obj_Zone_Discard.setPosition(tDiscardProps.position)
  obj_Zone_Discard.setRotation(tDiscardProps.rotation)
  obj_Zone_Discard.setScale(tDiscardProps.scale)
  if (objScoreZones[iPlayers]) then
    if (iPlayers != giCurNumPlayersOnFelt) then
      objTable.call("updateSurfaceByURL","seconddb.com/GreenFeltFullSquare"..iPlayers.."pv2.png")
      giCurNumPlayersOnFelt = iPlayers
    end
    for sColor, oColors in pairs(objScoreZones[iPlayers]["Colors"]) do
      for iZone, oZone in pairs(oColors.zones) do
        oZone.obj.setPosition(oZone.pos)
        oZone.obj.setScale(oZone.scl)
      end
    end
    for i, oWallProps in pairs(objScoreZones[iPlayers]["Walls"]) do
      objWalls[i].setScale(oWallProps.scl)
      objWalls[i].setPosition(oWallProps.pos)
      objWalls[i].setPositionSmooth(oWallProps.pos,false)
      local tint = objWalls[i].getColorTint()
      tint.a = 0
      objWalls[i].setColorTint(tint)
    end
    debug("laying out setbuttons","weird")
    setButtons()
  else
    log("Not enough players yet (or too many)")
  end
end


function countScore()
  if (bRunScoring) then
    local scores = countScoreInternal()
    for sColor, iScore in pairs(scores) do
      obj_scoretext[sColor].TextTool.setValue("" .. iScore)
    end
  end
  if (bRunScoring) then
    Wait.time(function () startLuaCoroutine(self, 'countScore') end, 5)
  end
  return 1
end

function countScoreInternal()
  local doneGUIDs = {}
  local scores = {}
  local tBookCount = {["White"]={[gi_BLACK_BOOK_SCORE]=0, [gi_RED_BOOK_SCORE]=0, [gi_WILD_BOOK_SCORE]=0},
                      ["Green"]={[gi_BLACK_BOOK_SCORE]=0, [gi_RED_BOOK_SCORE]=0, [gi_WILD_BOOK_SCORE]=0},
                      ["Blue"] ={[gi_BLACK_BOOK_SCORE]=0, [gi_RED_BOOK_SCORE]=0, [gi_WILD_BOOK_SCORE]=0},
                      ["Red"]  ={[gi_BLACK_BOOK_SCORE]=0, [gi_RED_BOOK_SCORE]=0, [gi_WILD_BOOK_SCORE]=0},
                    }
--  objScoreZones={
      -- Create 3P layout
--      [2]= {
--        ["White"] = {
--          [1] = {
--            ["obj"] = objAllScoreZones[1],
--            ["scl"] ={70.0, 5.0,30.3,},


  for sColor, scoreZones in pairs(objScoreZones[giPlayerCount]["Colors"]) do
    debug("Starting Score " .. sColor,"score")
    if (sColor!="Hide" and Player[sColor].seated) then
      local iScore = 0

      -- First, get the score from the hand and negative-it
      if (obj_Zone[sColor]) then
        for _, occupyingObject in ipairs(obj_Zone[sColor].getObjects()) do
            local rawScore = 0
            local bookScore = 0
            debug("Scoring " .. occupyingObject.tag ,"score")
            rawScore, dckDesc, bookScore = scoreTarget(occupyingObject)
  --          debug("scored as " .. rawScore .. ", " .. bookScore, "score")
            if (rawScore) then
              iScore = iScore - rawScore
            end
            if (bookScore) then
              iScore = iScore - bookScore
            end
        end
      end

      -- if Nothing is in their hand, they've gone out, so add 500 and
      -- make it pretty yellow
      if iScore==0 then
        iScore = 500
        obj_scoretext[sColor].TextTool.setFontColor("Yellow")
      else
        obj_scoretext[sColor].TextTool.setFontColor("Grey")
      end

      for j=1,#scoreZones.zones do
        debug("Starting Score " .. sColor .. ", " .. j,"score")
        for _, occupyingObject in ipairs(scoreZones.zones[j].obj.getObjects()) do
            if (tablefind(doneGUIDs, occupyingObject.guid)==-1) then
              local rawScore = 0
              local bookScore = 0
              debug("Scoring " .. occupyingObject.tag ,"score")
              rawScore, dckDesc, bookScore = scoreTarget(occupyingObject)
    --          debug("scored as " .. rawScore .. ", " .. bookScore, "score")
              if (rawScore) then
                iScore = iScore + rawScore
              end
              if (bookScore) then
                if (bookScore!=0) then
                  tBookCount[sColor][bookScore]=tBookCount[sColor][bookScore]+1
                end
                iScore = iScore + bookScore
              end
              tablepush(doneGUIDs,occupyingObject.guid)
            end
        end
      end
      --announceAll("score " .. sColor .. " = " .. iScore)
      scores[sColor] = iScore
      debug("score " .. sColor .. " = " .. iScore, "score")
    end
  end
  return scores, tBookCount
end

function whoIsFirst()
  local doneGUIDs = {}
  local bottomCards = {}
  local candidatePlayers = {}
  local iCardIndex = 0 -- if we have to do more than one test, this is the modifier to get the second to last, thrid to last...

  -- get the candidate players
  -- we need this b/c we may end up looping
  -- if there's a tie
  playerList = getSortedSeatedPlayers()
  for iP, playerColor in ipairs(playerList) do
    tablepush(candidatePlayers,playerColor)
  end

  debug("===================================","first" )
  debug("checking first","first" )
  repeat
    bottomCards = {}
    doneGUIDs = {}
    -- Find the scorezones that exist.. loop through them
    for sColor, scoreZones in pairs(objScoreZones[giPlayerCount]["Colors"]) do
      debug("... checking " .. sColor,"first")
      -- Make sure someone is still a candidate, otherwise, ignore
      if (tablefind(candidatePlayers,sColor)!=-1) then
        debug("... found " .. sColor .. " in candidates","first")
        -- go through each of this color's scorezones
        for j=1,#scoreZones.zones do
          -- find all the things in the zone
          for _, occupyingObject in ipairs(scoreZones.zones[j].obj.getObjects()) do
            -- make sure we haven't looked at this one before (in case it's strattling)
            if (tablefind(doneGUIDs, occupyingObject.guid)==-1) then
              --debug("... found a " .. occupyingObject.tag ,"first")
              if (occupyingObject.tag == "Deck") then
                contents = occupyingObject.getObjects()
                if (contents) then
                  if (bottomCards[sColor]) then
                    broadcastToAll(sColor .. " seems to have multiple decks.  Can't determine who goes first.")
                    return "None"
                  end
                  --debug("In Contents...","first")
                  --debug("contents = " .. #contents,"first")
                  --debug(contents,"first")
                  _, shortName, shortSuit = cardDeets(contents[#contents-iCardIndex])
                  --debug("... kicker= " .. shortName .. " " .. shortSuit,"first")
                  bottomCards[sColor]=shortName
                end
                tablepush(doneGUIDs,occupyingObject.guid)
              end
            end
          end
        end
        if (not bottomCards[sColor]) then
          broadcastToAll(sColor .. " seems to not have a foot deck.  Can't determine who goes first.")
          return "None"
        end
      end
    end

    -- we have a table of bottomCards.. so lets go through them and find the highest
    setSortOrder(true,true)
    debug("bottomcards = ...","first")
    debug(bottomCards, "first")
    local sTopCard = ""
    candidatePlayers = {}
    for sBCColor, sCardName in pairs(bottomCards) do
      broadcastToAll(coolName(sBCColor) .. " has a " .. sCardName)
      if ( (sTopCard=="") or (refCardOrderIndex[sCardName] > refCardOrderIndex[sTopCard]) ) then
        sTopCard = sCardName
        candidatePlayers = {}
        tablepush(candidatePlayers,sBCColor)
      end
      if ( ( sTopCard != "") and (refCardOrderIndex[sCardName] == refCardOrderIndex[sTopCard]) ) then
        tablepush(candidatePlayers,sBCColor)
      end
      --debug("testing " .. sCardName .. " for " .. sBCColor,"first")
    end
    debug("candidates = ...", "first")
    debug(candidatePlayers, "first")
    iCardIndex = iCardIndex + 1
    debug("iCardIndex = " .. iCardIndex,"first")
    if (#candidatePlayers>1) then
      broadcastToAll("There was a tie.. checking the next card down.")
    end
  until (#candidatePlayers==1 or iCardIndex>12)

--  broadcastToAll(coolName(candidatePlayers[1]) .. " goes first!")
  debug("First is " .. candidatePlayers[1],"first")
  --gsGoesFirstColor = candidatePlayers[1]
  gsFirstToGoFirstColor = candidatePlayers[1]
  --refreshScoresheet()
  return candidatePlayers[1]
end




function coWait(secs)
  function e_coroutine()
    myWait(secs) -- delay
    return 1
  end
  startLuaCoroutine(self, "example_coroutine")
end

function myWait(frames)
  frames = frames * 60
  while frames > 0 do
      coroutine.yield(0)
      frames = frames - 1
  end
end


function calcFormula(s)
  local sign = 1
  local total = 0
  local iPos = 1
  while 1==1 do
    if string.sub(s,iPos,iPos)=="-" then
      sign = -1
      iPos = iPos +1
    elseif string.sub(s,iPos,iPos)=="+" then
      sign = 1
      iPos = iPos+1
    end
    sNum = string.match(s,"[%d]+", iPos)
    if not sNum then
      break
    end
    total = total + tonumber(sNum)*sign
    iPos = iPos + string.len(sNum)
  end
  return total
end

-- function click_Score()
--   local sOut = ""
--   if (bScoreShowing) then
--     sOut = " "
--   else
--     debug("Scoring.....")
--     --tableDump(tablePlayerCards)
--     --tableDump(tablePlayerDecks)
--     debug("....Scoring.....")
--     for k, playersCards in pairs(tablePlayerCards) do
--       local score = 0
--       for i, card in ipairs(playersCards) do
--         if card.in_hand then
--           score = score - card.score
--         else
--           score = score + card.score
--         end
--       end
--       for i, card in ipairs(tablePlayerDecks[k]) do
--         score = score + card.score
--       end
--       local name = k
--       if (Player[k].steam_name) then
--         name = Player[k].steam_name
--       end
--       if (Player[k].seated) then
--         sOut = sOut .. name .. ": " .. score .. "\n"
--       end
--     end
--   end
--   textScore.TextTool.setValue(sOut)
--   bScoreShowing = not bScoreShowing
-- end


function checkNotes()
  local didOne = false
  local note = Notes.getNotes()
  --  note = "adfadsf +100 + 20 - 3 = ## asdfads  1+    40 - 1 =##"
  --debug("read: " .. note)
  if ( string.match(note, "##") ) then
    newNote = ""
    for line in note:gmatch("([^\n]*\n?)") do
      newNote = newNote .. CalcNoteLine(line)
    end
    Notes.setNotes(newNote)
  end
  --  func = assert(load("return " .. formula))
  --  score= func()
  --  debug("score: " .. score)

  --  local i = string.match(note, "/# *[%d]* */# *= *[/-/+ %d]*")
  return 1
end

function CalcNoteLineOrig(line)
  note = line
  local i = string.match(note, "[-/+%d ]* *= *##")
  if i then
    didOne = true
    debug("i = " .. i)
    debug("gsub1 = " .. string.gsub(i,"( *[-/+%d ]*) *=##","%1" ))
    local formula = string.gsub(string.gsub(i,"( *[-/+%d ]*) *=##","%1" ),"%s+","")
--    local formula = string.gsub(string.gsub(i,"( *[-/+%d ]*) *=# *[%d]* *#","%1" ),"%s+","")
    debug("formula: " .. formula)

    score = calcFormula(formula)
    --completedFormula = string.gsub(i,"([-/+%d ]* *= *)##","%1"..score.."%2" )
    completedFormula = string.gsub(i,"([-/+%d ]* *= *)# *[%d]*( *)#","%1"..score.."%2" )
    --    debug("RESULT = ".. completedFormula)
  iStart, iEnd = string.find(note, "[-/+%d ]* *= *# *%d* *#")
    debug("start    = " .. string.sub(note,1,iStart) )
    debug("compform = " .. completedFormula)
    debug("end      = " .. string.sub(note,iEnd+1))
--    note = note .. "\n" .. completedFormula
    found1 = string.match(note,"(.*=[- %d]*).-=.-")
    found2 = string.match(note,".*=([- %d]*.-=.*)")
    if (found1 and found2) then
      debug("found1= ^" .. found1 .. "^")
      debug("found1= ^" .. found2 .. "^")
      note = found1 .. "\n" .. string.gsub(found2,"##",score)
    else
      note = string.gsub(note,"##",score)
  end

    --    note = string.sub(note,1,iStart) .. "\n" .. completedFormula .. string.sub(note,iEnd+1)
    --    debug("Note: " .. note)
--    i = string.match(note, "[-/+%d ]* *= *# *[%d]* *#")
  end
  return note
end

function CalcNoteLine(line)
  note = line

  --log("note = " .. note)
  local iSolveHere, _ = string.find(note, "##")
  if (iSolveHere) then
    --log ("iSolveHere = " .. iSolveHere)
    local iPos = iSolveHere-1
    local iEndPos = iPos

    -- work back to the equal sign to get the end of the formula
    while iPos > 0 do
      if (string.match(string.sub(note,iPos,iPos),"=") ) then
        --log("Checking char for = " .. iPos .. " : '" .. string.sub(note,iPos,iPos) .. "''" )
        iEndPos = iPos - 1
        break
      end
      iPos = iPos - 1
    end

    -- work back to the non num,+,-, or space to get the start of the formula
    local sLastNonFormulaChar = ""
    iPos=iEndPos-1
    while iPos > 0 do
      --log("Checking char for +-d " .. iPos .. " : '" .. string.sub(note,iPos,iPos).. "''" )
      if (not string.match(string.sub(note,iPos,iPos),"[ %+%-%d]") ) then
        sLastNonFormulaChar = string.sub(note,iPos,iPos)
        iPos = iPos + 1
        break
      end
      iPos = iPos - 1
    end
    local iStartPos = iPos

    --log("StartPos = "..iStartPos)
    --log("EndPos   = "..iEndPos)
    local formula = string.sub(note,iStartPos, iEndPos)
    formula = string.gsub(formula," ","")
    --log ("formula = " .. formula)
    score = calcFormula(formula)
    if sLastNonFormulaChar == "=" then

      -- work forward from startpos to the non num non space to get the last sum
      iPos=iStartPos
      local bHitDig = false
      while iPos < #note do
        --log("Checking char for +-d " .. iPos .. " : '" .. string.sub(note,iPos,iPos).. "''" )
        local char = string.sub(note,iPos,iPos)
        if ((char=="-" and not bHitDig) or (char=="+" and not bHitDig) or (char==" ")) then
          iPos = iPos + 1
        elseif (string.match(char,"%d")) then
          bHitDig=true
          iPos = iPos +1
        else
          iPos = iPos -1
          break
        end
      end

      local sLastSub = string.sub(note,iStartPos,iPos)

      note =  string.sub(note,1,iPos) .. "\n\r" .. string.gsub(formula,"([%+%-])"," %1 ") .. " = " .. score .. string.sub(note,iSolveHere+2,#note)
    else
      note =  string.sub(note,1,iSolveHere-1) .. score .. string.sub(note,iSolveHere+2,#note)
    end
  end
  return note
end




function shallowCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
--function findByName()
--  debug("[b]---Find By Name---[/b]")
--  local allObjects = getAllObjects()
--  for _, object in ipairs(allObjects) do
--    debug("got: " .. object.name)
--    debug("getName(): " .. object.getName())
--    debug("getName(): " .. object.getName())
--    debug("typeof(): " .. typeof(object))
--  end

--end

function findProximity(targetPos, object)
    local objectPos = object.getPosition()
    local xDistance = math.abs(targetPos.x - objectPos.x)
    local zDistance = math.abs(targetPos.z - objectPos.z)
    local distance = xDistance^2 + zDistance^2
    return distance  -- return math.sqrt(distance) for actual distance
end


--==============================================================================
function cardDeets(oneCard)
  local shortSuit
  local shortName
  if type(oneCard) == 'table' then
    shortSuit = string.match(oneCard.description,"[%a%d]*$")
    shortName = string.match(oneCard.description,"[%a%d]*")
  else
    shortSuit = string.match(oneCard.getDescription(),"[%a%d]*$")
    shortName = string.match(oneCard.getDescription(),"[%a%d]*")
  end
  if (shortName == '2' or shortName == 'Joker') then
    return "Wild", shortName, shortSuit
  elseif (shortSuit == 'Clubs' or shortSuit == 'Spades') then
    return "Black", shortName, shortSuit
  else
    return "Red", shortName, shortSuit
  end
end

--==============================================================================
-- Game Rules helpers
-- Pure functions with no TTS calls.  These encode what is and isn't legal.

-- True for wildcard ranks (2 or Joker).
function isWild(rank)
  return rank == "2" or rank == "Joker"
end

-- True for ranks that can form melds (not wilds, not 3s).
function isEligibleRank(rank)
  return rank ~= "2" and rank ~= "3" and rank ~= "Joker"
end

-- True if cards[] could form a valid opening meld (3+ total, 2+ non-wild).
-- cards[] is a list of {rank, suit, color} or {rank, color} entries.
function canFormMeld(cards)
  if #cards < 3 then return false end
  local nonWild = 0
  for _, c in ipairs(cards) do
    if c.color ~= "Wild" then nonWild = nonWild + 1 end
  end
  return nonWild >= 2
end

--==============================================================================
function tablepush(tab, el)
  debug("table push " .. dump(el), "discard")
  local i = tablefind(tab, el)
  if i==-1  then
    table.insert(tab, el)
  end
end

function tablepop(tab, el)
  local i = tablefind(tab, el)
  if (i>-1) then
    table.remove(tab,i)
    debug("table pop-t " .. dump(el), "discard")
    return true
  end
  debug("table pop-f " .. dump(el), "discard")
return false
end


function tablefind(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
  return -1
end



function rnd(x) return math.floor(100*(x+0.005))/100 end


function notNill(thing)
  if thing then
    return "True"
  else
    return "False"
  end
end

function nearestRightAngle(fSourceRotY)
  local fY = 90*( math.floor((fSourceRotY+45)/90))
  fY = (fY)%360
  return fY
end
-- =============================================================================
function changeRelativePosition(vOrigPos, vRot, bLeftRight)
  local vNewPos = vOrigPos
  debug("vOrigPos =       " .. dump(vOrigPos), "spread")
  if (not bLeftRight) then
    vNewPos.x = vNewPos.x + gfSpreadMult*math.sin(math.rad(vRot.y))
    vNewPos.z = vNewPos.z + gfSpreadMult*math.cos(math.rad(vRot.y))
  else -- this is the norm.. fwd/bkwd
    vNewPos.x = vNewPos.x + gfSpreadMult*math.cos(math.rad(vRot.y))
    vNewPos.z = vNewPos.z + gfSpreadMult*math.sin(math.rad(vRot.y))
  end
  debug("new pos = " .. dump(vNewPos), "spread")
  return vNewPos
end
-- =============================================================================
function getPlayerRotationFromObject(oObj)
  local vRot = oObj.getRotation()
  vRot.x = 0
  vRot.z = 0
  local sSelInZoneColor=getOwnerOfObject(oObj)
  if (not sSelInZoneColor) then
    log ("ERROR: Trying to get rotation for owner of " .. oObj.tag .. " " .. oObj.getDescription() .. " returned nil")
    return vRot, sSelInZoneColor
  end
  debug("Sampled card belongs to " .. nvl(sSelInZoneColor), "playerrot")
  -- Now let's just be sure that we're exactly on a right angle
  -- rotation, in case the hand zone is sligthly off.
  -- let's add 45 degrees and divide it by 90
  --  so 0deg = floor(45/90) = 0... times 90 = 0
  --  so 89.9 deg = floor((89.9+45)/90) = 1.. times 90 = 90
  --  so 185 deg = floor((185+45)/90) = 2.. times 90 = 180
  --  so 270 deg = floor((270+45)/90) = 3.. times 90 = 270
  --  so 360 deg = floor((360+45)/90) = 4.. times 90 = 360
  -- Then we mod360 it, just in case it came in at 450 somehow (not possible, I expect)
  local rotPlayerY = obj_Zone[sSelInZoneColor].getRotation().y
  vRot.y = 90*( math.floor((rotPlayerY+45)/90))
  vRot.y = (vRot.y)%360
  debug("... Their hand rot is = " .. obj_Zone[sSelInZoneColor].getRotation().y, "playerrot")
  debug("... Normalized to = " .. vRot.y, "playerrot")
  return vRot, sSelInZoneColor
end
-- =============================================================================
function getOwnerOfObject(oObj)
  -- given an object, find the first scorezone that it belongs to
  -- (it might belong to >1, but we're just gonna get the first)
  -- and return the color associated to that score zones
  -- returns nil if it is not found
  debug("Getting Owner of " .. oObj.getDescription(),"getowner")
  local sColor = nil
  for _, oSelZone in pairs(oObj.getZones()) do
    debug("Object is in zone " .. oSelZone.guid, "getowner" )
    for k, oScoreZone in pairs(getAllScoreZones()) do
      debug("checking against scorezone " .. oScoreZone.guid, "getowner" )
      if oSelZone.guid == oScoreZone.guid then
        debug("Hit!  color=" .. oScoreZone.color, "getowner" )
        return oScoreZone.color
      end
    end
  end
  return nil
end
-- =============================================================================
function spread4(player, desiredPos, tCards)
  if not playerStuff[player].bSpreading then
    playerStuff[player].bSpreading = true
    local spinMult = 0.75
    local dropHeight = 0.4
    local deckType = "Unknown"
    local lastShortName = ""
    local spinnableCards={Red = nil, Black = nil, Wild=nil}
    local cardCount = 0
    local cardDropped = false
    local logcnt = 0
    local takenCard = nil
    local rot90 = {}
    local playedCards = {}
    local cardType = nil
    local vTopDropSpot = nil
    local iNumWild = 0
    local tOrder = { Black={"Wild","Red","Black"},
                      Red={"Wild","Black","Red"},
                      Wild={"Red","Black","Wild"}
                    }

    local pos = {}
    local posLast = {}
    local posFirst = {}

    -- ---------------------------------------------------------------
    function advancePosition()
      debug("posLast =       " .. dump(posLast), "spread")
      pos = posLast
      pos = changeRelativePosition(pos, rot, false)
      pos.y = pos.y + dropHeight+#playedCards*0.02
      posLast = pos
      debug("new posLast =   " .. dump(posLast), "spread")
      debug("Advanced Pos to " .. dump(pos), "spread")
    end
    -- ---------------------------------------------------------------
    function processOneCard(item)
      cardCount = cardCount + 1
      shortColor, shortName, _ = cardDeets(item)
      if (shortColor=="Wild") then
        iNumWild=iNumWild+1
      end
      -- if the current card isn't wild, let's see about marking the
      -- spread with a specific cardtype
      if (shortColor != "Wild")  then
        if (not cardType) then
          cardType = shortName
        elseif cardType != "MIXED" and cardType != shortName then
          -- just in case.. if we don't already know it's a mixed set
          -- AND this card value doesn't match the spread's card type and
          -- it isn't a wild card, we have a mixed spread.  Let's
          -- dump out a warning and mark it as mixed.
          print ("Problem: " .. shortName .. " found in line of " .. cardType)
          cardType = "MIXED"
        end
      end

      -- if it's spinnable, then save it and don't mark it as having
      -- been dropped (since it's gonna get moved)
      if not spinnableCards[shortColor] then
        spinnableCards[shortColor]=item
        debug("setting spinnable3 " .. shortColor .. " / " .. item.getDescription(),"spread")
      else
        -- let's record that we're playing this card (as a core/non-spinnable card)
        table.insert(playedCards,item)

        item.setRotation(rot)
        if (cardDropped) then
          advancePosition()
        end
        debug("simple card positioning " .. item.getDescription() .. " at pos="..dump(pos),"spread")
        item.setPositionSmooth(pos,false,true)
        debug("setting " .. item.GetDescription() .. " at " .. dump(item.getPosition()),"layoutsel")
        cardDropped = true
      end
    end
    -- ---------------------------------------------------------------


    debug("Spreading--------------","spread")

    -- if it's CA rules, there can be a wild book.  But if not, then mark it as
    -- N/A. This will help reduce lots of if/then's later in this function
    -- if (giRuleSet==giCaliforniaRules) then
    --   spinnableCards["Wild"]="N/A"
    -- end

    -- get selected objects (or the cards sent in) and call it "the selection (sel)"
    if (not tCards) then
      debug("** Had to get player selection instead of tCards!!!","prob2")
      tCards = Player[player].getSelectedObjects()
    end

    -- If the selection contains a non-deck, non-card thing, just stop entirely
    -- otherwise we'll end up laying out the table or something
    for k, v in pairs(tCards) do
      if (v.tag!="Deck" and v.tag!="Card") then
        broadcastToColor("Trying to layout a selection containing a non-Deck/Card (".. v.tag.."). Let's not. It goes badly.",player);
        return
      end
    end
    -- if we have something to do...
    if (tCards and #tCards>0) then

      -- Sort the cards to find the one closest to the center of the table (0,0,0)
      table.sort(tCards, function(a,b) return findProximity({x=0,y=0,z=0},a) < findProximity({x=0,y=0,z=0},b) end)

      -- if, instead, we were told where to put it, let's use that.
      -- this really means the sort and posLast=getpos above were useless
      -- good programming says to avoid them as unnecessary.  I'm not
      -- a good programmer
      if (desiredPos) then
        posLast = desiredPos
      else
        -- take the position of the first card (nearest to table center) and make it
        -- the start of the stack by capturing its position\
        posLast = tCards[1].getPosition()
      end

      -- Figure out the rotation to use for most of the cards
      -- as a baseline, let's start with the rotation of the first
      -- card in the set
--      rot = tCards[1].getRotation()

      -- Find out whose zone it's in.  Take the first selection as the
      -- deciding factor
      rot = getPlayerRotationFromObject(tCards[1])
      -- if (false) then
      --   local sSelInZoneColor=getOwnerOfObject(tCards[1])
      --   debug("Sampled card belongs to " .. nvl(sSelInZoneColor), "spread")
      --
      --   -- Now let's just be sure that we're exactly on a right angle
      --   -- rotation, in case the hand zone is sligthly off.
      --   -- let's add 45 degrees and divide it by 90
      --   --  so 0deg = floor(45/90) = 0... times 90 = 0
      --   --  so 89.9 deg = floor((89.9+45)/90) = 1.. times 90 = 90
      --   --  so 185 deg = floor((185+45)/90) = 2.. times 90 = 180
      --   --  so 270 deg = floor((270+45)/90) = 3.. times 90 = 270
      --   --  so 360 deg = floor((360+45)/90) = 4.. times 90 = 360
      --   -- Then we mod360 it, just in case it came in at 450 somehow (not possible, I expect)
      --   local rotPlayerY = obj_Zone[sSelInZoneColor].getRotation().y
      --   rot.y = 90*( math.floor((rotPlayerY+45)/90))
      --   rot.y = (rot.y)%360
      --   debug("... Their hand rot is = " .. obj_Zone[sSelInZoneColor].getRotation().y, "spread")
      --   debug("... Normalized to = " .. rot.y, "spread")
      -- end
      -- Got the new Rotation

      if (desiredPos) then
        -- debug("have desired pos.. shifting by fDropshift","spread")
        -- debug("orig posLast = "..dump(posLast),"spread")
        -- -- Now, figure out the new posLast/first based on the rotation and such
        -- -- only if the deisredPos was set.. meaning we're dropping at a pointer
        -- local vCardSize = tCards[1].getBoundsNormalized()
        -- local fDropshift = vCardSize.size.z/3
        -- local fDeltaX = gfDropShift*math.sin(math.rad(rot.y))
        -- local fDeltaZ = gfDropShift*math.cos(math.rad(rot.y))
        --
        -- posLast.x = posLast.x + fDeltaX
        -- posLast.z = posLast.z + fDeltaZ
        -- debug("new posLast = "..dump(posLast),"spread")
      end

      -- If we're going to auto-align, even though we have a target position
      -- stored in posLast, we need to modify it.
      -- call NearMe to return a new position after looking for other cards
      -- to the right and the left (determined by the rot)

      if (playerStuff[player].bAlign>0) then
        -- as bAlign is negative (false), 1 (high) or 3 (low)
        -- then subtract 2 making -1 high and 1 low.
        -- we lose "false" generally, but don't care now, we just checked
        posLast = nearMe(posLast, rot, tCards, playerStuff[player].bAlign-2, player)
      end

      -- We need to keep record of the top spot, even after we've moved
      -- on to other cards in the spread, so store it.  This is so we can
      -- return it
      if (not vTopDropSpot) then
        vTopDropSpot = shallowCopy(posLast)
        debug("spread-topdropspot = " .. dump(vTopDropSpot),"layoutsel")
      end


      -- We're going to alternate between a posLast and posFirst so, for now,
      -- set posFirst = posLast (shallow copy copies the data, not a reference
      -- to the object.  This is important because the variables will change
      -- independantly of each other
      posFirst = shallowCopy(posLast)
      pos = shallowCopy(posLast)

      -- to be careful, set rot x and z to zero.  we want the card flat
      -- relative to the table
      rot.x = 0
      rot.z = 0

      -- Now let's loop through all the items in the selection and start
      -- laying out what we can, saving one red, black, and wild off
      -- to the side to use at the end in case we need to turn a card
      for i, item in ipairs(tCards) do
        -- if it's a deck, we're gonna need to go through each contained
        -- card and handle it
        if (item.tag == "Deck") then
          local deckCards = shallowCopy(item.getObjects())
          for k, oneCard in pairs(deckCards) do
            if (item.getQuantity()==0) then
              takenCard = item.remainder
            else
              takenCard = item.takeObject({guid=oneCard.guid, position=pos, rotation=rot,smooth=false})
            end
            processOneCard(takenCard)
          end -- end loop through deck cards

        -- CARD INSTEAD
        else  -- It wasn't a deck, it was a single card..
          processOneCard(item)
        end
      end

      -- Now.. we have all the cards in the selection and they're all individuals
      -- plus all of them except for 3 possibles are laid out in the right spread
      -- All that's left is to figure out if we have 1-5, 6, or >0 cards so we can
      -- know what to do with the 3 "playedCards" (one red, one black and maybe one wild)

      -- if we never said it was a wild deck and never said it was a black deck
      -- then it isn't unknown anymore, it's red
      if (giRuleSet==giCaliforniaRules and iNumWild==cardCount) then
        deckType = "Wild"
        cardType = "Wild"
      elseif iNumWild==0 then
        deckType = "Red"
      else
        deckType = "Black"
      end

      debug("spinnable black = " .. notNill(spinnableCards["Black"]))
      debug("spinnable red   = " .. notNill(spinnableCards["Red"]))
      debug("spinnable wild  = " .. notNill(spinnableCards["Wild"]))
      debug("deck type       = " .. deckType)
      -- figure out what a 90deg rotation is for is and save it in rot90.y
      rot90 = shallowCopy(rot)
      rot90.y = rot90.y + 90

      -- if we have 6 cards and either it's an "almost book", meaning it has both a red and black card
      -- or it's a wild deck with a spinnable wild card... then we want to lay it out.
      if (cardCount==6 and (
                 ( deckType != "Wild" and spinnableCards["Red"] and spinnableCards["Black"])
              or (deckType == "Wild" and spinnableCards["Wild"]))) then

        for i, sOrder in ipairs(tOrder[deckType]) do
          if (spinnableCards[sOrder]) then
            spinnableCards[sOrder].setRotation(iif(i==3, rot90, rot))
            advancePosition()
            debug("spinnable positioning " .. spinnableCards[sOrder].getDescription() .. " at pos="..dump(pos),"spread")
            spinnableCards[sOrder].setPositionSmooth(pos,false,true)
          end
        end
      -- if it's >6, we should see if we can book them (all of them)
      -- it needs to not be a mixed set of cards (like.. some kings and some 4's)
      -- and it either must have a red and black card or be a wild book.
      elseif (cardType != "MIXED" and cardCount>6
              and ( (spinnableCards["Red"] and spinnableCards["Black"])
                    or (deckType == "Wild" and spinnableCards["Wild"])) ) then
          pos = shallowCopy(posFirst)
          pos.y = pos.y + 0.5
          for i=1,#playedCards do
            playedCards[i].setPositionSmooth(pos,false,true)
            playedCards[i].setRotation(rot90)
            pos.y = pos.y + .1
          end

          for i, sOrder in ipairs(tOrder[deckType]) do
            if (spinnableCards[sOrder]) then
              pos.y = pos.y + .1
              debug("spinnable positioning " .. spinnableCards[sOrder].getDescription() .. " at pos="..dump(pos),"spread")
              spinnableCards[sOrder].setPositionSmooth(pos,false,true)
              cardDropped = true
              spinnableCards[sOrder].setRotation(rot90)
            end
          end
          Wait.time( function() setCardDecal(); end, 1.0)
          -- Book complete: after cards have settled into a Deck, move it to zone 2/3.
          Wait.time( function() checkAndMoveBooks(player); end, 2.5)

      -- if we're neither near-bookable 6 cards or stackable 7+ cards, Then
      -- we just need to plunk all the spinnable cards down at the bottom
      -- of the spread
      else
        for i, sOrder in ipairs(tOrder["Black"]) do
          if (spinnableCards[sOrder]) then
            if (cardDropped) then
              advancePosition()
            end
            debug("spinnable positioning " .. spinnableCards[sOrder].getDescription() .. " at pos="..dump(pos),"spread")
            spinnableCards[sOrder].setPositionSmooth(pos,false,true)
            cardDropped = true
            spinnableCards[sOrder].setRotation(rot)
          end
        end
      end
--      Player[player].broadcast(#playedCards .. " cards")
      debug("cardtype, decktype, cardcount = " .. nvl(cardType) .. ", " .. nvl(deckType) .. ", " .. nvl(cardCount), "prob1")
    end
    debug("spread-topdropspot2 = " .. dump(vTopDropSpot),"layoutsel")
    playerStuff[player].bSpreading=false
    return vTopDropSpot
  else
    debug("Avoided a spread, we were already doing one","spread")
  end
  playerStuff[player].bSpreading=false
end

-- =============================================================================

function spread3(spread, player, rottype, desiredPos, tCards)
  return spread4(player, desiredPos, tCards)
end

-- =============================================================================
function spread3x(spread, player, rottype, desiredPos, tCards)
  if not playerStuff[player].bSpreading then
    playerStuff[player].bSpreading = true
    local spinMult = 0.75
    local dropHeight = 0.4
    local deckType = "Unknown"
    local lastShortName = ""
    local spinnableCards={Red = nil, Black = nil}
    local cardCount = 0
    local cardDropped = false
    local logcnt = 0
    local takenCard = nil
    local rot90 = {}
    local playedCards = {}
    local cardType = nil
    local vTopDropSpot = nil
    local iNumWild = 0

    debug("Spreading","prob1")

    -- get selected objects (or the cards sent in) and call it "the selection (sel)"
    local sel
    if (tCards) then
      sel = tCards
    else
      sel = Player[player].getSelectedObjects()
    end

    -- If the selection contains a non-deck, non-card thing, just stop entirely
    -- otherwise we'll end up laying out the table or something
    for k, v in pairs(sel) do
      if (v.tag!="Deck" and v.tag!="Card") then
        broadcastToColor("Trying to layout a selection containing a non-Deck/Card (".. v.tag.."). Let's not. It goes badly.",player);
        return
      end
    end

    -- if we have something to do...
    if (sel and #sel>0) then

      -- Sort the cards to find the one closest to the center of the table (0,0,0)
      table.sort(sel, function(a,b) return findProximity({x=0,y=0,z=0},a) < findProximity({x=0,y=0,z=0},b) end)

      -- take the position of the first card (nearest to table center) and make it
      -- the start of the stack by capturing its position\
      local posLast = sel[1].getPosition()

      -- if, instead, we were told where to put it, let's use that.
      -- this really means the sort and posLast=getpos above were useless
      -- good programming says to avoid them as unnecessary.  I'm not
      -- a good programmer
      if (desiredPos) then
        posLast = desiredPos
      end

      -- We're going to alternate between a posLast and posFirst so, for now,
      -- set posFirst = posLast (shallow copy copies the data, not a reference
      -- to the object.  This is important because the variables will change
      -- independantly of each other
      local posFirst = shallowCopy(posLast)

      -- Figure out the rotation to use for most of the cards
      -- as a baseline, let's start with the rotation of the first
      -- card in the set
      rot = sel[1].getRotation()
      local rotPlayerY=0
      -- If the parameter was set for rotating it toward a different player
      -- then find the player's hand zone, capture the rotation,
      -- and rotate it 180 degrees from there
      if (rottype == 1) then
        rotPlayerY = Player[player].getHandTransform().rotation.y
        rot.y = (rotPlayerY+180)%360
      else
        debug("rot.y = " .. rot.y,"spread")
        closestDist=-1
        closestColor=""
        for _, player in ipairs(Player.getPlayers()) do
  --        if (player.seated) then
            if obj_Zone[player.color] then
              prox = findProximity(obj_Zone[player.color].getPosition(), sel[1])
              if (prox<closestDist or closestDist==-1) then
                closestDist=prox
                closestColor=player.color
              end
            end
  --        end
        end
        if (closestDist==-1) then
          log('No player was closest?  none seated? This should never happen.')
        end
        debug("Closest is " .. closestColor)
        debug("zoneRot = " .. obj_Zone[closestColor].getRotation().y)
        rotPlayerY = obj_Zone[closestColor].getRotation().y
        rot.y = 90*( math.floor((rotPlayerY+45)/90))
        rot.y = (rot.y)%360
      end
      debug("new rot.y = " .. rot.y,"spread")
      -- Got the new Rotation

      if (desiredPos) then
        -- Now, figure out the new posLast/first based on the rotation and such
        -- only if the deisredPos was set.. meaning we're dropping at a pointer
        local vCardSize = sel[1].getBoundsNormalized()
        local fDropshift = vCardSize.size.z/3
        local fDeltaX = fDropshift*math.sin(math.rad(rot.y))
        local fDeltaZ = fDropshift*math.cos(math.rad(rot.y))

        posLast.x = posLast.x + fDeltaX
        posLast.z = posLast.z + fDeltaZ
      end
-- ABCD
      if (playerStuff[player].bAlign>0) then
        -- as bAlign is negative (false), 1 (high) or 3 (low)
        -- then subtract 2 making -1 high and 1 low.
        -- we lose "false" generally, but don't care now, we just checked
        posLast = nearMe(posLast, rot, sel,playerStuff[player].bAlign-2)
      end

      if (not vTopDropSpot) then
        vTopDropSpot = shallowCopy(posLast)
        debug("spread-topdropspot = " .. dump(vTopDropSpot),"layoutsel")
      end

      rot.x = 0
      rot.z = 0
      for i=1,#sel do
        local item=sel[i]

        if (item.tag == "Deck") then
          local deckCards = shallowCopy(item.getObjects())
          for k, oneCard in pairs(deckCards) do
            cardCount = cardCount + 1

            shortColor, shortName, _ = cardDeets(oneCard)
            if (shortColor=="Wild") then
              iNumWild=iNumWild+1
            end
            if (giRuleSet == giCaliforniaRules) then
              if (not cardType) then
                if (shortColor == "Wild") then
--                  cardType = shortColor
                else
                  cardType = shortName
                end
              elseif cardType != "MIXED" and cardType != shortName and shortColor != "Wild" then
                print ("Problem: " .. shortName .. " found in line of " .. cardType)
                cardType = "MIXED"
              end
            else
              if (shortColor != "Wild")  then
                if (not cardType) then
                  cardType = shortName
                elseif cardType != "MIXED" and cardType != shortName then
                  print ("Problem: " .. shortName .. " found in line of " .. cardType)
                  cardType = "MIXED"
                end
              end
            end

            -- Set the position for this card to be the same as the one before it
            pos = posLast
            -- if the LAST one was not spinnable and was dropped, then slide
            -- this one down a little bit to let the numbers show and set that as the
            -- position to be looked at next time around (posLast)
            if (not bSpinnable and cardDropped) then
              pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
              pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
              pos.y = pos.y + dropHeight
              posLast=pos
            end

            bSpinnable = false
            if (shortColor != "Wild" or giRuleSet == giCaliforniaRules) and spinnableCards[shortColor]==nil then
                bSpinnable=true
                pos.y = pos.y + 2
            end

            -- if this card is the last in a stack use remainder to get it
            -- and set its position
            -- if it's pulled from a stack, you have to use takeobject
            if (item.getQuantity()==0) then
              takenCard = item.remainder
              takenCard.setPositionSmooth(pos,false,true)
              takenCard.setRotation(rot)
            else
              takenCard = item.takeObject({guid=oneCard.guid, position=pos, rotation=rot,smooth=false})
            end

    --        log (" tc  ..." .. takenCard.getDescription())
            takenCard.addToPlayerSelection(player)
            takenCard.addToPlayerSelection(player)
            table.insert(playedCards,takenCard)


            if (shortColor=="Wild" and giRuleSet==giCaliforniaRules) then
            --  cardDropped = true
              if spinnableCards[shortColor]==nil then
                spinnableCards[shortColor]=takenCard
                debug("setting spinnable1 " .. shortColor)
              else
                cardDropped = true
              end
            elseif (shortColor == "Wild") then
              cardDropped = true
            else
              if spinnableCards[shortColor]==nil then
                spinnableCards[shortColor]=takenCard
                debug("setting spinnable2 " .. shortColor)
              else
                cardDropped = true
              end
            end
          end
        else  -- It wasn't a deck, it was a single card..
          cardCount = cardCount + 1
          table.insert(playedCards,sel[i])
          shortColor, shortName, _ = cardDeets(sel[i])
          if (shortColor=="Wild") then
            iNumWild=iNumWild+1
          end
          if (giRuleSet == giCaliforniaRules) then
            if (not cardType) then
              if (shortColor == "Wild") then
--                cardType = shortColor
              else
                cardType = shortName
              end
            elseif cardType != "MIXED" and cardType != shortName and shortColor != "Wild" then
              print ("Problem: " .. shortName .. " found in line of " .. cardType)
              cardType = "MIXED"
            end
          else
            if (shortColor != "Wild")  then
              if (not cardType) then
                cardType = shortName
              elseif cardType != "MIXED" and cardType != shortName then
                print ("Problem: " .. shortName .. " found in line of " .. cardType)
                cardType = "MIXED"
              end
            end
          end


          if ((shortColor == "Black" or shortColor=="Red" or (shortColor=="Wild" and giRuleSet==giCaliforniaRules)) and spinnableCards[shortColor]==nil) then
            spinnableCards[shortColor]=sel[i]
            debug("setting spinnable3 " .. shortColor)
          else


            sel[i].setRotation(rot)
            pos = posLast
            if (cardDropped) then
              pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
              pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
              pos.y = pos.y + dropHeight
            end
            posLast = pos
            sel[i].setPositionSmooth(pos,false,true)
            debug("setting " .. sel[i].GetDescription() .. " at " .. dump(sel[i].getPosition()),"layoutsel")
            cardDropped = true
          end
        end
      end
      -- if we never said it was a wild deck and never said it was a black deck
      -- then it isn't unknown anymore, it's red

      if (giRuleSet==giCaliforniaRules and iNumWild==#playedCards) then
        deckType = "Wild"
        cardType="Wild"
      elseif iNumWild==0 then
        deckType = "Red"
      else
        deckType = "Black"
      end

      debug("spinnable black = " .. notNill(spinnableCards["Black"]))
      debug("spinnable red   = " .. notNill(spinnableCards["Red"]))
      debug("spinnable wild  = " .. notNill(spinnableCards["Wild"]))
      debug("deck type       = " .. deckType)
      rot90 = shallowCopy(rot)
      rot90.y = rot90.y + 90
      if (cardCount==6 and (
                 ( deckType != "Wild" and spinnableCards["Red"] and spinnableCards["Black"])
              or (deckType == "Wild" and spinnableCards["Wild"]))) then

        if (deckType=="Black") then
          -- It's a black deck, so drop the spinnable Red first
          -- Then do the Black.
          spinnableCards["Red"].setRotation(rot)
          pos = posLast
          if (cardDropped) then
            pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
            pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
            pos.y = pos.y + dropHeight
          end
    --      log("Dropping spinnable Red" .. ' ('.. rnd(pos.x) .. ',' .. rnd(pos.y) .. ')')
          posLast = pos
          spinnableCards["Red"].setPositionSmooth(pos,false,true)
          cardDropped = true
          pos = posLast
          if (cardDropped) then
            pos.x = pos.x + spinMult*math.sin(math.rad(rot.y))
            pos.z = pos.z + spinMult*math.cos(math.rad(rot.y))
            pos.y = pos.y + dropHeight
          end
    --      log("spinning Black" .. ' ('.. rnd(pos.x) .. ',' .. rnd(pos.y) .. ')')
          posLast = pos
    --    If there was a wild stored as spinnable (in Cali rules, it would be), let's drop that one tooltip
          if ( spinnableCards["Wild"] ) then
            spinnableCards["Wild"].setRotation(rot)
            -- pos = posLast
            -- if (cardDropped) then
            --   pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
            --   pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
            --   pos.y = pos.y + dropHeight
            -- end
            --      log("Dropping spinnable Red" .. ' ('.. rnd(pos.x) .. ',' .. rnd(pos.y) .. ')')
            posLast = pos
            spinnableCards["Wild"].setPositionSmooth(pos,false,true)
            cardDropped = true
            pos = posLast
            if (cardDropped) then
              pos.x = pos.x + spinMult*math.sin(math.rad(rot.y))
              pos.z = pos.z + spinMult*math.cos(math.rad(rot.y))
              pos.y = pos.y + dropHeight
            end
            posLast = pos
          end
          spinnableCards["Black"].setPositionSmooth(pos,false,true)
          spinnableCards["Black"].setRotation(rot90)
          cardDropped = true
        elseif (deckType == "Red") then
          -- if it's a red deck, drop the black cards first, then black (there won't be any wilds)
          spinnableCards["Black"].setRotation(rot)
          pos = posLast
          if (cardDropped) then
            pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
            pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
            pos.y = pos.y + dropHeight
          end
    --      log("Dropping spinnable Black" .. ' ('.. pos.x .. ',' .. pos.y .. ')')
          posLast = pos
          spinnableCards["Black"].setPositionSmooth(pos,false,true)
          cardDropped = true
          spinnableCards["Red"].setRotation(rot)
          pos = posLast
          if (cardDropped) then
            pos.x = pos.x + spinMult*math.sin(math.rad(rot.y))
            pos.z = pos.z + spinMult*math.cos(math.rad(rot.y))
            pos.y = pos.y + dropHeight
          end
    --      log("spinning Red"  .. ' ('.. pos.x .. ',' .. pos.y .. ')')
          posLast = pos
          spinnableCards["Red"].setPositionSmooth(pos,false,true)
          spinnableCards["Red"].setRotation(rot90)
          cardDropped = true
        else -- Deck must be wild (not black, not red)
          -- thus there's no black or red cards to drop
          pos = posLast
          if (cardDropped) then
            pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
            pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
            pos.y = pos.y + dropHeight
          end
          posLast = pos
          spinnableCards["Wild"].setPositionSmooth(pos,false,true)
          spinnableCards["Wild"].setRotation(rot90)
          cardDropped = true

        end
      elseif (cardType != "MIXED" and cardCount>6 and ( (spinnableCards["Red"] and spinnableCards["Black"]) or (deckType == "Wild" and spinnableCards["Wild"])) )then
          pos = shallowCopy(posFirst)
          pos.y = pos.y + 0.5
          for i=1,#playedCards do
            playedCards[i].setPositionSmooth(pos,false,true)
            playedCards[i].setRotation(rot90)
            pos.y = pos.y + .1
          end
          pos.y = pos.y + 1
          if (deckType=="Black") then
            spinnableCards["Black"].setPositionSmooth(pos,false,true)
          elseif (deckType=="Red") then
            spinnableCards["Red"].setPositionSmooth(pos,false,true)
          else
            spinnableCards["Wild"].setPositionSmooth(pos,false,true)
          end
      else
        for _, oneCard in pairs(spinnableCards) do
          if oneCard then
            pos = posLast
            if (cardDropped) then
              pos.x = pos.x + gfSpreadMult*math.sin(math.rad(rot.y))
              pos.z = pos.z + gfSpreadMult*math.cos(math.rad(rot.y))
              pos.y = pos.y + dropHeight
            end
            posLast = pos
            oneCard.setPositionSmooth(pos,false,true)
            oneCard.setRotation(rot)
            cardDropped = true
          end
        end
      end
--      Player[player].broadcast(#playedCards .. " cards")
      debug("cardtype, decktype, cardcount = " .. cardType .. ", " .. deckType .. ", " .. cardCount, "prob1")
    end
    debug("spread-topdropspot2 = " .. dump(vTopDropSpot),"layoutsel")
    playerStuff[player].bSpreading=false
    return vTopDropSpot
  else
    debug("Avoided a spread","prob1")
  end
  playerStuff[player].bSpreading=false

end




function addRelativePos(sDir, vPos, vRot, fDelta)
  local vOut = vPos
  if (gt_DECODE_DIR[vRot.y][1]=="x") then
    vOut.z = vOut.z + (fDelta*gt_DECODE_DIR[vRot.y][2])
  else
    vOut.x = vOut.x + (fDelta*gt_DECODE_DIR[vRot.y][2])
  end
  return vOut
end

function findLeftMostAndHighest(tOrigSelObjects, vRot)
  local cDecodeDir = { [0]={"x",-1}, [90]={"z",-1}, [180]={"x",1}, [270]={"z",1} }
  local sMostLeft = ""
  local oMostLeft = nil
  local vMostLeftPos = {} -- {x=0, y=0, z=0}
  local sHighest = ""
  local oHighest = nil
  local vHighestPos = {} -- {x=0, y=0, z=0}
  for k, v in pairs(tOrigSelObjects) do
--    debug("checking position of " .. v.getDescription() .. " (" .. dump(v.getPosition()) ..")","layoutsel")
    if (cDecodeDir[vRot.y][1]=="x") then
--      debug("checking x " .. v.getPosition().x .. " modified by " ..  cDecodeDir[vRot.y][2],"layoutsel")
      if ((not oMostLeft) or v.getPosition().x*cDecodeDir[vRot.y][2]<vMostLeftPos.x*cDecodeDir[vRot.y][2]) then
        sMostLeft = v.getDescription()
        oMostLeft = v
        vMostLeftPos = v.getPosition()
      end
      if ((not oHighest) or v.getPosition().z*cDecodeDir[vRot.y][2]>vHighestPos.z*cDecodeDir[vRot.y][2]) then
        sHighest = v.getDescription()
        oHighest = v
        vHighestPos = v.getPosition()
      end

    else
      -- this should be a <... my 1/-1 in cdecode seems wrong but it's working for the nearMe
      -- so I'll flip it as a > for now.
      if ((not oMostLeft) or v.getPosition().z*cDecodeDir[vRot.y][2]>vMostLeftPos.z*cDecodeDir[vRot.y][2]) then
        sMostLeft = v.getDescription()
        oMostLeft = v
        vMostLeftPos = v.getPosition()
      end
      if ((not oHighest) or v.getPosition().x*cDecodeDir[vRot.y][2]>vHighestPos.x*cDecodeDir[vRot.y][2]) then
        sHighest = v.getDescription()
        oHighest = v
        vHighestPos = v.getPosition()
      end
    end
  end
--  debug("Most Left = " .. sMostLeft,"layoutsel")
--  debug("Highest = " .. sHighest,"layoutsel")
  return oMostLeft, oHighest
end

-- function getCardsInMyVertical(oCard, vRot, sColor, tOrigSelObjects)
--   local fCardPadding = 0.2
--   -- detect a small rectange, extending to either side the width of a card turned on
--   -- it's side (so the long side, plus the padding between cards,plus a tiny bit more to hit the card
--   local detectorSize = { gv_CARD_SIZE.z*.75, 1, gv_CARD_SIZE.x*5}
--   local t = {
--     ["origin"] = oCard.getPosition(),
--     ["direction"] = {0,1,0},
--     ["type"] = 3, -- box
--     ["size"] = detectorSize,
--     ["orientation"] = {vRot.x, vRot.y, vRot.z},
--     ["distance"] = .02,
--     ["debug"] = gbDevGhostBoxes, -- make it visible for Now
--   }
--   local objs = Physics.cast(t)
--   local alreadyCheckedGUIDs = {}
--   local tSelectionToSpread = {}
--   for k, v in pairs(objs) do
--     if ((v.hit_object.tag=="Card" or v.hit_object.tag=="Deck") and not alreadyCheckedGUIDs[v.hit_object.getGUID()] ) then
--       alreadyCheckedGUIDs[v.hit_object.getGUID()]=1
--       if (objectInScoreZone(v.hit_object, sColor)) then
--         if (findInTable(tOrigSelObjects,v.hit_object)>-1) then
--           table.insert(tSelectionToSpread,v.hit_object)
--         else
--           debug("v.hit_object: " .. v.hit_object.getDescription() .. " not in original set, so ignoring it", "layoutsel")
--         end
--       end
--     end
--   end
--   return tSelectionToSpread
-- end


function getDir(sDir, fRotY)
  local iVert=iif(sDir=="up",1, iif(sDir=="down",-1,0))
  local iHoriz=iif(sDir=="left",1, iif(sDir=="right",-1,0))
  debug("GetDir " .. dump(sDir) .. ", " .. dump(fRotY) .. ", " .. dump(iVert) .. ", " .. dump(iHoriz),"vertical")

  local vRet = {
             x = iVert*math.sin(math.rad(fRotY))    + iHoriz*math.cos(math.rad(fRotY)),
             y = 0,
             z = iVert*-1*math.cos(math.rad(fRotY)) + iHoriz*math.sin(math.rad(fRotY))
           }
  return vRet
end


function getCardsInMyVertical3(oCard, vRot, sColor, tOrigSelObjects, tAlreadyAccountedForObjs, vPos, sDir, alreadyCheckedGUIDs)
  local bFoundDifferentCard = false
  local tSelectionToSpread = {}
  local fCardPadding = 0.2
  local fDiscoveryDistance=gv_CARD_SIZE.x*0.5;

  local iWildCount = 0;

  if (not alreadyCheckedGUIDs) then
    alreadyCheckedGUIDs = {}
  end

  -- detect a small rectange, extending to either side the width of a card turned on
  -- it's side (so the long side, plus the padding between cards,plus a tiny bit more to hit the card
  local detectorSize = { gv_CARD_SIZE.z*.75, 2.0, gv_CARD_SIZE.x/10}

  vRot, sColor = getPlayerRotationFromObject(oCard)

  debug("getCardsInMyVertical3 called.. sdir=" .. nvl(sDir),"vertical")

  local aDir = {}
  if not sDir then
    aDir["up"]=getDir("up",vRot.y)
    aDir["down"]=getDir("down",vRot.y)
  else
    aDir[sDir]=getDir(sDir,vRot.y)
  end

  if (not vPos) then
    vPos = oCard.getPosition()
  end
  local firstNonWild = nil
  local iWildCount = 0;

  for sWorkingDir, vDir in pairs(aDir) do
    -- if we're not given a direction, then we're not in a recursive calls
    -- and we reset giLoopStop as a safety catch
    if not sDir then
      giLoopStop=0
    end
    debug("(" .. nvl(giLoopStop) .. ") scanning " .. sWorkingDir .. " vertically","vertical2")
    local bAddedToSelection = false
    local t = {
      ["origin"] = vPos,
      ["direction"] = vDir,
      ["type"] = 3, -- box
      ["size"] = detectorSize,
      ["orientation"] = {vRot.x, vRot.y, vRot.z},
      ["max_distance"] = fDiscoveryDistance,
      ["debug"] = gbDevGhostBoxes, -- make it visible for Now
    }
    local objs = Physics.cast(t)
    debug("(" .. nvl(giLoopStop) .. ") found " .. nvl(#objs) .. " to Evaluate: " ..dump(objs) ,"vertical2")
    local sType, sName, sSuit = cardDeets(oCard)
    if (sType != "Wild") then
      firstNonWild = sName .. iif(sName=="3",sType,"")
    end
    debug("(" .. nvl(giLoopStop) .. ") scanning " .. sWorkingDir .. "(dir:" .. dump(vDir) .. ") vertically","vertical2")

    -- if (tAlreadyAccountedForObjs) then
    --   for k, v in pairs(tAlreadyAccountedForObjs) do
    --     alreadyCheckedGUIDs[v.getGUID()]=1
    --   end
    -- end

    debug("AlreadyChecked = " .. dump(alreadyCheckedGUIDs),"vertical2")

    for k, v in pairs(objs) do

      if (v.hit_object.tag=="Card" or v.hit_object.tag=="Deck") then
        debug("checking k=" .. k .. "(" .. v.hit_object.getGUID() .. ")", "vertical2")
      end

      if ((v.hit_object.tag=="Card" or v.hit_object.tag=="Deck")
          and not alreadyCheckedGUIDs[v.hit_object.getGUID()]) then
        debug("passed first gate", "vertical2")
        alreadyCheckedGUIDs[v.hit_object.getGUID()]=1
        if (objectInScoreZone(v.hit_object, sColor)) then
          if (not tOrigSelObjects or findInTable(tOrigSelObjects,v.hit_object)>-1) then
            local sType, sName, sSuit = nil
            if (v.hit_object.tag=="Deck") then
              local _,_,_,cardType = scoreTarget(v.hit_object)
              if (cardType == 'MIXED') then
                bFoundDifferentCard = true
                break
              end
              -- mark it wild or notwild (don't really care, let's just say black)
              sType = iif(cardType == "Wild","Wild","Black")
              sName = cardType
              if (sType == "Wild") then
                iWildCount = 7 -- (Really, just need any number > 2 here)
              end
              debug("Checking Deck type/name = " .. sType .. "/" .. sName,"vertical")
            else
              sType, sName, _ = cardDeets(v.hit_object)
              debug("vert found card " .. sName .. " (" .. sType .. ")","vertical")
            end

            if (sType=="Wild") then
              iWildCount = iWildCount + 1 -- yes, we maybe just doublecounted a deck (7+1) but don't care.. >2 is all we care about
            end
            debug("vert iWildCount= " .. iWildCount,"vertical")


            if (sType=="Red" and sName=="3") then
              bFoundDifferentCard = true
              debug("Found a Red 3. stop","vertical")
              break
            elseif (sType != "Wild" and firstNonWild and firstNonWild != sName .. iif(sName=="3",sType,"")) then
              bFoundDifferentCard = true
              debug("Found Different Card = true","vertical")
              break
            elseif (sType != "Wild") and iWildCount>2 then
              -- we have a non-wild card but we've already seen 2 wilds.. so
              -- we think we're looking at a wild book.  Therefore, this is Different
              -- and we break out.
              bFoundDifferentCard = true
              debug("Found Different Card (nonwild in field of wilds) = true.  Type=" .. sType,"vertical")
              break
            elseif ((sType != "Wild") and (not firstNonWild) ) then
              -- THIS ELSE HAS TO COME LAST AFTER ALL THE DROPOUT ELSEIFs OR
              -- IT WON'T GET TO THEM.
              firstNonWild = sName .. iif(sName=="3",sType,"")
              debug("setting firstnonwild =" .. sName .. " (type = " .. sType .. ")","vertical")
            else
              debug("No exceptional state found for " .. v.hit_object.tag .. " " .. sName .. " (" .. sType.. ")","vertical")
            end

            debug(firstNonWild,"layoutsel")
            if (firstNonWild) then
              debug("Added " .. v.hit_object.getDescription() .. " while firstNonWild=".. firstNonWild .. " sName="..sName .. iif(sName=="3",sType,""),"vertical")
            end
            table.insert(tSelectionToSpread,v.hit_object)
            bAddedToSelection = true
          else
            debug("v.hit_object: " .. v.hit_object.getDescription() .. " not in original set, so ignoring it", "vertical")
          end
        end
      end
    end

    if #tSelectionToSpread>0 and bAddedToSelection then
      if not giLoopStop then
        giLoopStop=0
      end
      debug("(" .. giLoopStop .. ") found " .. nvl(#tSelectionToSpread) .. " to spread, so recursing ".. nvl(sWorkingDir),"vertical2")
      debug("(" .. giLoopStop .. ") cards: " .. dump(tSelectionToSpread),"vertical2")
      local tCards={}
      local oFarthest = findFarthestOnAxisDirection(tSelectionToSpread,vDir)
      debug("(" .. giLoopStop .. ") farthest (Starting point) is " .. oFarthest.getDescription(),"vertical2")
      if (giLoopStop<10) then
        giLoopStop = giLoopStop+1
        tCards, bFoundDifferentCard = getCardsInMyVertical3(oFarthest, vRot, sColor, nil, tSelectionToSpread,nil,sWorkingDir, alreadyCheckedGUIDs)
      end
      debug("(" .. giLoopStop .. ") " .. sWorkingDir.." search found " .. #tCards .. " and adding to selection", "vertical2" )
      debug(dump(tCards),"vertical2")
      for _, obj in pairs(tCards) do
        tablepush(tSelectionToSpread, obj)
      end
    end
  end

--  debug("(" .. giLoopStop .. ") cards: " .. dump(tCards),"vertical2")

  -- Include the original set of cards in the set of cards to be spread
  if (tOrigSelObjects) then
    for _, obj in pairs(tOrigSelObjects) do
      tablepush(tSelectionToSpread, obj)
    end
  end
  return tSelectionToSpread, bFoundDifferentCard
end

function findFarthestOnAxisDirection(tObjects, vDir)
  local oFnd = nil
  local iFnd = nil
  for _, oObj in pairs (tObjects) do
    iDist= oObj.getPosition().x*vDir.x + oObj.getPosition().z*vDir.z
    if not iFnd or iFnd < iDist then
      iFnd = iDist
      oFnd = oObj
    end
  end
  return oFnd
end



-- =============================================================================
function getCardsInMyVertical2(oCard, vRot, sColor, tOrigSelObjects, vPos)
  local bFoundDifferentCard = false
  local alreadyCheckedGUIDs = {}
  local tSelectionToSpread = {}
  local fCardPadding = 0.2
  local fDiscoveryDistance=gv_CARD_SIZE.x*0.5;

  local iWildCount = 0;

  -- detect a small rectange, extending to either side the width of a card turned on
  -- it's side (so the long side, plus the padding between cards,plus a tiny bit more to hit the card
  local detectorSize = { gv_CARD_SIZE.z*.75, 2.0, gv_CARD_SIZE.x/10}

  vRot, sColor = getPlayerRotationFromObject(oCard)


  local aDir = {}
  if gt_DECODE_DIR[vRot.y][1]=="x" then
    aDir[1] = {0,0,-1}
    aDir[2] = {0,0,1}
  else
    aDir[1] = {-1,0,0}
    aDir[2] = {1,0,0}
  end

  if (not vPos) then
    vPos = oCard.getPosition()
  end
  local firstNonWild = nil
  local iWildCount = 0;

  for _, vDir in pairs(aDir) do
    local t = {
      ["origin"] = vPos,
      ["direction"] = vDir,
      ["type"] = 3, -- box
      ["size"] = detectorSize,
      ["orientation"] = {vRot.x, vRot.y, vRot.z},
      ["max_distance"] = fDiscoveryDistance,
      ["debug"] = gbDevGhostBoxes, -- make it visible for Now
    }
    local objs = Physics.cast(t)
    local sType, sName, sSuit = cardDeets(oCard)
    if (sType != "Wild") then
      firstNonWild = sName .. iif(sName=="3",sType,"")
    end
    for k, v in pairs(objs) do
      if ((v.hit_object.tag=="Card" or v.hit_object.tag=="Deck") and not alreadyCheckedGUIDs[v.hit_object.getGUID()] ) then
        alreadyCheckedGUIDs[v.hit_object.getGUID()]=1
        if (objectInScoreZone(v.hit_object, sColor)) then
          if (not tOrigSelObjects or findInTable(tOrigSelObjects,v.hit_object)>-1) then
            local sType, sName, sSuit = nil
            if (v.hit_object.tag=="Deck") then
              local _,_,_,cardType = scoreTarget(v.hit_object)
              if (cardType == 'MIXED') then
                bFoundDifferentCard = true
                break
              end
              -- mark it wild or notwild (don't really care, let's just say black)
              sType = iif(cardType == "Wild","Wild","Black")
              sName = cardType
              if (sType == "Wild") then
                iWildCount = 7 -- (Really, just need any number > 2 here)
              end
              debug("Checking Deck type/name = " .. sType .. "/" .. sName,"vertical")
            else
              sType, sName, _ = cardDeets(v.hit_object)
              debug("vert found card " .. sName .. " (" .. sType .. ")","vertical")
            end

            if (sType=="Wild") then
              iWildCount = iWildCount + 1 -- yes, we maybe just doublecounted a deck (7+1) but don't care.. >2 is all we care about
            end
            debug("vert iWildCount= " .. iWildCount,"vertical")


            if (sType=="Red" and sName=="3") then
              bFoundDifferentCard = true
              debug("Found a Red 3. stop","vertical")
              break
            elseif (sType != "Wild" and firstNonWild and firstNonWild != sName .. iif(sName=="3",sType,"")) then
              bFoundDifferentCard = true
              debug("Found Different Card = true","vertical")
              break
            elseif (sType != "Wild") and iWildCount>2 then
              -- we have a non-wild card but we've already seen 2 wilds.. so
              -- we think we're looking at a wild book.  Therefore, this is Different
              -- and we break out.
              bFoundDifferentCard = true
              debug("Found Different Card (nonwild in field of wilds) = true.  Type=" .. sType,"vertical")
              break
            elseif ((sType != "Wild") and (not firstNonWild) ) then
              -- THIS ELSE HAS TO COME LAST AFTER ALL THE DROPOUT ELSEIFs OR
              -- IT WON'T GET TO THEM.
              firstNonWild = sName .. iif(sName=="3",sType,"")
              debug("setting firstnonwild =" .. sName .. " (type = " .. sType .. ")","vertical")
            else
              debug("No exceptional state found for " .. v.hit_object.tag .. " " .. sName .. " (" .. sType.. ")","vertical")
            end

            debug(firstNonWild,"layoutsel")
            if (firstNonWild) then
              debug("Added " .. v.hit_object.getDescription() .. " while firstNonWild=".. firstNonWild .. " sName="..sName .. iif(sName=="3",sType,""),"vertical")
            end
            table.insert(tSelectionToSpread,v.hit_object)
          else
            debug("v.hit_object: " .. v.hit_object.getDescription() .. " not in original set, so ignoring it", "vertical")
          end
        end
      end
    end
  end
  return tSelectionToSpread, bFoundDifferentCard
end

-- =============================================================================
function nvl(val, ifnil)
  if (val) then
    return val
  else
    if (ifnil) then
      return ifnil
    else
      return "nil"
    end
  end
end

--==============================================================================
-- Zone / player accessor helpers
-- Use these instead of spelling out objScoreZones[giPlayerCount]["Colors"][sColor]
-- everywhere.  All return nil (with no crash) when zones aren't initialised yet.

-- Returns the colorZones table {footPos, zones[]} for sColor, or nil.
function getPlayerZones(sColor)
  if not giPlayerCount or not objScoreZones[giPlayerCount] then return nil end
  local cz = objScoreZones[giPlayerCount]["Colors"][sColor]
  if not cz or not cz.zones then return nil end
  return cz
end

-- Returns the zone-entry table {obj, scl, pos} for zone index zi (default 1).
function getPlayerZone(sColor, zi)
  local cz = getPlayerZones(sColor)
  if not cz then return nil end
  return cz.zones[zi or 1]
end

-- Returns the Y rotation for sColor's hand zone (0/90/180/270).
function getPlayerRotY(sColor)
  return gt_COLOR_ROT[sColor] or 0
end

-- Returns the decode-dir entry {lateralAxis, direction} for sColor.
function getPlayerDecodeDir(sColor)
  return gt_DECODE_DIR[getPlayerRotY(sColor)]
end

--==============================================================================
-- State Query API
-- Pure functions that describe the current game state as plain Lua tables.
-- These have no side effects and do not move or animate anything.
-- A future decision engine can call these freely to reason about the board.

-- Returns a list of {rank, suit, color, obj} for every card in sColor's hand.
-- Wilds are included.  'obj' is the live TTS object reference.
function getHandCards(sColor)
  local result = {}
  local ok, hand = pcall(function() return Player[sColor].getHandObjects() end)
  if not ok or not hand then return result end
  for _, card in ipairs(hand) do
    pcall(function()
      local c, r, s = cardDeets(card)
      table.insert(result, {rank=r, suit=s, color=c, obj=card})
    end)
  end
  return result
end

-- Returns a list of {rank, isBook, obj, pos} for every meld/book in sColor's
-- score zones.  'isBook' is true when the Deck has 7+ cards.
-- Red-3 stacks (rank "3") are included so callers can filter as needed.
function getMelds(sColor)
  local result = {}
  local colorZones = getPlayerZones(sColor)
  if not colorZones then return result end
  local seen = {}
  for _, scoreZone in ipairs(colorZones.zones) do
    local ok, objs = pcall(function() return scoreZone.obj.getObjects() end)
    if ok and objs then
      for _, obj in ipairs(objs) do
        pcall(function()
          if obj.is_face_down then return end
          local guid = obj.getGUID()
          if seen[guid] then return end
          seen[guid] = true
          local rank, pos
          local isBook = false
          if obj.tag == "Card" then
            local _, r, _ = cardDeets(obj)
            rank = r
            pos  = obj.getPosition()
          elseif obj.tag == "Deck" then
            local ok_d, cards = pcall(function() return obj.getObjects() end)
            if ok_d and cards and #cards > 0 then
              local _, r, _ = cardDeets(cards[1])
              rank = r
            end
            local ok_q, qty = pcall(function() return obj.getQuantity() end)
            if ok_q and qty and qty >= 7 then isBook = true end
            pos = obj.getPosition()
          end
          if rank then
            table.insert(result, {rank=rank, isBook=isBook, obj=obj, pos=pos})
          end
        end)
      end
    end
  end
  return result
end

-- Returns a list of rank strings that the player can legally meld from hand:
-- 3+ non-wild cards of that rank, and playing them won't leave fewer than 2
-- total cards in hand.  Wilds and 3s are always excluded.
function getEligibleRanks(sColor)
  local hand = getHandCards(sColor)
  local byRank = {}
  local total  = #hand
  for _, entry in ipairs(hand) do
    if entry.color ~= "Wild" and entry.rank ~= "3" then
      byRank[entry.rank] = (byRank[entry.rank] or 0) + 1
    end
  end
  local result = {}
  for rank, cnt in pairs(byRank) do
    if cnt >= 3 and (total - cnt) >= 2 then
      table.insert(result, rank)
    end
  end
  return result
end

-- Returns {ok=bool, reason=string}.  Checks whether sColor can meld 'rank'
-- from hand right now (3+ cards available, won't leave fewer than 2 in hand).
function canMeld(sColor, rank)
  if not isEligibleRank(rank) then
    return {ok=false, reason="cannot meld wilds or 3s"}
  end
  local hand  = getHandCards(sColor)
  local total = #hand
  local cnt   = 0
  for _, entry in ipairs(hand) do
    if entry.rank == rank and entry.color ~= "Wild" then cnt = cnt + 1 end
  end
  if cnt < 3 then
    return {ok=false, reason="only " .. cnt .. " of rank " .. rank .. " in hand (need 3)"}
  end
  if (total - cnt) < 2 then
    return {ok=false, reason="would leave fewer than 2 cards in hand"}
  end
  return {ok=true, reason="ok"}
end

-- Returns the position {x,y,z} of the topmost (nearest-center) non-book card
-- in the existing meld for sColor's 'rank', or nil if no such meld exists.
function getMeldAnchor(sColor, rank)
  local melds = getMelds(sColor)
  local decode = getPlayerDecodeDir(sColor)
  if not decode then return nil end
  local lateralAxis = decode[1]
  local direction   = decode[2]
  local depthAxis   = (lateralAxis == "x") and "z" or "x"
  local bestScore, bestPos = nil, nil
  for _, meld in ipairs(melds) do
    if meld.rank == rank and not meld.isBook and meld.pos then
      local score = meld.pos[depthAxis] * direction
      if bestScore == nil or score > bestScore then
        bestScore = score
        bestPos   = meld.pos
      end
    end
  end
  return bestPos
end

--==============================================================================
-- ZHF_Advisor — Turn advisor (inlined from ZHF_Advisor.lua)
-- Entry points: buildTurnPlan(sColor), executeTurnPlan(plan), printTurnPlan(plan, sColor)
--==============================================================================

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
  local wildCount = 0
  local rankFound = nil
  local mixed     = false
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
  if mixed then return nil end
  if wildCount == qty then return "wild" end
  if wildCount > 0 then return "black" end
  return "red"
end

-- Returns a plain-data snapshot of sColor's game state.
-- Fields: color, hand, handCount, handByRank, wildCount, melds, meldsByRank,
--         books {red,black,wild}, bookCounts {red,black,wild}, hasFoot, canGoOut
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
      if meld.rank and not meldsByRank[meld.rank] then
        meldsByRank[meld.rank] = meld
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

-- Should the player go out? Returns {should=bool, reason=string}
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

-- Which melds to play from hand, sorted by priority.
-- Priority: 1=completes book, 2=extends meld, 3=new meld.
-- Returns [{rank, cards, count, existingCount, priority, reason}]
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
function evalDiscard(state, meldPlan)
  local melding = {}
  for _, m in ipairs(meldPlan) do melding[m.rank] = true end

  local remaining = {}
  for _, card in ipairs(state.hand) do
    if not melding[card.rank] then table.insert(remaining, card) end
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
    elseif card.rank ~= "3" then          -- red 3s silently skipped
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

  -- Group candidates by rank: byRank[rank] = {cards=[]}
  local byRank = {}
  for _, card in ipairs(candidates) do
    if not byRank[card.rank] then byRank[card.rank] = {rank=card.rank, cards={}} end
    table.insert(byRank[card.rank].cards, card)
  end

  -- Build flat list of rank-groups.
  local groups = {}
  for _, g in pairs(byRank) do table.insert(groups, g) end

  -- RULE 3: Minimum count across all groups.
  local minCount = math.huge
  for _, g in ipairs(groups) do
    if #g.cards < minCount then minCount = #g.cards end
  end
  local atMinCount = {}
  for _, g in ipairs(groups) do
    if #g.cards == minCount then table.insert(atMinCount, g) end
  end

  -- RULE 4: Lowest strata within min-count groups.
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

  -- RULE 5: Prefer same-color (mono-color) groups.
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

  -- RULE 7: Tiebreaker — highest rank within strata (across remaining pool).
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
  local function removingCardKeepsBalance(card, groupCards)
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
      if removingCardKeepsBalance(card, chosen.cards) then
        pick = card; break
      end
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

-- Assembles a complete TurnPlan. Returns plain table; nothing is moved.
-- Fields: color, state, goOut, melds, discard, log[], ok
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
  return {color=sColor, state=state, goOut=goOut, melds=melds, discard=discard, log=log, ok=true}
end

-- Executes a TurnPlan: plays melds via layoutHandRank (staggered like layoutHandAll),
-- then discards after all animations finish.
function executeTurnPlan(plan)
  if not plan.ok then return end
  local sColor = plan.color

  -- Stagger meld ranks the same way layoutHandAll does: each rank fires after
  -- the previous one has had time to land, so computeNewLinePosition sees the
  -- already-placed cards and picks the next lateral slot correctly.
  local t = 0
  for _, m in ipairs(plan.melds) do
    local capturedRank = m.rank
    Wait.time(function()
      layoutHandRank(sColor, capturedRank, true)  -- red 3s already handled by buildTurnPlan
    end, t)
    t = t + (m.count * 0.15) + 0.75
  end

  -- Discard fires after all melds have finished (t is now the total meld time).
  if plan.discard.card and not plan.goOut.should then
    Wait.time(function()
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
    end, t + 0.5)
  end
end

-- Prints plan.log to sColor's chat window.
function printTurnPlan(plan, sColor)
  for _, line in ipairs(plan.log) do
    printToColor(line, sColor)
  end
end

--==============================================================================
function objectInScoreZone(oThing, sColor)
  if not sColor then return false end
  local colorEntry = getPlayerZones(sColor)
  if not colorEntry then return false end
  for _, scoreZone in ipairs(colorEntry.zones) do
    local ok, inZone = pcall(function() return objectInZone(oThing, scoreZone.obj) end)
    if ok and inZone then
      return true
    end
  end
  return false
end
--==============================================================================
function getAllScoreZones()
  local tOut={}
  debug("getting all score zones","getallscorezones")
  if not objScoreZones[giPlayerCount] then
    log("WARNING: getAllScoreZones - no zones defined for player count " .. tostring(giPlayerCount))
    return tOut
  end
  for sColor, scoreZones in pairs(objScoreZones[giPlayerCount]["Colors"]) do
    if scoreZones.zones then
      debug("looping through " .. #scoreZones.zones .. " zones for " .. sColor,"getallscorezones")
      for _, scoreZone in ipairs(scoreZones.zones) do
        local ok, guid = pcall(function() return scoreZone.obj.getGUID() end)
        if ok and guid then
          debug("adding zone " .. guid,"getallscorezones")
          table.insert(tOut, {color=sColor, guid=guid})
        else
          log("WARNING: getAllScoreZones - stale or nil zone object for color " .. tostring(sColor))
        end
      end
    else
      log("WARNING: getAllScoreZones - no zones for color " .. tostring(sColor) .. " at player count " .. tostring(giPlayerCount))
    end
  end
  debug("returning " .. dump(tOut),"getallscorezones")
  return tOut
end

--==============================================================================
-- Examines sColor's hand and plays any non-wild card whose rank already exists
-- on the table (in their score zones).  Cards are played one at a time with a
-- Collects all card objects of a given rank from sColor's score zones.
-- Returns the list of objects (Cards and Decks containing that rank).
function getTableCardsOfRank(sColor, rank)
  local result = {}
  local colorZones = getPlayerZones(sColor)
  if not colorZones then return result end
  for _, scoreZone in ipairs(colorZones.zones) do
    local ok, zoneObjs = pcall(function() return scoreZone.obj.getObjects() end)
    if ok and zoneObjs then
      for _, obj in ipairs(zoneObjs) do
        pcall(function()
          if not obj.is_face_down then
            if obj.tag == "Card" then
              local _, r, _ = cardDeets(obj)
              if r == rank then table.insert(result, obj) end
            elseif obj.tag == "Deck" then
              local ok_dc, deckCards = pcall(function() return obj.getObjects() end)
              if ok_dc and deckCards and #deckCards > 0 then
                local _, r, _ = cardDeets(deckCards[1])
                if r == rank then table.insert(result, obj) end
              end
            end
          end
        end)
      end
    end
  end
  return result
end

--==============================================================================
-- Returns the world position for the red-3 meld: just below the player's
-- face-down foot pile (away from board center, toward the player's edge).
function getRedThreeMeldPos(sColor)
  local decode = getPlayerDecodeDir(sColor)
  if not decode then return nil end
  local lateralAxis = decode[1]
  local direction   = decode[2]
  local depthAxis   = (lateralAxis == "x") and "z" or "x"

  -- Scan score zones for the face-down foot pile to get its actual world position.
  local footPilePos = nil
  local cz_foot = getPlayerZones(sColor)
  if cz_foot then
    for _, sz in ipairs(cz_foot.zones) do
      local ok, objs = pcall(function() return sz.obj.getObjects() end)
      if ok and objs then
        for _, obj in ipairs(objs) do
          if obj.is_face_down then
            local ok_p, p = pcall(function() return obj.getPosition() end)
            if ok_p and p then footPilePos = p; break end
          end
        end
      end
      if footPilePos then break end
    end
  end
  -- Fallback: use the dealing-time footPos stored in playerStuff
  if not footPilePos then
    local ps = playerStuff and playerStuff[sColor]
    if ps and ps.footPos and #ps.footPos >= 3 then
      footPilePos = {x=ps.footPos[1], y=ps.footPos[2], z=ps.footPos[3]}
    end
  end
  if not footPilePos then return nil end

  -- Place the red-3 stack below (toward the player's edge) the foot pile,
  -- in line with it along the lateral axis.
  -- The foot pile sits at the outer edge of the scoring zone in the depth
  -- direction, so "below" technically exits the scoring zone.  This is
  -- fine visually — the card is placed face-down first (hand zones only
  -- reclaim face-up cards), then flipped face-up once settled.
  local gap = gv_CARD_SIZE.z * 1.5   -- ~3 units below the foot pile
  local pos = {x=footPilePos.x, y=footPilePos.y, z=footPilePos.z}
  -- -direction moves AWAY from board center (toward the player's edge).
  pos[depthAxis] = footPilePos[depthAxis] - direction * gap
  return pos
end

--==============================================================================
-- Moves all red 3s (3♥ / 3♦) from the player's hand to the red-3 side-stack
-- meld below the foot pile, drawing one replacement card from mainDeck for
-- each.  Repeats recursively if a replacement card is itself a red 3.
-- Calls callback() once no more red 3s remain in hand.
function handleRedThrees(sColor, callback, depth)
  depth = depth or 0
  if depth > 8 then          -- safety: at most 8 passes (deck has only 4 red 3s)
    if callback then callback() end
    return
  end

  local hand  = Player[sColor].getHandObjects()
  local red3s = {}
  for _, card in ipairs(hand) do
    local cardColor, rank, suit = cardDeets(card)
    -- Only Hearts and Diamonds 3s go to the side stack; never Clubs or Spades.
    if rank == "3" and (suit == "Hearts" or suit == "Diamonds") then
      table.insert(red3s, card)
    end
  end

  if #red3s == 0 then
    if callback then callback() end
    return
  end

  local targetPos = getRedThreeMeldPos(sColor)
  if not targetPos then
    broadcastToColor("Could not locate foot pile for red 3 placement", sColor)
    if callback then callback() end
    return
  end

  broadcastToColor("Moving " .. #red3s .. " red 3(s) to side stack", sColor)

  local t = 0
  for _, card in ipairs(red3s) do
    local captured = card
    local pos      = targetPos
    Wait.time(function()
      pcall(function()
        -- Flip face-down before placing so the native hand zone doesn't
        -- reclaim the card (hand zones only process face-up cards).
        -- Flip back face-up once the card is settled at the target position.
        captured.flip()
        captured.setPosition(pos)
        Wait.time(function()
          pcall(function() if not captured.is_face_down then return end
            captured.flip()
          end)
        end, 0.4)
      end)
    end, t)
    t = t + 0.3
    -- Draw a replacement card from the main deck for each red 3 played
    Wait.time(function()
      if mainDeck then
        local ok, qty = pcall(function() return mainDeck.getQuantity() end)
        if ok and qty and qty > 0 then
          pcall(function() mainDeck.deal(1, sColor) end)
        end
      end
    end, t)
    t = t + 0.5
  end

  -- After replacements arrive, check again in case a drawn card is also a red 3
  local capturedDepth    = depth
  local capturedCallback = callback
  Wait.time(function()
    handleRedThrees(sColor, capturedCallback, capturedDepth + 1)
  end, t + 0.5)
end

--==============================================================================
-- planAutoPlay: pure decision layer for "Play Hand".
-- Scans the table and hand; returns a move list or a failure result.
-- Returns {ok=false, reason=string} or
--   {ok=true, moves=[{rank, cards=[], target={obj,pos}}], totalCards=n}
function planAutoPlay(sColor)
  local colorZones = getPlayerZones(sColor)
  if not colorZones then
    return {ok=false, reason="No score zones found for " .. sColor}
  end

  -- Build rank target map from score zones
  local meldTargets = {}
  local bookTargets = {}
  for _, scoreZone in ipairs(colorZones.zones) do
    local ok, zoneObjs = pcall(function() return scoreZone.obj.getObjects() end)
    if ok and zoneObjs then
      for _, obj in ipairs(zoneObjs) do
        pcall(function()
          if obj.is_face_down then return end
          if obj.tag == "Card" then
            local cardColor, rank, _ = cardDeets(obj)
            if isEligibleRank(rank) and cardColor ~= "Wild" and not meldTargets[rank] then
              local ok_pos, pos = pcall(function() return obj.getPosition() end)
              if ok_pos and pos then meldTargets[rank] = {obj=obj, pos=pos} end
            end
          elseif obj.tag == "Deck" then
            local ok_qty, qty = pcall(function() return obj.getQuantity() end)
            local ok_dc, dc   = pcall(function() return obj.getObjects() end)
            if ok_dc and dc and #dc > 0 then
              local isBook = ok_qty and qty and qty >= 7
              local cardColor, rank, _ = cardDeets(dc[1])
              if isEligibleRank(rank) and cardColor ~= "Wild" then
                local ok_pos, pos = pcall(function() return obj.getPosition() end)
                if ok_pos and pos then
                  if isBook then
                    if not bookTargets[rank] then bookTargets[rank] = {obj=obj, pos=pos} end
                  else
                    if not meldTargets[rank] then meldTargets[rank] = {obj=obj, pos=pos} end
                  end
                end
              end
            end
          end
        end)
      end
    end
  end

  local rankTargets = {}
  for rank, t in pairs(meldTargets) do rankTargets[rank] = t end
  for rank, t in pairs(bookTargets) do
    if not rankTargets[rank] then rankTargets[rank] = t end
  end

  -- Find matching hand cards, grouped by rank
  local byRank, rankOrder = {}, {}
  local handCards = Player[sColor].getHandObjects()
  for _, card in ipairs(handCards) do
    local cardColor, rank, _ = cardDeets(card)
    if isEligibleRank(rank) and cardColor ~= "Wild" and rankTargets[rank] then
      if not byRank[rank] then byRank[rank] = {}; table.insert(rankOrder, rank) end
      table.insert(byRank[rank], card)
    end
  end

  local moves = {}
  local totalCards = 0
  for _, rank in ipairs(rankOrder) do
    table.insert(moves, {rank=rank, cards=byRank[rank], target=rankTargets[rank]})
    totalCards = totalCards + #byRank[rank]
  end

  if totalCards == 0 then
    return {ok=false, reason="No playable cards found in hand"}
  end
  return {ok=true, moves=moves, totalCards=totalCards}
end

--==============================================================================
-- executeAutoPlay: animation layer for "Play Hand".
function executeAutoPlay(sColor, plan)
  local function dph(str)
    if gtDebugFlags["playhand"] then printToColor("[playhand] " .. str, sColor) end
  end

  broadcastToColor("Auto-playing " .. plan.totalCards .. " card(s)", sColor)

  local t = 0
  for _, move in ipairs(plan.moves) do
    for _, card in ipairs(move.cards) do
      local capturedCard = card
      local capturedTarget = move.target
      Wait.time(function()
        local ok, desc = pcall(function() return capturedCard.getDescription() end)
        if ok then
          dph("playing " .. desc .. " onto rank " .. move.rank)
          capturedCard.setPosition(capturedTarget.pos)
          playerStuff[sColor].bSpreadQueued = true
          queueSpread(sColor, capturedCard)
        else
          dph("card gone by timer time")
        end
      end, t)
      t = t + 0.75
    end
    local capturedRank   = move.rank
    local capturedTarget = move.target
    Wait.time(function()
      local allCards = getTableCardsOfRank(sColor, capturedRank)
      local safeCards = {}
      for _, obj in ipairs(allCards) do
        local ok = pcall(function() obj.getPosition() end)
        if ok then table.insert(safeCards, obj) end
      end
      if #safeCards > 0 then spread4(sColor, capturedTarget.pos, safeCards) end
    end, t)
    t = t + 0.75
  end

  Wait.time(function() broadcastToColor("hand played", sColor) end, t)
end

function autoPlayMatchingCards(sColor, skipRedThrees)
  if not skipRedThrees then
    handleRedThrees(sColor, function() autoPlayMatchingCards(sColor, true) end)
    return
  end
  local plan = planAutoPlay(sColor)
  if not plan.ok then broadcastToColor(plan.reason, sColor); return end
  executeAutoPlay(sColor, plan)
end

--==============================================================================
-- Computes the table position for a brand-new meld line in the player's zone.
-- Only considers zone 1. Scans existing melds left→right and fills the first
-- gap wide enough for a new meld. Falls back to right of rightmost, then left
-- of leftmost on overflow. Empty zone: top edge of zone 1, laterally centered.
function computeNewLinePosition(sColor, colorZones, rotY, dph)
  local decode      = gt_DECODE_DIR[rotY]
  local lateralAxis = decode[1]   -- "x" or "z"
  local direction   = decode[2]   -- -1 or +1; also "toward center" sign on depthAxis
  local depthAxis   = (lateralAxis == "x") and "z" or "x"
  local cardGap     = gv_CARD_SIZE.x + 0.2   -- 3.2 units center-to-center between melds

  -- Collect meld columns from zone 1: group face-up non-book objects by lateral
  -- position (tolerance 1 unit = same column).  Track topmost depth per column.
  local topmostScore = nil
  local topmostDepth = nil
  local columns      = {}   -- list of { lat, dep } one entry per meld column

  -- Returns true if an object is the red-3 side-stack meld (rank "3").
  -- These should be ignored when deciding where to place new rank melds.
  local function isRed3Meld(obj)
    -- Returns true only for Hearts/Diamonds 3s (the red-3 side stack).
    -- Black 3s (Clubs/Spades) are normal meld cards and must not be skipped.
    local function isRedThree(cardInfo)
      local _, rank, suit = cardDeets(cardInfo)
      return rank == "3" and (suit == "Hearts" or suit == "Diamonds")
    end
    if obj.tag == "Card" then
      return isRedThree(obj)
    elseif obj.tag == "Deck" then
      local ok_d, cards = pcall(function() return obj.getObjects() end)
      if ok_d and cards and #cards > 0 then
        return isRedThree(cards[1])
      end
    end
    return false
  end

  local zone1 = colorZones.zones[1]
  local ok, zoneObjs = pcall(function() return zone1.obj.getObjects() end)
  if ok and zoneObjs then
    for _, obj in ipairs(zoneObjs) do
      if not obj.is_face_down and (obj.tag == "Card" or obj.tag == "Deck")
         and not isRed3Meld(obj) then
        local ok_o, opos = pcall(function() return obj.getPosition() end)
        if ok_o and opos then
          local lat = opos[lateralAxis]
          local dep = opos[depthAxis]
          -- Track global topmost (nearest board center)
          local topScore = dep * direction
          if topmostScore == nil or topScore > topmostScore then
            topmostScore = topScore
            topmostDepth = dep
          end
          -- Cluster into columns by lateral position
          local found = false
          for _, col in ipairs(columns) do
            if math.abs(col.lat - lat) < 1.0 then
              found = true
              if dep * direction > col.dep * direction then col.dep = dep end
              break
            end
          end
          if not found then
            table.insert(columns, { lat = lat, dep = dep })
          end
        end
      end
    end
  end

  -- Get zone 1 live geometry
  local ok_p, z1p = pcall(function() return zone1.obj.getPosition() end)
  local ok_s, z1s = pcall(function() return zone1.obj.getScale()    end)
  local tableY    = (ok_p and z1p) and z1p.y or 1.0

  local newPos = { x = 0, y = tableY, z = 0 }

  if #columns > 0 then
    -- Sort columns from leftmost → rightmost (ascending lat * direction)
    table.sort(columns, function(a, b)
      return a.lat * direction < b.lat * direction
    end)

    newPos[depthAxis] = topmostDepth

    -- Scan left→right for a gap wide enough to insert a meld (>= 1.5 * cardGap)
    local placedLat = nil
    for i = 1, #columns - 1 do
      local gap = (columns[i+1].lat - columns[i].lat) * direction
      if gap >= cardGap * 1.5 then
        placedLat = columns[i].lat + direction * cardGap
        dph("gap between col " .. i .. " and " .. (i+1) .. ", placing at lat=" .. tostring(placedLat))
        break
      end
    end

    if not placedLat then
      -- No gap: try right of rightmost
      local candidateLat = columns[#columns].lat + direction * cardGap
      local inBounds = true
      if ok_p and z1p and ok_s and z1s then
        local zoneLatHalf = ((lateralAxis == "x") and z1s.x or z1s.z) / 2
        local zoneFarEdge = z1p[lateralAxis] + direction * zoneLatHalf
        if (candidateLat - zoneFarEdge) * direction > 0 then inBounds = false end
      end
      if inBounds then
        placedLat = candidateLat
        dph("no gap; right of rightmost at lat=" .. tostring(placedLat))
      else
        -- Overflow: left of leftmost
        placedLat = columns[1].lat - direction * cardGap
        dph("overflow; left of leftmost at lat=" .. tostring(placedLat))
      end
    end

    newPos[lateralAxis] = placedLat

  else
    -- Empty zone: 1.5 card-heights from top edge of zone 1, 35% from left edge
    -- (leftEdge + 0.35 * width = center - direction * 0.30 * halfWidth)
    if ok_p and z1p and ok_s and z1s then
      local depthScale   = (depthAxis == "z") and z1s.z or z1s.x
      local zoneLatHalf  = ((lateralAxis == "x") and z1s.x or z1s.z) / 2
      local zoneTopEdge  = z1p[depthAxis] + direction * (depthScale / 2)
      newPos[depthAxis]   = zoneTopEdge - direction * 1.0 * gv_CARD_SIZE.z
      newPos[lateralAxis] = z1p[lateralAxis] - direction * 0.30 * zoneLatHalf
      dph("empty zone: cardCenter=" .. tostring(newPos[depthAxis]) .. " lat=" .. tostring(newPos[lateralAxis]))
    elseif ok_p and z1p then
      newPos.x = z1p.x
      newPos.z = z1p.z
      dph("empty zone fallback: zone1 center")
    end
  end

  return newPos
end

--==============================================================================
--==============================================================================
-- planLayoutRank: pure decision layer — no side effects, no animation.
-- Returns {ok=bool, reason=string} on failure, or on success:
--   {ok=true, cards=[], targetPos={x,y,z}, colorZones=..., rotY=...,
--    rank=rank, sColor=sColor}
function planLayoutRank(sColor, rank)
  local colorZones = getPlayerZones(sColor)
  if not colorZones then
    return {ok=false, reason="No score zones found for " .. sColor}
  end
  if not isEligibleRank(rank) then
    return {ok=false, reason="Cannot layout wilds or 3s"}
  end

  local handCards = Player[sColor].getHandObjects()
  local rankCards = {}
  for _, card in ipairs(handCards) do
    local cardColor, r, _ = cardDeets(card)
    if r == rank and cardColor ~= "Wild" then
      table.insert(rankCards, card)
    end
  end

  if (#handCards - #rankCards) < 2 then
    return {ok=false, reason="Cannot play: would leave fewer than 2 cards in hand"}
  end

  local rotY = getPlayerRotY(sColor)

  -- Find target: topmost card of an existing incomplete meld, or a new slot
  local allTableCards = getTableCardsOfRank(sColor, rank)
  local existingCards = {}
  for _, obj in ipairs(allTableCards) do
    local isBook = false
    if obj.tag == "Deck" then
      local ok, qty = pcall(function() return obj.getQuantity() end)
      if ok and qty and qty >= 7 then isBook = true end
    end
    if not isBook then table.insert(existingCards, obj) end
  end

  -- Require 3+ cards to start a new meld; any count is fine when extending an existing one.
  local minCards = (#existingCards > 0) and 1 or 3
  if #rankCards < minCards then
    return {ok=false, reason="Need at least " .. minCards .. " of rank " .. rank .. " (have " .. #rankCards .. ")"}
  end

  local targetPos
  if #existingCards > 0 then
    local decode    = gt_DECODE_DIR[rotY]
    local depthAxis = (decode[1] == "x") and "z" or "x"
    local direction = decode[2]
    local bestScore = nil
    for _, ec in ipairs(existingCards) do
      local ok, epos = pcall(function() return ec.getPosition() end)
      if ok and epos then
        local score = epos[depthAxis] * direction
        if bestScore == nil or score > bestScore then
          bestScore = score; targetPos = epos
        end
      end
    end
    if not targetPos then
      local ok_fb, fb = pcall(function() return existingCards[1].getPosition() end)
      if ok_fb and fb then targetPos = fb end
    end
    if not targetPos then
      return {ok=false, reason="Could not read position of existing meld for rank " .. rank}
    end
  else
    local dphNoop = function() end
    targetPos = computeNewLinePosition(sColor, colorZones, rotY, dphNoop)
  end

  return {ok=true, cards=rankCards, targetPos=targetPos,
          colorZones=colorZones, rotY=rotY, rank=rank, sColor=sColor}
end

--==============================================================================
-- executeLayoutRank: animation layer — runs the Wait.time chain and spread4.
-- `plan` must be a successful result from planLayoutRank.
function executeLayoutRank(sColor, plan)
  local function dph(str)
    if gtDebugFlags["layouthand"] then printToColor("[layouthand] " .. str, sColor) end
  end

  broadcastToColor("Laying out " .. #plan.cards .. " card(s) of rank " .. plan.rank, sColor)

  local t = 0
  for _, card in ipairs(plan.cards) do
    local capturedCard = card
    local capturedPos  = plan.targetPos
    Wait.time(function()
      local ok = pcall(function() capturedCard.setPosition(capturedPos) end)
      if not ok then dph("card gone before timer fired") end
    end, t)
    t = t + 0.15
  end

  local capturedRank = plan.rank
  local capturedPos  = plan.targetPos
  Wait.time(function()
    if playerStuff[sColor] then playerStuff[sColor].bSpreading = false end
    local freshScan = getTableCardsOfRank(sColor, capturedRank)
    -- Do NOT filter out complete books (Deck qty>=7) here.
    -- spread4 needs to see the full Deck so it can count 7+ cards,
    -- apply the 90-degree rotation, and fire checkAndMoveBooks.
    local safeCards = {}
    for _, obj in ipairs(freshScan) do
      local ok = pcall(function() obj.getPosition() end)
      if ok then table.insert(safeCards, obj) end
    end
    dph("spread4 for rank=" .. capturedRank .. " safeCards=" .. #safeCards)
    if #safeCards > 0 then spread4(sColor, capturedPos, safeCards) end
    broadcastToColor("Layout complete for rank " .. capturedRank, sColor)
  end, t + 0.5)
end

--==============================================================================
-- Lays out 3+ cards of a given rank from the player's hand onto the table.
-- Adds to an existing meld if one exists; otherwise creates a new line.
-- Requires 3+ cards of that rank and won't leave fewer than 2 cards in hand.
function layoutHandRank(sColor, rank, skipRedThrees)
  if not skipRedThrees then
    handleRedThrees(sColor, function() layoutHandRank(sColor, rank, true) end)
    return
  end
  local plan = planLayoutRank(sColor, rank)
  if not plan.ok then
    broadcastToColor(plan.reason, sColor)
    return
  end
  executeLayoutRank(sColor, plan)
end

--==============================================================================
-- Lays out all eligible ranks from the player's hand, one rank at a time.
-- A rank is eligible if the player holds 3+ non-wild cards of that rank.
function layoutHandAll(sColor, skipRedThrees)
  -- Handle red 3s first; re-enter with skipRedThrees=true once done.
  if not skipRedThrees then
    handleRedThrees(sColor, function() layoutHandAll(sColor, true) end)
    return
  end

  -- Use getEligibleRanks: 3+ non-wild of rank, won't leave fewer than 2 in hand
  local eligible = getEligibleRanks(sColor)

  if #eligible == 0 then
    broadcastToColor("No eligible ranks to lay out (need 3+ of a rank)", sColor)
    return
  end

  broadcastToColor("Laying out " .. #eligible .. " rank(s) from hand", sColor)

  -- Schedule each rank with a stagger.
  -- planLayoutRank gives us the card count for a tight delay estimate;
  -- fall back to a conservative 7-card estimate if the plan fails.
  local t = 0
  for _, rank in ipairs(eligible) do
    local capturedRank = rank
    Wait.time(function()
      layoutHandRank(sColor, capturedRank, true)  -- red 3s already handled above
    end, t)
    local plan = planLayoutRank(sColor, rank)
    local nCards = (plan.ok and plan.cards) and #plan.cards or 7
    t = t + (nCards * 0.15) + 0.75
  end
end

--==============================================================================
-- planMoveBooks: pure decision layer for checkAndMoveBooks.
-- Scans zone 1 for complete books and computes target positions in side zones.
-- Returns {ok=false} if nothing to move, or
--   {ok=true, moves=[{book=obj, tPos={x,y,z}}]}
function planMoveBooks(sColor)
  local colorZones = getPlayerZones(sColor)
  if not colorZones then return {ok=false} end
  if not colorZones.zones[1] or not colorZones.zones[1].obj then return {ok=false} end
  if not colorZones.zones[2] or not colorZones.zones[2].obj then return {ok=false} end

  local decode = getPlayerDecodeDir(sColor)
  if not decode then return {ok=false} end
  local lateralAxis = decode[1]
  local direction   = decode[2]
  local depthAxis   = (lateralAxis == "x") and "z" or "x"
  local bookGap     = gv_CARD_SIZE.x + 0.5

  local function getZoneGeo(zi)
    local z = colorZones.zones[zi]
    if not z or not z.obj then return nil end
    local ok_p, zp = pcall(function() return z.obj.getPosition() end)
    local ok_s, zs = pcall(function() return z.obj.getScale()    end)
    if not ok_p or not ok_s or not zp or not zs then return nil end
    local latHalf = ((lateralAxis == "x") and zs.x or zs.z) / 2
    return {pos=zp, scl=zs, latHalf=latHalf}
  end

  local geo = {[2]=getZoneGeo(2), [3]=getZoneGeo(3)}

  local rightIdx, leftIdx
  if geo[2] and geo[3] then
    if geo[2].pos[lateralAxis] * direction >= geo[3].pos[lateralAxis] * direction then
      rightIdx, leftIdx = 2, 3
    else
      rightIdx, leftIdx = 3, 2
    end
  elseif geo[2] then
    if geo[2].pos[lateralAxis] * direction >= 0 then rightIdx = 2 else leftIdx = 2 end
  elseif geo[3] then
    if geo[3].pos[lateralAxis] * direction >= 0 then rightIdx = 3 else leftIdx = 3 end
  end

  local function getOccupied(zi)
    local occ = {}
    if not zi or not geo[zi] then return occ end
    local ok, objs = pcall(function() return colorZones.zones[zi].obj.getObjects() end)
    if not ok or not objs then return occ end
    for _, obj in ipairs(objs) do
      local ok_p, p = pcall(function() return obj.getPosition() end)
      if ok_p and p then table.insert(occ, p[lateralAxis]) end
    end
    return occ
  end

  local function isBlocked(lat, occupied)
    for _, occ in ipairs(occupied) do
      if math.abs(lat - occ) < bookGap * 0.9 then return true end
    end
    return false
  end

  local function slotLat(zi, n, rightFill)
    local g = geo[zi]; if not g then return nil end
    local innerEdge = rightFill
      and (g.pos[lateralAxis] - direction * g.latHalf)
       or (g.pos[lateralAxis] + direction * g.latHalf)
    local fillDir = rightFill and direction or -direction
    return innerEdge + fillDir * (n - 0.5) * bookGap
  end

  local function slotInBounds(zi, lat, rightFill)
    local g = geo[zi]; if not g then return false end
    local outerEdge = rightFill
      and (g.pos[lateralAxis] + direction * g.latHalf)
       or (g.pos[lateralAxis] - direction * g.latHalf)
    local fillDir = rightFill and direction or -direction
    return (lat - outerEdge) * fillDir <= 0
  end

  local function findSlot(zi, rightFill, occupied)
    if not zi then return nil end
    for n = 1, 50 do
      local lat = slotLat(zi, n, rightFill)
      if not lat or not slotInBounds(zi, lat, rightFill) then return nil end
      if not isBlocked(lat, occupied) then
        table.insert(occupied, lat)
        return lat
      end
    end
    return nil
  end

  local occRight = getOccupied(rightIdx)
  local occLeft  = getOccupied(leftIdx)

  -- Blue fills left zone first, then overflows to right.
  -- All other players fill right zone first, then overflow to left.
  local firstIdx,  firstFill,  firstOcc  = rightIdx, true,  occRight
  local secondIdx, secondFill, secondOcc = leftIdx,  false, occLeft
  if sColor == "Blue" then
    firstIdx,  firstFill,  firstOcc  = leftIdx,  false, occLeft
    secondIdx, secondFill, secondOcc = rightIdx, true,  occRight
  end

  local refGeo = geo[rightIdx] or geo[leftIdx]
  if not refGeo then return {ok=false} end
  local targetY = refGeo.pos.y - refGeo.scl.y / 2 + gv_CARD_SIZE.y

  local moves = {}
  local ok1, z1objs = pcall(function() return colorZones.zones[1].obj.getObjects() end)
  if not ok1 or not z1objs then return {ok=false} end
  for _, obj in ipairs(z1objs) do
    pcall(function()
      if not obj.is_face_down and obj.tag == "Deck" then
        local ok_q, qty = pcall(function() return obj.getQuantity() end)
        if ok_q and qty and qty >= 7 then
          local targetLat, slotZoneIdx
          targetLat = findSlot(firstIdx, firstFill, firstOcc)
          if targetLat then
            slotZoneIdx = firstIdx
          else
            targetLat = findSlot(secondIdx, secondFill, secondOcc)
            if targetLat then slotZoneIdx = secondIdx end
          end
          if targetLat then
            local zGeo = geo[slotZoneIdx]
            local tPos = {x=0, y=targetY, z=0}
            tPos[lateralAxis] = targetLat
            tPos[depthAxis]   = zGeo.pos[depthAxis]  -- center of the destination zone
            table.insert(moves, {book=obj, tPos=tPos})
          end
        end
      end
    end)
  end

  if #moves == 0 then return {ok=false} end
  return {ok=true, moves=moves}
end

--==============================================================================
-- executeMoveBooks: animation layer for checkAndMoveBooks.
function executeMoveBooks(plan)
  local delay = 0
  for _, move in ipairs(plan.moves) do
    local captured = move.book
    local tPos     = move.tPos
    Wait.time(function()
      pcall(function() captured.setPositionSmooth(tPos, false, false) end)
    end, delay)
    delay = delay + 0.4
  end
end

--==============================================================================
-- Scans zone 1 for complete books (face-up Deck with qty >= 7) and moves each
-- to the next available slot in the side zones (2 and/or 3).
-- The zone to the player's right fills left-to-right (inner edge outward).
-- The zone to the player's left fills right-to-left (inner edge outward).
function checkAndMoveBooks(sColor)
  local plan = planMoveBooks(sColor)
  if not plan.ok then return end
  executeMoveBooks(plan)
end

--==============================================================================
function layoutLargeSelection(sColor, vRot)
  -- directions based on the rotation of the hand object

  debug("layoutLargeSelection:","layoutsel")
  --debug("vrot = " .. dump(vRot),"layoutsel")
  local tOrigSelObjects = Player[sColor].getSelectedObjects()

  -- Check that we have SOMETHING to do
  if (not tOrigSelObjects or #tOrigSelObjects==0) then
    broadcastToColor("No items are selected.  Layout Canceled", sColor)
    return false
  end

  -- Check that everything is in this players score zone
  for k, v in pairs(tOrigSelObjects) do
    if not (objectInScoreZone(v, sColor)) then
      broadcastToColor("At least 1 of your selection is not in your zone (" .. v.getDescription() .. ").", sColor)
      broadcastToColor("Layout is not allowed.", sColor)
      return false
    end
  end
  itmp=30
  local iLastCount = #Player[sColor].getSelectedObjects() + 1
  local vNextPos = nil
  while itmp>0 and (#Player[sColor].getSelectedObjects()>0 and  #Player[sColor].getSelectedObjects()<iLastCount) do
    debug("Doing LayoutSubSelect.  objCount=" .. #Player[sColor].getSelectedObjects(), "layoutsel")
    iLastCount = #Player[sColor].getSelectedObjects()
    vNextPos = layoutSubSelection(sColor, vRot, Player[sColor].getSelectedObjects(), vNextPos)
    debug("nextpos = " .. dump(vNextPos), "layoutsel")
    itmp = itmp -1
  end
  if itmp==0 then
    log ("Had to crash out!!!!!!!!!!!!!!!!!!!!")
  end
  for k, v in pairs(tOrigSelObjects) do
    v.addToPlayerSelection(sColor)
  end

end
--==============================================================================
function layoutVerticalStack(sColor, vRot, oTarget, vDesiredPos)
  if (vDesiredPos) then
    debug("vDesirePos = " .. dump(vDesiredPos),"layoutsel")
  end
    -- Do the bulk of it.  First, find the left most and the highest


  -- Now find everything around it vertically
  local tCards = getCardsInMyVertical2(oTarget, vRot, sColor, nil)

  if isLayoutable(sColor, tCards) then
  --  debug ("tCards = " .. dump(tCards), "layoutsel")
    local oLeftMost, oHighest = findLeftMostAndHighest(tCards, vRot)
  --  debug ("oLeftMost = " .. oLeftMost.getDescription(),"layoutsel")
  --  debug ("oHighest = " .. oHighest.getDescription(),"layoutsel")

    if (not vDesiredPos) then
      if (gt_DECODE_DIR[vRot.y][1]=="x") then
        vDesiredPos = {x=oLeftMost.getPosition().x, y=oLeftMost.getPosition().y, z=oHighest.getPosition().z+oHighest.getScale().x/2}
      else
        vDesiredPos = {x=oHighest.getPosition().x+oHighest.getScale().x/2, y=oLeftMost.getPosition().y, z=oLeftMost.getPosition().z}
      end
    end
    vDropTop = spread3("s",sColor, 1, vDesiredPos, tCards)
    debug("vDropTop = " .. dump(vDropTop),"layoutsel")
  else
    debug("Vertical Selection was Not Layoutable.","layoutsel")
  end
  return vNextPos
end






--==============================================================================
function layoutSubSelection(sColor, vRot, tObjects, vDesiredPos)
  debug("enter layoutSubSelection ","layoutsel")
  -- Do the bulk of it.  First, find the left most and the highest
  local oLeftMost, oHighest = findLeftMostAndHighest(tObjects, vRot)
--  debug ("oLeftMost = " .. oLeftMost.getDescription(),"layoutsel")
--  debug ("oHighest = " .. oHighest.getDescription(),"layoutsel")

  -- Now find everything around it vertically
  local tCards = getCardsInMyVertical2(oLeftMost, vRot, sColor, tObjects)
--  debug ("tCards = " .. dump(tCards), "layoutsel")

  if (not vDesiredPos) then
    if (gt_DECODE_DIR[vRot.y][1]=="x") then
--      vDesiredPos = {x=oLeftMost.getPosition().x, y=oLeftMost.getPosition().y, z=oHighest.getPosition().z+oHighest.getScale().x/2}
      vDesiredPos = {x=oLeftMost.getPosition().x, y=oLeftMost.getPosition().y, z=oHighest.getPosition().z}
    else
--      vDesiredPos = {x=oHighest.getPosition().x+oHighest.getScale().x/2, y=oLeftMost.getPosition().y, z=oLeftMost.getPosition().z}
      vDesiredPos = {x=oHighest.getPosition().x, y=oLeftMost.getPosition().y, z=oLeftMost.getPosition().z}
    end
    debug("vDesirePos calculated as to = " .. dump(vDesiredPos),"layoutsel")
  else
    debug("vDesirePos passed in as = " .. dump(vDesiredPos),"layoutsel")
  end

  vDropTop = spread3("s",sColor, 1, vDesiredPos, tCards)
  debug("spread vDropTop = " .. dump(vDropTop),"layoutsel")

  debug("Direction = " .. gt_DECODE_DIR[vRot.y][1] .. " / " .. gt_DECODE_DIR[vRot.y][2], "layoutsel" )
  if (gt_DECODE_DIR[vRot.y][1]=="x") then
  --  vNextPos = {x=vDropTop.x + (gv_CARD_SIZE.x + 0.2)*gt_DECODE_DIR[vRot.y][2] , y=vDropTop.y, z=vDropTop.z+ gv_CARD_SIZE.x/2*gt_DECODE_DIR[vRot.y][2]}--+gv_CARD_SIZE.z/2*gt_DECODE_DIR[vRot.y][2]}
    vNextPos = {x=vDropTop.x + (gv_CARD_SIZE.x + 0.2)*gt_DECODE_DIR[vRot.y][2] , y=vDropTop.y, z=vDropTop.z}--+gv_CARD_SIZE.z/2*gt_DECODE_DIR[vRot.y][2]}
  else
    --vNextPos = {x=vDropTop.x + gv_CARD_SIZE.x/2*gt_DECODE_DIR[vRot.y][2], y=vDropTop.y, z=vDropTop.z - (gv_CARD_SIZE.x + 0.2)*gt_DECODE_DIR[vRot.y][2]}
    vNextPos = {x=vDropTop.x, y=vDropTop.y, z=vDropTop.z - (gv_CARD_SIZE.x + 0.2)*gt_DECODE_DIR[vRot.y][2]}
  end

  debug("#tcards="..#tCards,"layoutsel")
  for k, v in pairs(tCards) do
    v.removeFromPlayerSelection(sColor)
  end

  return vNextPos
end


function nearMe(vPos, vRot, sel, iHighLow, playerColor)
  -- iHighLow -1 to go high, 1 to go lower

  debug("Called nearMe","nearme")

  local fCardPadding = 0.2
  local cDecodeDir = { [0]={"x",-1}, [90]={"z",-1}, [180]={"x",1}, [270]={"z",1} }
  local fHighest = nil
  local oHighest = nil
  local fNearest = nil
  local oNearest = nil
  local alreadyCheckedGUIDs = {}

  -- if we've been passed a selection of cards, go ahead and ignore them
  -- they're the ones we're trying to place
  if (sel) then
    --    debug("#sel=".. #sel,"nearme")
    for i, oneSel in ipairs(sel) do
      debug("doing "..i,"nearme")
      --debug(sel[i],"nearme")
      debug(oneSel,"nearme")
      alreadyCheckedGUIDs[oneSel.getGUID()]=1
    end
  end

  -- detect a small rectange, extending to either side the width of a card turned on
  -- it's side (so the long side, plus the padding between cards,plus a tiny bit more to hit the card
  local detectorSize = { gv_CARD_SIZE.x*2 + (fCardPadding+0.1)*2, 1,0.5 }
  local t = {
    ["origin"] = vPos,
    ["direction"] = {0,1,0},
    ["type"] = 3, -- box
    ["size"] = detectorSize,
    ["orientation"] = {vRot.x, vRot.y, vRot.z},
    ["distance"] = .1,
    ["debug"] = gbDevGhostBoxes, -- make it visible for Now
  }
  local objs = Physics.cast(t)

  if (not objs) then
    debug("No cards left or right of " .. dump(vPos) .."were found.","nearme")
  end

  --local detectorSize = { gv_CARD_SIZE.x*2 + (fCardPadding+0.1)*2, 1,0.5 }
  for k, v in pairs(objs) do
    if (v.hit_object.tag=="Card" and not alreadyCheckedGUIDs[v.hit_object.getGUID()] ) then
      alreadyCheckedGUIDs[v.hit_object.getGUID()]=1
      local pos = v.hit_object.getPosition()
      debug("vry="..vRot.y,"nearme")
      debug("cdd="..cDecodeDir[vRot.y][1] .. " / " .. cDecodeDir[vRot.y][2],"nearme")

      -- Look to see if the cards we found were the ones that are part of this stack
      -- meaning that their relative Left/Right position is within 1 unit of the
      -- ray box itself... so skip those
      if ( (cDecodeDir[vRot.y][1]=="z" and math.abs(vPos.z-pos.z)>1)
           or (cDecodeDir[vRot.y][1]=="x" and math.abs(vPos.x-pos.x)>1) ) then
        --debug("vrot="..dump(vRot),"nearme")
        --debug("pos="..dump(pos),"nearme")

        --1234
        -- tCards, _ = getCardsInMyVertical3(v.hit_object, vRot, sColor, nil, nil, nil, nil, alreadyCheckedGUIDs)
        -- local _, oHighest = findLeftMostAndHighest(tCards, vRot)
        --1234

        local newOrigin = {  iif(vRot.y==90,pos.x-(detectorSize[1]/4),iif(vRot.y==270,pos.x+(detectorSize[1]/4),pos.x)),
                        pos.y,
                        iif(vRot.y==0,pos.z-(detectorSize[1]/4),iif(vRot.y==180,pos.z+(detectorSize[1]/4),pos.z))
                      }
        --debug("newOrigin="..dump(newOrigin),"nearme")
        local s = {
          ["origin"] = newOrigin,
          ["direction"] = {0,1,0},
          ["type"] = 3, -- box
          ["size"] = detectorSize,
          ["orientation"] = {vRot.x, vRot.y+90, vRot.z},
          ["distance"] = .02,
          ["debug"] = gbDevGhostBoxes, -- make it visible for Now
        }
        local stackObjs = Physics.cast(s)
        local fHighest=nil
        for kStackCard, vStackCard in pairs(stackObjs) do
          if (vStackCard.hit_object.tag=="Card") then -- and (not playerColor  or  objectInScoreZone(vSTackCard.hit_object, playerColor)) then
            --debug("in range: " .. vStackCard.hit_object.getDescription(),"nearme")
            --debug("zpos=".. vStackCard.hit_object.getPosition().z,"nearme")
            local fRelHeight=iif(cDecodeDir[vRot.y][1]=="x",vStackCard.hit_object.getPosition().z,vStackCard.hit_object.getPosition().x)

            if (not fHighest or iif(cDecodeDir[vRot.y][2]==1,(fHighest<fRelHeight),(fHighest>fRelHeight))) then
              fHighest = fRelHeight
              oHighest = vStackCard.hit_object
            end
          end
        end

        -- we have a stack and have found the highest of it.  Now we check
        -- that against any other stacks (read: the other side of this particular
        -- spread may have cards too) to see which is nearest at that is the
        -- one we'll align to
        if (fHighest and (not fNearest or
            iif(cDecodeDir[vRot.y][2]==1*iHighLow,
                (fNearest<math.abs(fNearest-fHighest)),
                (fNearest>math.abs(fNearest-fHighest))))) then
          --debug("setting nearesttotarget to " .. oHighest.getDescription(),"nearme")
          fNearest = fHighest
          oNearest = oHighest
        end
        debug("Highest == " .. oHighest.getDescription(), "nearme")
      end
      if (oNearest) then
        debug("NearestToTarget="..oNearest.getDescription(),"nearme")
      end
    end
    --    v.hit_object.flip()
  end

  local cardGap = gv_CARD_SIZE.x + (fCardPadding)
  -- if we found a nearest... work it out..
  if oNearest then
    debug("official nearest = " .. oNearest.getDescription(),"nearme")
    local posON = oNearest.getPosition()
    local posNew = posON
    if (cDecodeDir[vRot.y][1]=="x") then
      if (vPos.x > posNew.x) then
        posNew.x = posON.x + cardGap
      else
        posNew.x = posON.x - cardGap
      end
    else
      if (vPos.z > posNew.z) then
        posNew.z = posON.z + cardGap
      else
        posNew.z = posON.z - cardGap
      end
    end
    debug("returning new pos: ".. dump(posNew),"nearme")
    -- if we have a nearest (which is actually the highest of the nearest stack)
    -- then return a target position based on that object
    return posNew
  end
  -- if we reached here, we didn't have a "nearest" so we'll just say
  -- drop this thing where you already are (vPos)
  debug("returning orig pos: ".. dump(vPos),"nearme")
  return vPos
end






function onObjectSpawn(obj)
    obj.addContextMenuItem('Layout Pretty', function(x) spread3("s",x,1) end, false)
    obj.addContextMenuItem('Layout TowardCam', function(x) spread3("s",x,0) end, false)
    -- Card-only items: do NOT add these to all objects — hand zone scripting zones
    -- break if they receive more than 3 items total (2 from here + 1 from onLoad).
    if obj.tag == "Card" then
      obj.addContextMenuItem('Layout Hand', function(playerColor)
        local _, rank, _ = cardDeets(obj)
        layoutHandRank(playerColor, rank)
      end, false)
    end
end

function findInTable2 (tab, target)
  if (tab) then
    for i, v in ipairs(tab) do
      if v.guid==target then
        return i
      end
    end
  end
  return -1
end

function findInTable(tab, target)
  if (tab) then
    for i, v in ipairs(tab) do
      if v==target then
        return i
      end
    end
  end
  return -1
end

function objGuid(obj)
  if (obj) then
    --log("leave = " .. obj.tag)
    if obj.guid then
      return obj.guid
    else
      local g = obj.getGUID()
      return g
    end
  else
    return nil
  end
end

function playerZoneCheck(sColor, oTheObject)
  if (Player[sColor] and Player[sColor].seated) then
    playerZoneBoundary(sColor, oTheObject)
    if (oTheObject.tag=="Card") then
      queueFootNoteCheck(sColor)
    end
  end
end

function onObjectLeaveScriptingZone(zone, leave_object)
  if (leave_object.tag=="Deck") then
    for _, oneCard in ipairs(leave_object.getObjects()) do
      onObjectLeaveScriptingZone(zone, oneCard)
    end
    return
  end
  if (zone.guid == ZONE_DISCARD) then
    local iPos = findInTable(tableDiscard, objGuid(leave_object))
    if (iPos>-1) then
     table.remove(tableDiscard,iPos);
    end
    debug('Leave script zone ' .. leave_object.guid,"discard")
    tablepush(fromdiscard, leave_object.guid)
    Wait.time(function() tablepop(fromdiscard,leave_object.guid) end,2.0,0)
--    guidJustLeftDiscard = leave_object.guid
  end
--  log (leave_object.tag .. " leaving: " .. leave_object.guid)


  if (zone.guid == ZONE_WHITE) then
    playerZoneCheck("White",leave_object)
  elseif (zone.guid == ZONE_RED) then
    playerZoneCheck("Red",leave_object)
  elseif (zone.guid == ZONE_GREEN) then
    playerZoneCheck("Green",leave_object)
  elseif (zone.guid == ZONE_BLUE) then
    playerZoneCheck("Blue",leave_object)
  end
end

function queueFootNoteCheck(sColor)
  if (not gbDealing) then
    if (not playerStuff[sColor].bQueuedFootNoteCheck) then
      playerStuff[sColor].bQueuedFootNoteCheck = true
      Wait.time(function () checkFootNote(sColor); playerStuff[sColor].bQueuedFootNoteCheck=false end,0.5)
    end
  end
end

function announceAll(sMsg)
--  if not bMaskActions then
    printToAll(sMsg)
--  end
end

function setReminder(sColor)
--  announceAll("SR:dc=" ..playerStuff[sColor].drawcount)
  local sOut = " "
  sOut = sOut .. playerStuff[sColor].footReminder
  if (playerStuff[sColor].drawcount>0) then
    if sOut == " " then
      sOut = "Drew " .. playerStuff[sColor].drawcount
    else
      sOut = sOut .. " \nDrew " .. playerStuff[sColor].drawcount
    end
  end
  if (playerStuff[sColor].drawcountdisc>0) then
    if sOut == " " then
      sOut = "Drew " .. playerStuff[sColor].drawcountdisc .. " (from discard)"
    else
      sOut = sOut .. " \nDrew " .. playerStuff[sColor].drawcountdisc .. " (from discard)"
    end
  end
  textFootNotes[sColor].TextTool.setValue(sOut)
end

function addToDrawCount(sColor, iCnt, bDiscard)
  if sColor != "White" then
    playerStuff["White"].drawcount=0
    playerStuff["White"].drawcountdisc=0
  end
  if sColor != "Green" then
    playerStuff["Green"].drawcount=0
    playerStuff["Green"].drawcountdisc=0
  end
  if sColor != "Blue" then
    playerStuff["Blue"].drawcount=0
    playerStuff["Blue"].drawcountdisc=0
  end
  if sColor != "Red" then
    playerStuff["Red"].drawcount=0
    playerStuff["Red"].drawcountdisc=0
  end
  --announceAll("tick"..playerStuff[sColor].drawcount)

  if bDiscard then
    playerStuff[sColor].drawcountdisc = playerStuff[sColor].drawcountdisc + iCnt
  else
    playerStuff[sColor].drawcount = playerStuff[sColor].drawcount + iCnt
  end
end

function playerZoneBoundary (player_color, obj)
  if not gbInitializing then

    if not gbDealing then
      local name = coolName(player_color)
      if tablepop(fromdeck,obj.guid) then
        if (not playerStuff[player_color].bMaskActions) then
--          announceAll("dc="..playerStuff[player_color].drawcount)
          if (playerStuff[player_color].drawcountqueued==false) then
            playerStuff[player_color].drawcountqueued=true
            Wait.time(function()
                --announceAll(name .. " drew " .. playerStuff[player_color].drawcount);
                setReminder("White")
                setReminder("Green")
                setReminder("Blue")
                setReminder("Red")
                playerStuff[player_color].drawcountqueued=false;
                end, 2)
          end
          announceAll(name .. " drew 1");
          addToDrawCount(player_color,1,false)

--          playerStuff[player_color].drawcount = playerStuff[player_color].drawcount+1;
--          announceAll(name .. " drew 1")
        end
      else
        if tablepop(fromdiscard,obj.guid) then
          if (not playerStuff[player_color].bMaskActions) then
            if (playerStuff[player_color].drawcountqueued==false) then
              playerStuff[player_color].drawcountqueued=true
              Wait.time(function()
                  --announceAll(name .. " drew " .. playerStuff[player_color].drawcountdisc .. " (from discard)");
                  setReminder("White")
                  setReminder("Green")
                  setReminder("Blue")
                  setReminder("Red")
                  playerStuff[player_color].drawcountqueued=false;
--                  playerStuff[player_color].drawcountdisc=0;
                end, 1)
            end
            announceAll(name .. " drew 1 (from discard)");
            addToDrawCount(player_color,1,true)
--            playerStuff[player_color].drawcountdisc = playerStuff[player_color].drawcountdisc+1;
--            announceAll(name .. " drew 1 (from discard)")
          end
        end
      end
    end

    -- local lDesc, lGuid, lQty
    -- if type(obj)=="table" then
    --   lDesc = obj.description
    --   lGuid = obj.guid
    --   lQty = 1
    -- else
    --   lDesc = obj.getDescription()
    --   lGuid = obj.getGUID()
    --   lQty = obj.getQuantity()
    -- end
    -- debug("val=" .. lDesc)
    -- local iPos = findInTable2(tablePlayerCards[player_color],lGuid)
    -- if iPos==-1 then
    --   local iScore, sDesc = scoreTarget(obj)
    --   --log("Inserting.1." .. obj.getDescription())
    --   table.insert(tablePlayerCards[player_color], {guid= lGuid, isdeck=(lQty>1), score= iScore, in_hand=true,desc= sDesc})
    --   giInsertCount = giInsertCount + 1
    --   debug(giInsertCount .. " zb (" .. lGuid .. ") " .. sDesc)
    -- else
    --   tablePlayerCards[player_color][iPos].in_hand = inHand
    -- end
    --tableDump(tablePlayerCards)
  end
end

function onObjectEnterScriptingZone( zone,  enter_object)
--end
--function dummy()
  if (zone.guid == ZONE_DISCARD) then
    --local g = enter_object.getGUID()
    if (enter_object and (enter_object.tag=="Card" or enter_object.tag=="Deck")) then
      tablepush(fromdiscard, enter_object.guid)
      table.insert(tableDiscard, enter_object.guid)
    end
  end
  if (zone.guid == ZONE_WHITE) then
    playerZoneCheck("White", enter_object)
  elseif (zone.guid == ZONE_RED) then
    playerZoneCheck("Red", enter_object)
  elseif (zone.guid == ZONE_GREEN) then
    playerZoneCheck("Green", enter_object)
  elseif (zone.guid == ZONE_BLUE) then
    playerZoneCheck("Blue", enter_object)
  end
end

function tableDump(tab)
  for k, playersCards in pairs(tab) do
    debug(#playersCards .. " ".. k .. " **********************************")
    for i, card in ipairs(playersCards) do
      debug("guid = " .. card.guid .. "  - score= " .. card.score .. "  - inhand=" .. tostring(card.in_hand) .. "  - desc = " .. card.desc)
    end
  end
end


function enteredAndWaited(bag, oGuid, oTag, oDesc)
  return
end
-- function hide001 ()
--   debug("bag: "  .. " - g:" .. bag.getGUID() .. " - d:" .. bag.getDescription())
-- --  debug("bag: " .. bag.tag       .. " - g:" .. bag.getGUID() .. " - d:" .. bag.getDescription())
--     debug("obj: " .. oGuid .. " (" .. oTag   ..  ") - "  .. oDesc)
--     debug("Tock")
--
--     local lScore, lDesc = scoreTarget(bag)
--     debug("Tick")
--       bag.setDescription(lDesc)
--
--       -- If the deck isn't already owned
--       local sDeckPlayer, iBagPos = findUsedThing(tablePlayerDecks, bag.getGUID())
--       if (not sDeckPlayer ) then
--         -- Look for the card in the table of owned cards
--         debug("Looking for ".. oGuid .. " - d:" .. oDesc)
--         local sPlayer = findUsedThing(tablePlayerCards, oGuid)
--         -- Since deck isn't owned, if we found a player for the card add this deck to that player
--         if (sPlayer) then
--           debug("card belongs to " .. sPlayer)
--           debug("Inserting.2." .. bag.getDescription())
--           table.insert(tablePlayerDecks[sPlayer],{guid=bag.getGUID(), score=lScore, desc=lDesc})
--         end
--       else
--         tablePlayerDecks[sDeckPlayer][iBagPos].score = lScore
--         tablePlayerDecks[sDeckPlayer][iBagPos].desc = lDesc
--       end
--
--       debug("Decks ----------------")
--       --tableDump(tablePlayerDecks)
-- end

function onObjectPickUp(colorName, object)
    debug(colorName .. " picked up " .. object.getGUID())
    if tablepop(fromdiscard,object.guid) then
      local name = colorName
      if (Player[colorName].steam_name) then
        name = Player[colorName].steam_name
      end
      announceAll(name .. " drew 1 (from discard)")
    end

end

function onObjectLeaveContainer(bag, obj)
  debug("Object " .. obj.guid .. " left container " .. bag.guid, "discard")
  if (objectInZone(obj, obj_Zone_Discard)) then
    tablepush(fromdiscard,obj.guid)
    Wait.time(function() tablepop(fromdiscard,obj.guid) end,2.0,0)
  end
  if not gbInitializing and mainDeck then
    -- local player, idx = findUsedThing(tablePlayerDecks, bag.getGUID())
    --log ("b: " .. bag.guid)
    --log ("md: " ..mainDeck.getGUID())
    --log ("#fd:" .. #fromdeck)

    if (bag.guid == mainDeck.guid) then
      tablepush(fromdeck, obj.guid)
      Wait.time(function() tablepop(fromdeck,obj.guid) end,2.0,0)
    end

  --   if (player) then
  --   --  debug("... belonged to " .. player)
  --     local lScore, lDesc = scoreTarget(bag)
  --     bag.setDescription(lDesc)
  --     tablePlayerDecks[player][idx].score = lScore
  --     tablePlayerDecks[player][idx].desc = lDesc
  -- --    table.remove(tablePlayerDecks[player],idx)
  --   end
    --debug("Decks ----------------")
    --tableDump(tablePlayerDecks)
  end
end


-- function onObjectDestroy(obj)
--   if not gbInitializing then
--     debug("destroy: ".. obj.guid .. " tag="..obj.tag)
--     if (obj.tag == "Deck") then
--       local player, idx = findUsedThing(tablePlayerDecks, obj.getGUID())
--       if (player) then
--         table.remove(tablePlayerDecks[player], idx)
--       end
--     end
--   end
-- end

function onObjectEnterContainer(bag, obj)
  if (gbSpreading) then
    debug('Skipped one')
  end
  if not gbInitializing  and not gbSpreading then
    local lGuid = obj.getGUID()
    local lTag = obj.tag
    local lDesc = obj.getDescription()
    --Wait.time(function() enteredAndWaited(bag,lGuid,lTag, lDesc)  end, 0.5)
  end
end

-- function findUsedThing(tbl, target)
--   local sPlayer = ""
--   for sPlayer, playersDecks in pairs(tbl) do
--     --debug("checking player " .. sPlayer)
--     if (playersDecks) then
--       --debug("payersDecks type = " .. type(playersDecks))
--       for i, oneDeck in ipairs(playersDecks) do
--           debug("   against ".. oneDeck.guid)
--           if (oneDeck.guid==target) then
--             debug("found")
--             return sPlayer, i
--           end
--       end
--     end
--   end
--   return nil, nil
-- end

function playerName(player_color)
  local name = player_color
  if (Player[player_color].steam_name) then
    name = Player[player_color].steam_name
  end
  return name
end

-- =============================================================================
function objectInZone(obj, zone)
  local zoneObjects = shallowCopy(zone.getObjects())
  for k, oneCard in pairs(zoneObjects) do
    if (oneCard.guid == obj.guid) then
      return true
    end
  end
  return false
end

-- =============================================================================
function AssessLayoutableForOne(obj, bIsLayoutable, sDeckType, iWildCount)
  local shortColor, shortName, _ = cardDeets(obj)
  debug ("Assessing " .. shortName .. " DT:" .. sDeckType,"Assessment" )
  if ((sDeckType != shortName) and (string.match(shortName,"[3456789]") or shortName == "10" or shortName == "Jack" or shortName == "Queen" or shortName == "King" or shortName == "Ace")) then
    if ((not sDeckType) or (sDeckType == "")) then
      sDeckType = shortName
    else
      debug ("fail b/c DeckType(".. sDeckType ..") <> shortName(".. shortName .. ") ","Assessment")
      bIsLayoutable = false
    end
  end
  if (shortName == "2" or shortName == "Joker") then
    iWildCount = iWildCount+1
    if iWildCount>2 then
      if ((not sDeckType) or (sDeckType == "")) then
        sDeckType = "Wild"
      else
        if (sDeckType != "Wild") then
          debug ("fail b/c >2 wild and decktype <> wild or blank","Assessment")
          bIsLayoutable = false
        end
      end
    end
  end
  return bIsLayoutable, sDeckType, iWildCount
end

-- =============================================================================
function playDiscardSound()
  if (soundCube and gbPlaySounds) then
    soundCube.AssetBundle.playTriggerEffect(giDiscardSound)
  end
end


-- =============================================================================
function isLayoutable(playerColor, tCards)
sCardType = ""
local sDeckType = ""
local iWildCount = 0
local bIsLayoutable = true
local itemCount = 0
  debug("Start Check","prob1")
  local sel = iif(tCards, tCards, Player[playerColor].getSelectedObjects())

  for i=1,#sel do
    local item=sel[i]
--    log("checking item.tag = " .. item.tag)
    if (item.tag == "Deck") then
      local deckCards = shallowCopy(item.getObjects())
      for k, oneCard in pairs(deckCards) do
        itemCount = itemCount + 1
        bIsLayoutable, sDeckType, iWildCount = AssessLayoutableForOne(oneCard,bIsLayoutable, sDeckType, iWildCount)
        if not (bIsLayoutable) then
          debug("End Check","prob1")
          return false
        end
      end
    elseif (item.tag == "Card") then
      itemCount = itemCount + 1
      bIsLayoutable, sDeckType, iWildCount = AssessLayoutableForOne(item,bIsLayoutable, sDeckType, iWildCount)
      if not (bIsLayoutable) then
        debug("End Check","prob1")
        return false
      end
    else
--      log("Error.. assessing layout and item is type/tag: " .. item.tag)
      bisLayoutable=false
      debug("End Check","prob1")
      return false
    end
  end

  if itemCount <= 2 then
--    log ("fail b/c itemcount <=2")
    -- if false then
    --   tCards = layoutVerticalStack(playerColor, obj_Zone[playerColor].getRotation(), sel[1], nil)
    --   if tCards then
    --     debug("tCard cnt = "..#tCards,"prob1")
    --   else
    --     debug("no tCards","prob1")
    --   end
    --   -- this should really check the contents, not just count
    --   -- may be a problem later
    --   if (tCards and #tCards != #sel) then
    --     for k, v in pairs(tCards) do
    --       v.addToPlayerSelection(playerColor)
    --     end
    --     return isLayoutable(playerColor)
    --   end
    -- end
    bIsLayoutable = false
    debug("End Check","prob1")
    return false
  end
  if (itemCount >6 and #sel==1) then
--    log ("fail b/c itemcount >2 and selcount =1")
--   This means it's one deck of > 6 cards.. leave it alone
    bIsLayoutable = false
    debug("End Check","prob1")
    return false
  end

  debug("End Check","prob1")
  return bIsLayoutable
end


-- =============================================================================
function getNonWild(tCards, oElseCard)
  for _, oSelCard in pairs(tCards) do
    local sShortColor, sShortName, sShortType = cardDeets(oSelCard)
    if (sShortColor != "Wild") then
      return oSelCard
    end
  end
  if (oElseCard) then
    return oElseCard
  end
  return nil
end


-- =============================================================================
function queueSpread (playerColor, oDropped)
  local tCards={}
  local bFoundDifferentCard=false
  local vDesiredPos = nil

  local sel = Player[playerColor].getSelectedObjects()
  -- we either want to have a card being dropped or a whole Selection
  -- if we have neither, then bail out
  debug("oDropped = "..iif(oDropped, oDropped.getDescription(),"none"),"queuespread")
  debug("sel = "..dump(sel),"queuespread")
  if (not oDropped and #sel==0) then
    debug("nothing selected..","prob1")
    playerStuff[playerColor].bSpreadQueued = false
    return
  end

  -- If we do have a selection and it's huge, its' not likely
  -- meant for laying out (more like emptying a hand during debug)
  -- so bail out
  if (#sel>15) then
    debug("Big drop, just drop them","prob1")
    playerStuff[playerColor].bSpreadQueued = false
    return
  end

  -- for the moment, we've abandoned the whole "make sure they're not
  -- still moving" part.
  bNoMovement=true
  if (false) then
    for i=1,#sel do
      local item=sel[i]
      x = item.getVelocity()
      if (x.x!=0 or x.y!=0 or x.z!=0) then
        bNoMovement = false
        debug("still moving..","prob1")
        break
      end
    end
  end

  -- get a representative card from all the selected cards that ISN'T wild
  -- if none match (all wild?) then just return the one we know about.
  oDropped = getNonWild(sel, oDropped)

  -- for the moment, this is always true
  if (bNoMovement) then
    debug("done moving..","prob1")

    -- Get the rotation of the hand zone of this player color
--    local vRot = obj_Zone[playerColor].getRotation()
    local vRot = getPlayerRotationFromObject(oDropped)

    -- find cards within the vertical of the dropped card (or selection if oDropped is nill)
    -- this returns the list of cards found up to and NOT including any cards with
    -- a different non-wild value.
    -- crd-madelocal
    tCards, bFoundDifferentCard = getCardsInMyVertical3(oDropped, vRot, playerColor, nil, nil, Player[playerColor].getPointerPosition())

    -- tCards are all the cards in the vertical, but we're possibly dropping a few
    -- cards that are horizontally laid out, like from a hand.  so we need to add all
    -- the currently selected cards to tCards before we spread
    for _, oSelCard in pairs(sel) do
      if (tablefind(tCards,oSelCard)==-1) then
        table.insert(tCards,oSelCard)
      end
    end

    -- if we did find a "stopper" card, drop a debug but keep going
    if (bFoundDifferentCard) then
      debug("Found Different Card!!!", "queuespread")
    end

    -- just for debugging, let's dump out all the cards that were returned
    -- by the vertical check
    for i, oCard in ipairs(tCards) do
      debug("tCards[".. i .. "] = " .. oCard.getDescription(),"queuespread")
    end

    -- if we found a different card, let's not try and merge these two
    -- sets.. we don't want 5's mixed with the 10's.
    -- also, if we have no cards in the vertical at all, there's no point
    -- so we'll also skip out.
--    if tCards and not bFoundDifferentCard then
    if tCards then
      -- check to see if anything is in the vertical that's not also in the
      -- current selection (the set being dropped).  If there IS, then we're
      -- dropping on an existing stack and we should line up with where it
      -- already is.  Otherwise, we drop at the mousepointer because everything
      -- in tCards was already in our selection
      local tTableCards = {}
      local bDroppingOnCard = false
      -- start a loop through all the cards returned by the vertical check
      for _, oCard in ipairs(tCards) do
        debug("looping through vert found card: " .. oCard.getDescription(), "queuespread")
        local bCardInSel = false
        -- for each of the cards in the vertical check, look to see if it's
        -- in the current selection.  If it is, set a flag and break out
        -- of the inner loop (no reason to keep looking)
        for _, oSel in ipairs(sel) do
          debug("checking vs selected card: " .. oSel.getDescription(), "queuespread")
          if (oCard.getGUID()==oSel.getGUID()) then
            debug (oCard.getDescription() .. " = " .. oSel.getDescription() .. " so Breaking Loop","queuespread")
            bCardInSel = true
            break
          end
        end

        -- if this card wasn't in the selection group, then we know that
        -- we're dropping on some existing cards on the table, so set a
        -- flag to tell us that.  Also, let's keep track of a table of
        -- "tablecards" for all the cards that are already laid out
        if (not bCardInSel) then
          debug("Dropping on a card: " .. oCard.getDescription(),"queuespread")
          bDroppingOnCard = true
          table.insert(tTableCards, oCard)
          -- no break, because we want to fill up tTableCards
        end
      end
      -- Simple debug.. call out if we're not dropping on any card
      if (not bDroppingOnCard) then
        debug("Not dropping on any card","queuespread")
      else
        -- Ok, so we're dropping on some existing cards.. let's find the
        -- highest and most left of those cards (we really only care about
        -- the highest)
        local oLeftest, oHighest = findLeftMostAndHighest(tTableCards, vRot)

        -- if we didn't find one, that's gotta be an error, log it.
        if (not oHighest) then
          log ("ERROR: Looked for the highest card to spread but didn't find one?")
        else
          -- we did find one.. so get its position, then add some to the height
          -- because the position is center of the card but we're looking for
          -- a spot higher.  This is more trial and error than math.  advancing it
          -- by the value of 1 seems to work. We use addRelativePos(vert..) because
          -- what is "up" for each player is different. The function figures that out.
          vDesiredPos = oHighest.getPosition()
          --vDesiredPos = addRelativePos("vert", vDesiredPos, vRot, 1)
        end

        -- loop through EVERY card in the vertical and make sure it's part
        -- of the player's selection.
        Player[playerColor].clearSelectedObjects();
        if false then
          for _, oCard in pairs(tCards) do
            debug("adding to selection: ".. oCard.getDescription(),"queuespread")
            oCard.addToPlayerSelection(playerColor)
          end
          if (gtDebugFlags["queuespread"]) then
            local tDbgSel = Player[playerColor].getSelectedObjects()
            debug("All cards in updated selection group:","queuespread")
            for _, oOne in pairs(tDbgSel) do
              debug("    " .. oOne.getDescription(),"queuespread")
            end
          end
        end -- if false
      end
    end

    -- So, now the selection has everything we want to spread out in it,
    -- whether there were table cards or no table card, vertical-hits or none.
    -- If we don't yet have a desired position (top of the existing table cards
    -- if we have them), then let's just drop the cards where the mouse pointer is.
    if not vDesiredPos then
      vDesiredPos = Player[playerColor].getPointerPosition()--1234
      vDesiredPos = addRelativePos("vert", vDesiredPos, vRot, gfDropShift)
    end

    -- Almost there.. so let's make sure that the current selection is
    -- "layoutable" (not a mixed set, etc..) and, if so, spread it.
    if (isLayoutable(playerColor, tCards)) then
      -- if they're holding down the "mask" button, then we want them laid out
      -- toward a different player.. otherwise, toward us.
      if (not playerStuff[playerColor].bMaskActions) then
      --  spread3("s",playerColor,0)
      debug("spread - 1","queuespread")
      debug(">>>>>>spreading - 1 : " .. dump(tCards),"vertical2")
        -- do the spread, for this color, dropping it at our desired position
        -- then clear the semaphores so they can queuespread again
         Wait.time(function()
              spread3("s",playerColor,1,vDesiredPos, tCards);
              playerStuff[playerColor].bSpreadQueued = false;
              debug("clearing selected objects for " .. playerColor,"queuespread");
              Player[playerColor].clearSelectedObjects();
            end, 0.1)
      else
      --  spread3("s",playerColor,1)
        debug("spread - 0","queuespread")
        -- do the spread, for this color, dropping it at our desired position,
        -- then clear the semaphores so they can queuespread again
        Wait.time(function()
              spread3("s",playerColor,0,vDesiredPos,tCards);
              playerStuff[playerColor].bSpreadQueued = false;
              debug("clearing selected objects for " .. playerColor,"queuespread");
              Player[playerColor].clearSelectedObjects();
            end, 0.1)
      end
    else
      -- if it wasn't layoutable, then let's just end here.
      -- clear the semaphores for being mid-spread so that
      -- they can queue up another if they need
      playerStuff[playerColor].bSpreadQueued = false

    end
  else
    -- if we're still moving (currently, not possible as we've got an "if true" above), wait for .2sec and check again
    Wait.time(function() queueSpread(playerColor, oDropped) end,0.1)
  end
end

-- =============================================================================
-- Returns true if sColor still has a face-down foot pile in their score zones.
function playerHasFoot(sColor)
  local czFoot = getPlayerZones(sColor)
  for _, scoreZone in ipairs(czFoot and czFoot.zones or {}) do
    for _, obj in ipairs(scoreZone.obj.getObjects()) do
      if (obj.tag == "Deck" or obj.tag == "Card") and obj.is_face_down then
        return true
      end
    end
  end
  return false
end

-- =============================================================================
function checkFootNote(sColor, iCheckCount)
  if (not iCheckCount) then
    iCheckCount = 0
  end
  local handCards = Player[sColor].getHandObjects()
  if (#handCards<4) then
    if (not giPlayerCount) then
      local p = getSortedSeatedPlayers()
      giPlayerCount = #p
    end
    local bFootExists = playerHasFoot(sColor)
    if (bFootExists)  then
      if (playerStuff[sColor].bShowFootNotes) then
        playerStuff[sColor].footReminder="Remember Foot"
        broadcastToColor("Don't forget your foot",sColor)
        setReminder(sColor)
        --textFootNotes[sColor].TextTool.setValue("Remember Foot")
        textFootNotes[sColor].TextTool.setFontColor("Yellow")
      end
    else -- else
      playerStuff[sColor].footReminder=""
      if (#handCards==0) then
        local _, tBookCount = countScoreInternal()
        log("tBookCount=".. dump(tBookCount))
        if (tBookCount[sColor][gi_RED_BOOK_SCORE]>1 and tBookCount[sColor][gi_BLACK_BOOK_SCORE]>1) then
          soundCube.AssetBundle.playTriggerEffect(13)
          broadcastToAll(coolName(sColor) .. " has gone out!!","Yellow")
          gbHandWonPause = true
          gbFinishFlag = true
          recordScores()
          Wait.time(function() gbFinishFlag=false; setCardDecal(); end, 10.0)
          Wait.time(function() gbHandWonPause=false end, 5.0)
          finishFlag()
        else
          if (iCheckCount<5) then
            Wait.time(function () checkFootNote(sColor, iCheckCount+1) end, 1.0)
          end
        end
      end
      setReminder(sColor)
--      textFootNotes[sColor].TextTool.setValue(" ")
      textFootNotes[sColor].TextTool.setFontColor("Yellow")
    end
  else
    setReminder(sColor)
--    textFootNotes[sColor].TextTool.setValue(" ")
    textFootNotes[sColor].TextTool.setFontColor("Yellow")
  end
end


function onObjectDrop(player_color, dropped_object)
     -- if it's inside the discard zone, center it over the discard pile
    if (obj_Zone_Discard) then
      if (objectInZone(dropped_object, obj_Zone_Discard)) then
        dropped_object.setPosition(obj_Zone_Discard.getPosition())
      end
      if (playerStuff[player_color].bAutoLayout) then
        if (not objectInZone(dropped_object, obj_Zone_Discard)
           and (not (objectInZone(dropped_object, obj_Zone_Green)
                or objectInZone(dropped_object, obj_Zone_White)
                or objectInZone(dropped_object, obj_Zone_Blue )
                or objectInZone(dropped_object, obj_Zone_Red)))) then
          if (not playerStuff[player_color].bSpreadQueued and not playerStuff[player_color].bMaskActions) then
            playerStuff[player_color].bSpreadQueued = true
            -- only queue up if the object is a card
            if (dropped_object.tag == "Card") then
              debug("queueing spread","queuespread")
              queueSpread(player_color,dropped_object)
            else
              debug("skipping queueing spread, dropped obj is not a card (" .. dropped_object.tag .. ")","queuespread")
              playerStuff[player_color].bSpreadQueued = false
            end
          else
            debug("skipping queueing spread, player.bSpreadQueued = " .. iif(playerStuff[player_color].bSpreadQueued,"true","false"),"queuespread")
            playerStuff[player_color].bSpreadQueued = false
          end
        end
      end
    end

    local iPos = findInTable(tableDiscard, dropped_object.getGUID())
    if (iPos>-1) then
      onDiscardComplete(player_color, dropped_object)
    end
end

-- All side-effects that must fire when a card is discarded, whether by a player
-- dropping it manually or by script (executeTurnPlan).  Called from onObjectDrop
-- for manual discards and explicitly from executeTurnPlan for scripted ones.
function onDiscardComplete(sColor, discardedObj)
  if not sColor or not discardedObj then return end
  local iPos = findInTable(tableDiscard, discardedObj.getGUID())
  if iPos == -1 then return end   -- card not in discard zone yet; guard re-entry
  if (not playerStuff[sColor].bMaskActions) then
    local name = coolName(sColor)
    textDiscardValue.TextTool.setValue(name)
    textDiscardValue.TextTool.setFontColor(sColor)
    if (gb_USE_TURNS and sColor==Turns.turn_color) then
      Turns.turn_color=Turns.getNextTurnColor()
    end
    announceAll(name .. " discarded ")
    setCardDecal()
    checkFootNote(sColor)
    playDiscardSound()
  end
  if discardedObj.tag == "Card" then
    tablepush(fromdiscard, discardedObj.guid)
  else
    local deckCards = shallowCopy(discardedObj.getObjects())
    for _, oneCard in pairs(deckCards) do
      tablepush(fromdiscard, oneCard.guid)
    end
  end
  table.remove(tableDiscard, iPos)
end


function scoreCard(oneCard)
  local lDesc = ""
  local lGuid = ""
  local scr=0
  --log("type = "..type(oneCard))
  if (type(oneCard)=="table") then
    lGuid = oneCard.guid
    lDesc = oneCard.description
  else
    lGuid = oneCard.getGUID()
    lDesc = oneCard.getDescription()
  end
  --log("scoring: ".. lGuid .. " (".. type(oneCard) .. ")")
  _, shortName, _ = cardDeets(oneCard)
--  log("shortname = " .. shortName)
  --shortName = string.match(oneCard.description,"[%a%d]*")
  if (string.match(shortName,"[4567]")) then
    scr = 5
  elseif shortName=="2" or shortName=="Ace" then
    scr=20
  elseif (shortName=="3") then
    if (lDesc == "3 of Clubs" or lDesc=="3 of Spades") then
      scr = 5
    else
        scr = giRed3Penalty
    end
  elseif (shortName=="8" or shortName=="9" or shortName=="10" or shortName=="Jack" or shortName=="Queen" or shortName=="King"  ) then
    scr = 10
  elseif (shortName=="Joker") then
    scr = 50
  else
    debug("ERROR: CAN NOT SCORE " .. oneCard.tag .. ": g:" .. oneCard.getGUID() .. " - d:" .. oneCard.getDescription())
    scr = 0
  end
  return scr, lDesc
end

function hoverTroll()
  playerList = Player.getPlayers()
  for _, playerReference in ipairs(playerList) do
    hObj = playerReference.getHoverObject()
    if (hObj and hObj.getQuantity()>1) then
      dckCnt, dckDesc, _ = scoreTarget(hObj)
      hObj.setDescription(dckDesc)
    end
  end
  return 1
end

function scoreTarget(target)
  local bInconsistentDeck = false
  local guidGotBlack = nil
  local guidGotRed = nil
  local guidGotJoker = nil
  local bTopIsJoker = false
  local bTopIsBlack = false
  local bTopIsRed = false
  local iWildCount = 0
  local cardType = nil
  local shortName = nil
  local shortSuit = nil
  local score = 0
  local sDesc = ""
  local bookScore = 0

  --debug("Scoring thing of type " .. type(target))
  if target.tag=="Deck" then
--  if target.getQuantity()>1 then
    --log("decking")
    contents = target.getObjects()
    if (contents) then
      debug("In Contents...")
      debug("contents = " .. #contents)
      iRed3Count =0
      for k, oneCard in pairs(contents) do
        local oneScore = scoreCard(oneCard)
        if (oneScore) then
          score = score + oneScore
        end
        _, shortName, shortSuit = cardDeets(oneCard)
        if shortName=="3" then
          iRed3Count = iRed3Count + 1
        end
    --            shortName = string.match(oneCard.description,"[%a%d]*")
    --            shortSuit = string.match(oneCard.description,"[%a%d]*$")
    --            debug("k = " .. k .." - " .. shortName .. "/" .. shortSuit )
        if (shortName=="2") or (shortName=="Joker") then
          iWildCount = iWildCount + 1
          if (shortName=="Joker") then
              if (k==target.getQuantity()) then
                bTopIsJoker=true
                debug("Top is Joker")
              end
            guidGotJoker = oneCard.guid
          end
        else
          if (shortSuit=="Clubs") or (shortSuit=="Spades") then
            if (k==target.getQuantity()) then
              bTopIsBlack=true
              debug("Top is Black")
            end
            guidGotBlack = oneCard.guid

    --                debug('GotBlack ' .. oneCard.description)
          else
            if (k==target.getQuantity()) then
              bTopIsRed=true
              debug("Top is Red")
            end
            guidGotRed = oneCard.guid
    --                debug('GotRed' .. oneCard.description)
          end
          if (not cardType) then
            cardType = shortName
          end
          if (shortName != cardType) or ( (shortName=="3") and (giRuleSet != giCaliforniaRules) ) then
            bInconsistentDeck = true
          end
        end
    --            debug("oneCard:" .. shortName .. " --- " .. scr )
      end
    end

    -- now card type will have 3-Ace, Wild, or Mixed in it. (for returning later)
    if (bInconsistentDeck) then
      cardType = "MIXED"
    elseif (not cardType) then
      cardType = "Wild"
    end

    sAddTxt = ""
    if (target != mainDeck) then
      --debug('Guids = ' .. guidGotBlack .. ' - ' .. guidGotRed)
--      if (iRed3Count>0) then
--        if (giRuleSet == giCaliforniaRules) then
--          if (bInconsistentDeck) then
--            sAddTxt = "\n" .. "Red 3's counted as " .. giRed3Penalty .. " in mixed deck"
--          else
--            score = score - giRed3Penalty*iRed3Count + 50*iRed3Count
--            sAddTxt = "\n" .. "Red 3's counted as " .. giRed3SideStackScore .. " in extra-card deck"
--          end
--        elseif (giRuleSet==giNorthCarolinaRules) then
--          sAddTxt = "\n" .. "Red 3's counted as " .. giRed3Penalty .. " in mixed deck"
--        end
--      end

      sDesc = "DeckScore: ".. score
      -- Reused Score now that we've put it in getDescription
      -- from here on, it's the score of the meld
      --score=0
      --debug("score = " .. sDesc)
      bProblem = false
      iQty = target.getQuantity()
      if (giRuleSet != giCaliforniaRules) or (iRed3Count != iQty) then
        if iQty<7 then
          sDesc = sDesc .. "\n" .. "Incomplete Book (" .. iQty .. " cards)"
          bProblem = true
        end
        if ( (not guidGotRed) and ( (giRuleSet != giCaliforniaRules) or (iQty>iWildCount) ) ) then
            sDesc = sDesc .. "\n" .. "Incomplete Book (Need Red)"
            bProblem = true
        end
        if ( (not guidGotBlack) and ( (giRuleSet != giCaliforniaRules) or (iQty>iWildCount) ) ) then
          sDesc = sDesc .. "\n" .. "Incomplete Book (Need Black)"
          bProblem = true
        end
        if ( (iWildCount>2) and (giRuleSet == giNorthCarolinaRules) ) then
            sDesc = sDesc .. "\n" .. "Invalid Book (too many wild)" -- .. iWildCount .. " Wild)"
            bProblem = true
        end
        if ((iWildCount>2) and (giRuleSet==giCaliforniaRules) and (iQty>iWildCount)) then
            sDesc = sDesc .. "\n" .. "Invalid Book (too many wild)" -- .. iWildCount .. " Wild)"
            bProblem = true
        end
        if (bInconsistentDeck) then
          sDesc = sDesc .. "\n" .. "Invalid Book (mixed book)"
          bProblem = true
        end
        if (not bProblem) then
          if ( (giRuleSet==giCaliforniaRules) and (iWildCount==iQty) ) then
            sDesc = sDesc .. "\n" .. "Wild Book"
            bookScore=gi_WILD_BOOK_SCORE
            --score=1500
            if (not bTopIsJoker) and (guidGotJoker) then
                local deckPos = target.getPosition()
                local deckScale = target.getScale()
                local oneGot = target.takeObject{position={deckPos.x, deckPos.y+deckScale.y/2+0.05, deckPos.z},guid=guidGotJoker}
            end
          elseif (iWildCount>0) then
            sDesc = sDesc .. "\n" .. "Black Book"
            bookScore=gi_BLACK_BOOK_SCORE
            --score=300
            if (not bTopIsBlack) then
                local deckPos = target.getPosition()
                local deckScale = target.getScale()
                local oneGot = target.takeObject{position={deckPos.x, deckPos.y+deckScale.y/2+0.05, deckPos.z},guid=guidGotBlack}
            end
          else
            sDesc = sDesc .. "\n" .. "Red Book"
            bookScore=gi_RED_BOOK_SCORE
            --score=500
            if (not bTopIsRed) then
              local deckPos = target.getPosition()
              local deckScale = target.getScale()
              local oneGot = target.takeObject{position={deckPos.x, deckPos.y+deckScale.y/2+0.05, deckPos.z},guid=guidGotRed}
            end
          end
        end
      end
    else
      sDesc = sDesc .. "\nMain Deck"
    end
    sDesc = sDesc .. sAddTxt
    --debug("score2 = " .. sDesc)
  else
    --  log("single")
      score, sDesc = scoreCard(target)
  end
  --debug("Returning = " .. score .. " / " .. sDesc)
  -- Note: score is the card value if it's a card
  --       score is the meld value if it's a valid deck
  if (not score) then
    score = 0
  end
  if (not bookScore) then
    bookScore=0
  end
  if (target.is_face_down) then
      score = -1 * score
      bookScore = 0
  end
  return score, sDesc, bookScore, cardType
end

--==============================================================================
function iif(crit, iftrue, ifnot)
  if (crit) then
    return iftrue
  end
  return ifnot
end

function coolName(sColor)
  return iif(playerStuff[sColor].nick,playerStuff[sColor].nick,iif(Player[sColor].steam_name,Player[sColor].steam_name,sColor))
end

function writeToNotebookTab(sMessage, iTab)
  if not iTab then
    iTab = 1
  end
  if (not sMessage) then
    sMessage = "<nil value?!>"
  end
  tabInfo = Notes.getNotebookTabs()
  if (tabInfo[iTab].body) then
    sNote = tabInfo[iTab].body .. "\n------------------------------------\n" .. sMessage
  end
  params = {
      index = iTab-1,
      body = sNote,
  }
  Notes.editNotebookTab(params)
end

function copyScores()
  sNote = ""
  playerList = getSortedSeatedPlayers()
  for iP, playerColor in ipairs(playerList) do
    sNote = sNote .. "\n" .. coolName(playerColor) .. ", " .. gtScores[playerStuff[playerColor].num][1] .. ", " .. gtScores[playerStuff[playerColor].num][2] .. ", " .. gtScores[playerStuff[playerColor].num][3] .. ", " .. gtScores[playerStuff[playerColor].num][4].. ", TOTAL = " .. gtScores[playerStuff[playerColor].num][5]
  end
  sNote = sNote .. "\n\n"
  sNote = sNote .. "\n" .. "#score set 1 " .. gtScores[1][1] .. " ".. gtScores[2][1] .. " ".. gtScores[3][1] .. " ".. gtScores[4][1] .. " "
  sNote = sNote .. " 2 " .. gtScores[1][2] .. " ".. gtScores[2][2] .. " ".. gtScores[3][2] .. " ".. gtScores[4][2] .. " "
  sNote = sNote .. " 3 " .. gtScores[1][3] .. " ".. gtScores[2][3] .. " ".. gtScores[3][3] .. " ".. gtScores[4][3] .. " "
  sNote = sNote .. " 4 " .. gtScores[1][4] .. " ".. gtScores[2][4] .. " ".. gtScores[3][4] .. " ".. gtScores[4][4] .. " "
  sNote = sNote .. " hand " .. giHand .. " first " .. gsFirstToGoFirstColor .. "\n\n\n"
  tabInfo = Notes.getNotebookTabs()
  if (tabInfo[1].body) then
    sNote = tabInfo[1].body .. "\n------------------------------------\n" .. sNote
  end
  params = {
      index = 0,
      title = "Scores",
      body = sNote,
      color = "Grey"
  }
  Notes.editNotebookTab(params)
end

function onChat(message, sender)
  local sColor = sender.color
  local sMsg = string.lower(message)


  if (string.gsub(message,"%s+","")=="#admin") then
    Player[sColor].print ("#debug : no debugs")
    Player[sColor].print ("#debug <key>: enable a debug key")
    Player[sColor].print ("#direction [true|false]: hide/show the direction buttons")
    Player[sColor].print ("#offset: reset the offset between cards in row to default")
    Player[sColor].print ("#offset <num>: set the offset between cards in row")
    Player[sColor].print ("#dev [true|false]: turn on/off development features")
    return false
  end

  if (string.gsub(message,"%s+","")=="#help") then
    Player[sColor].print ("#reinit : restore object refs after hot script push")
    Player[sColor].print ("#init : reset board")
    Player[sColor].print ("#sort <string> [, <color>] : change sort")
    Player[sColor].print ("#sort help : sort help")
    Player[sColor].print ("#sound <num> : set discard sound to #")
    Player[sColor].print ("#nick <string>[, <color>] : Set nickname")
    Player[sColor].print ("#score reset")
    Player[sColor].print ("#score set <hand> <p1> <p2> <p3> <p4>")
    Player[sColor].print ("#score hand <hand>")
    Player[sColor].print ("#score f2gf <color>")
    Player[sColor].print ("#score copy")
    Player[sColor].print ("#footnote [true|false] [, <color>] : turn footnote warnings on/off for self or target color")
    Player[sColor].print ("#align [true|false] [, <color>] : evenly space card stacks")
    Player[sColor].print ("#playhand : auto-play matching cards from hand to table")
    return false
  end

  if string.gsub(message,"%s+","")=="#playhand" then
    autoPlayMatchingCards(sColor)
    return false
  end

  if string.gsub(message,"%s+","")=="#plan" then
    local plan = buildTurnPlan(sColor)
    printTurnPlan(plan, sColor)
    return false
  end

  if string.gsub(message,"%s+","")=="#reinit" then
    local ok, err = pcall(function() onLoad("") end)
    if ok then
      Player[sColor].print("Reinit OK.")
    else
      Player[sColor].print("Reinit ERROR: " .. tostring(err))
    end
    return false
  end

  if string.gsub(message,"%s+","")=="#status" then
    local p = function(s) Player[sColor].print(s) end
    p("=== Script State ===")
    p("obj_Zone_Discard: " .. tostring(obj_Zone_Discard))
    p("objScoreZones: "    .. tostring(objScoreZones))
    p("giPlayerCount: "    .. tostring(giPlayerCount))
    p("mainDeck: "         .. tostring(mainDeck))
    p("goSurface: "        .. tostring(goSurface))
    p("text_score_white: " .. tostring(text_score_white))
    p("textDiscardValue: " .. tostring(textDiscardValue))
    p("playerStuff: "      .. tostring(playerStuff))
    p("giRuleSet: "        .. tostring(giRuleSet))
    p("giStartFootCards: " .. tostring(giStartFootCards))
    p("UI_TABLETOP_SURFACE: " .. tostring(UI_TABLETOP_SURFACE))
    return false
  end

  if string.sub(message,1,5)=="#nick" then
    local sNick, sTargetColor = string.match(message,"#nick *([^,]*),* *(.*)")
    if (sTargetColor and sTargetColor!="") then
      debug("sTargetColor="..sTargetColor.."." ,"panel")
      sTargetColor = string.lower(sTargetColor)
      sColor = sTargetColor:gsub("^%l", string.upper)
    end
    debug("nick="..sNick .. " color="..sColor,"panel")
    playerStuff[sColor].nick=sNick
    setPlayerNamesOnScoresheet()
    return false
  end

  if string.sub(message,1,9)=="#footnote" then
    local sVal, sTargetColor = string.match(sMsg,"#footnote *([^,]*),* *(.*)")
    if (sTargetColor and sTargetColor!="") then
      sTargetColor = string.lower(sTargetColor)
      sColor = sTargetColor:gsub("^%l", string.upper)
    end
    playerStuff[sColor].bShowFootNotes=(sVal=="true")
    printToColor("ShowFootNotes set to " .. iif(playerStuff[sColor].bShowFootNotes,"true","false"),sColor)
    textFootNotes[sColor].TextTool.setValue(" ")
    if (sender.color != sColor) then
      printToColor("ShowFootNotes set to " .. iif(playerStuff[sColor].bShowFootNotes,"true","false").. " for " .. coolName(sColor),sender.color)
    end
    return false
  end

  if string.sub(message,1,6)=="#align" then
    local sVal, sTargetColor = string.match(sMsg,"#align *([^,]*),* *(.*)")
    if (sTargetColor and sTargetColor!="") then
      sTargetColor = string.lower(sTargetColor)
      sColor = sTargetColor:gsub("^%l", string.upper)
    end
    if (sVal=="true") then
      playerStuff[sColor].bAlign = math.abs(playerStuff[sColor].bAlign)
    elseif (sVal=="high") then
      playerStuff[sColor].bAlign = 1
  elseif (sVal=="low") then
      playerStuff[sColor].bAlign = 3
    else
      playerStuff[sColor].bAlign = math.abs(playerStuff[sColor].bAlign)*-1
end
--    playerStuff[sColor].bAlign=iif(sVal=="true",math.abs(playerStuff[sColor].bAlign),math.abs(playerStuff[sColor].bAlign)*-1)
    printToColor("Alignment set to " .. gt_ALIGN_WORDS[playerStuff[sColor].bAlign],sColor)
    textFootNotes[sColor].TextTool.setValue(" ")
    if (sender.color != sColor) then
      printToColor("Alignment set to " .. gt_ALIGN_WORDS[playerStuff[sColor].bAlign] .. ' for ' .. coolName(sColor),sender.color)
    end
    return false
  end


  if sMsg=="#sound" then
    effectTable = soundCube.AssetBundle.getTriggerEffects()
    debug(dump(effectTable),"panel")
    for k,v in pairs(effectTable) do
      printToColor(v.index .. ": " .. v.name,sColor)
    end
    return false
  end

  if string.sub(sMsg,1,5)=="#play" then
    local sVal = string.match(sMsg,"#play *(.*)")
    local sSound = string.match(sMsg,"(%d+)")
    if tonumber(sVal) then
      layoutScoreZones(tonumber(sVal))
      return false
    end
  end

  if (string.gsub(sMsg,"%s+","")=="#debug") then
    gtDebugFlags={
    }
    return false
  end

  if string.sub(message,1,4)=="#dev" then
    local sVal = string.match(sMsg,"#dev *(.*)")
    if (sVal == "win") then
      finishFlag()
      return false
    end
    if (sVal == "ghost") then
      local sVal = string.match(sMsg,"#dev *ghost *(.*)")
      gbDevGhostBoxes=(sVal=="true")
      printToColor("Ghost set to " .. iif(gbDevGhostBoxes,"true","false"),sColor)
    else
      gbShowDirButtons=(sVal=="true")
      printToColor("Dir buttons set to " .. iif(gbShowDirButtons,"true","false"),sColor)
      setButtons()
      gbDevGhostBoxes=(sVal=="true")
      printToColor("Ghost set to " .. iif(gbDevGhostBoxes,"true","false"),sColor)
    end
    return false
  end

  if string.sub(sMsg,1,10)=="#dev" then
    local sVal = string.match(sMsg,"#dev ghost *(.*)")
    gbDevGhostBoxes=(sVal=="true")
    return false
  end



  if string.sub(message,1,10)=="#direction" then
    local sVal = string.match(sMsg,"#direction *(.*)")
    gbShowDirButtons=(sVal=="true")
    setButtons()
    return false
  end

  -- if string.sub(sMsg,1,9)=="#walltint" then
  --   local sVal = string.match(sMsg,"#walltint *(.*)")
  --   printToColor("Wall Tint set to " .. sVal,sColor)
  --   if (tonumber(sVal)) then
  --     for i, oWallProps in pairs(objScoreZones[#Player.getPlayers()]["Walls"]) do
  --       local objWalls[i].getColorTint(tint)
  --       tint.a = tonumber(sVal)
  --       objWalls[i].setColorTint(tint)
  --     end
  --   end
  --   return false
  -- end


  if string.sub(sMsg,1,6)=="#debug" then
    local sVal = string.match(sMsg,"#debug *(.*)")
    if sVal == "on" then
      gtDebugFlags["playhand"] = 1
      printToColor("playhand debug ON", sColor)
    elseif sVal == "off" then
      gtDebugFlags["playhand"] = nil
      printToColor("playhand debug OFF", sColor)
    else
      gtDebugFlags[sVal] = 1
      printToColor("Debug set to " .. dump(gtDebugFlags), sColor)
    end
    return false
  end


  if sMsg=="#offset" then
    gfSpreadMult = 0.8
    printToColor("setting offset to 0.8 (default)",sColor)
    return false

  end

  if string.sub(sMsg,1,7)=="#offset" then
    local sVal = string.match(sMsg,"#offset *(.*)")
    if (tonumber(sVal)) then
      gfSpreadMult = tonumber(sVal)
      printToColor("setting offset to " .. sVal,sColor)
    else
      printToColor(sVal .. " is not a number",sColor)
    end
    return false
  end

  if string.sub(sMsg,1,10)=="#dropshift" then
    local sVal = string.match(sMsg,"#dropshift *(.*)")
    if (tonumber(sVal)) then
      gfDropShift = tonumber(sVal)
      printToColor("setting dropshift to " .. sVal,sColor)
    else
      printToColor(sVal .. " is not a number",sColor)
    end
    return false
  end


  if string.sub(sMsg,1,6)=="#sound" then
    local sVal = string.match(sMsg,"#sound *(.*)")
    local sSound = string.match(sMsg,"(%d+)")
    if tonumber(sVal) then
      giDiscardSound = tonumber(sVal)
      playDiscardSound()
      return false
    else
      if (sVal=="false") then
        gbPlaySounds = false
        return false
      elseif (sVal=="true") then
        gbPlaySounds = true
        playDiscardSound()
        return false
      else
        printToColor("#sound must have a number, true, or false.", sColor)
        return false
      end
    end
    return false
  end

  if string.sub(sMsg,1,6)=="#score" then
    if (string.match(sMsg,"help")) then
      Player[sColor].print ("#score reset")
      Player[sColor].print ("#score set <hand> <p1> <p2> <p3> <p4> [<hand> <p1> <p2> <p3> <p4>]* [hand <num>] [first <color>]")
      Player[sColor].print ("#score hand <hand>")
      Player[sColor].print ("#score first <color>")
      Player[sColor].print ("#score copy")
      return false
    end
    if (string.match(sMsg,"reset")) then
      resetScoresheet()
      return false
    end
    if (string.match(sMsg,"set")) then -- must come after the "reset" search, obviously
      local sHand, sP1, sP2, sP3, sP4 = string.match(sMsg,"set *(%d+) *(%-?%d+) *(%-?%d+) *(%-?%d*) *(%-?%d*)")
      debug("sMsg = " .. sMsg .. " / sHand = " .. iif(sHand,sHand,"nil"),"score")
      local iLoopBreak = 0
      while (sHand) do
        debug("looping","score")
        iLoopBreak = iLoopBreak +1
        if (iLoopBreak>4) then
          log("ERROR: Had to Loopbreak out of #score")
          break
        end
        debug("Setting scores.","score")
        gtScores[1][tonumber(sHand)]=iif(tonumber(sP1),tonumber(sP1),0)
        gtScores[2][tonumber(sHand)]=iif(tonumber(sP2),tonumber(sP2),0)
        gtScores[3][tonumber(sHand)]=iif(tonumber(sP3),tonumber(sP3),0)
        gtScores[4][tonumber(sHand)]=iif(tonumber(sP4),tonumber(sP4),0)
        sHand = nil
        debug("Removing 5 numbers.","score")
        sMsg = string.gsub(sMsg,"( *%-?%d+)","",5)
        debug("Searching for next scores.","score")
        sHand, sP1, sP2, sP3, sP4 = string.match(sMsg,"set *(%d+) *(%-?%d+) *(%-?%d+) *(%-?%d*) *(%-?%d*)")
        debug("sMsg = " .. sMsg .. " / sHand = " .. iif(sHand, sHand,"nil"),"score")
      end
      debug("left with sMsg = " .. sMsg .. " / sHand = " .. iif(sHand,sHand,"nil"),"score")
--      return false
    end

--    if (string.match(sMsg,"hand")) then
      local sHand = string.match(sMsg,"hand *(%d+)")
      debug("Looking for hand and got " .. iif(sHand,sHand,"nil"),"score")
      if tonumber(sHand) then
        setHand(tonumber(sHand))
        printToAll("Current hand is set to " .. sHand)
        refreshScoresheet()
      end
--      return false
--    end


--    if (string.match(sMsg,"first")) then
      local sClr = string.match(sMsg,"first *(.*)")
      debug("Looking for color and got " .. iif(sClr,sClr,"nil"),"score")
      if (sClr) then
        sColor = sClr:gsub("^%l", string.upper)
        if Player[sColor]  then
          gsFirstToGoFirstColor = sColor
          printToAll(sColor .. " is set as the first to have gone first in this game.")
          refreshScoresheet()
        else
          if sClr then
            log("Error: trying to set score.first but value not recognized.  cmd= " .. sMsg)
          end
        end
--      return false
    end

    if (string.match(sMsg,"copy")) then
      copyScores()
      printToColor("Scores recorded to Notebook tab", sColor)
      return false
    end
    refreshScoresheet()
    return false
  end

  if (string.gsub(message,"%s+","")=="#score") then
    countScore()
    return false
  end

  if (string.gsub(message,"%s+","")=="#init") then
    mainDeck = initializeGame()
    return false
  end

  if (string.gsub(message,"%s+","")=="#deckem") then
    admin_deckem()
    return false
  end

    if (string.gsub(message,"%s+","")=="#sort") then
      displaySort(sender.color, sender.color, playerStuff[sender.color].sSortMetaOrder)
      return false
    end
    if string.sub(message,1,5)=="#sort" then
      if (string.match(sMsg,"help")) then
        Player[sColor].print ("w - WildCards")
        Player[sColor].print ("3 - all threes")
        Player[sColor].print ("b - 3+ card sets")
        Player[sColor].print ("p - pairs")
        Player[sColor].print ("a - all others")
        Player[sColor].print ("r - Highest to Lowest")
        Player[sColor].print ("l - Lowest to Highest")
        Player[sColor].print ("> - Ace High")
        Player[sColor].print ("< - Ace Low")
        Player[sColor].print ("Append with ', <color>' to do for someone else")
        return false
      end
      local sTargetColor = string.match(sMsg,", *(.*)")
      if (sTargetColor) then
        sColor = sTargetColor:gsub("^%l", string.upper)
      end
      processSortCommand(sColor, sMsg)
      displaySort(sender.color, sColor, playerStuff[sColor].sSortMetaOrder)
      return false
    end
    return true
end

function processSortCommand(sColor, sMsg)
  sMsg = string.gsub(sMsg,"#sort *","")
  if (sColor) then
    debug("sColor       : " ..  sColor ,"sort")
  else
    debug("sColor is nil?!","sort")
  end
  if (sMsg) then
    debug("sMsg  : " .. sMsg,"sort")
  else
    debug("sMsg is nil?!","sort")
  end
  local sSortCommand = string.match(sMsg,"[<>wbp3alr]+")
  debug("sSortComand  : " .. sSortCommand,"sort")
  if sSortCommand then
    if (string.match(sSortCommand,">")) then
      playerStuff[sColor].bSortAceHigh = true
      debug("Setting sortAceHigh=true","sort")
    end
    if (string.match(sSortCommand,"<")) then
      playerStuff[sColor].bSortAceHigh = false
      debug("Setting sortAceHigh=false","sort")
    end
    if (string.match(sSortCommand,"l")) then
      playerStuff[sColor].bSortLowLeft = true
      debug("Setting sortLowLeft=true","sort")
    end
    if (string.match(sSortCommand,"r")) then
      playerStuff[sColor].bSortLowLeft = false
      debug("Setting sortLowLeft=false","sort")
    end
    playerStuff[sColor].sSortMetaOrder=sSortCommand -- string.gsub(sSortCommand,"[<>lr]","")
    if (not string.find(playerStuff[sColor].sSortMetaOrder,"a")) then
      playerStuff[sColor].sSortMetaOrder = playerStuff[sColor].sSortMetaOrder .. "a"
    end

    -- Check for stupid.. remove duplicates and unknown letters
    local sNew = ""
    for i=1,string.len(playerStuff[sColor].sSortMetaOrder) do
      if (not string.find(sNew, string.sub(playerStuff[sColor].sSortMetaOrder,i,i))) then
        if (string.find(string.sub(playerStuff[sColor].sSortMetaOrder,i,i),"[<>wbp3alr]")) then
          sNew = sNew .. string.sub(playerStuff[sColor].sSortMetaOrder,i,i)
        else
          log("ERROR: unknown string found in sort command: " .. message)
        end
      end
    end

    playerStuff[sColor].sSortMetaOrder = sNew
    debug("SortMetaOrder  : " .. playerStuff[sColor].sSortMetaOrder,"sort")
  end
end


function displaySort(sActorColor, sSortColor, sSort)
  local sSortWords = {
    ["w"]="wild cards",
    ["3"]="threes",
    ["b"]="3+ card sets",
    ["p"]="pairs",
    ["a"]="all others",
    [true]="lowest to highest",
    [false]="highest to lowest",
    ["l"]="lowest to highest",
    ["r"]="highest to lowest",
    [">"]="Aces High",
    ["<"]="Aces Low",
   }

  sReadable = ""
  debug("SortMetaOrder  : " .. playerStuff[sSortColor].sSortMetaOrder,sort)
  for i=1,string.len(playerStuff[sSortColor].sSortMetaOrder) do
      if (sReadable != "") then
        sReadable = sReadable .. ", "
      end
      sReadable = sReadable .. sSortWords[string.sub(playerStuff[sSortColor].sSortMetaOrder,i,i)]
  end
  if (sSortColor != sActorColor) then
    Player[sSortColor].print("The " .. sActorColor .. " player has changed your sorting." )
    Player[sActorColor].print("The " .. sSortColor .. " player's sorting is " .. sReadable .. " (" .. playerStuff[sSortColor].sSortMetaOrder .. ")." )
    Player[sActorColor].print("Within each set, the cards will be sorted from " .. sSortWords[playerStuff[sSortColor].bSortLowLeft] .. "." )
  end
  Player[sSortColor].print("Your sorting is set to " .. sReadable .. " (" .. playerStuff[sSortColor].sSortMetaOrder .. ")." )
--  Player[sSortColor].print("Within each set, the cards will be sorted from " .. sSortWords[playerStuff[sSortColor].bSortLowLeft] .. "." )
end

function printTab(stitle, tab, grp)
  if grp then
    if (gtDebugFlags[grp]) then
      print ("Table = " .. stitle)
      for index, data in ipairs(tab) do
          print(index)
          s = ""
          for key, value in pairs(data) do
              s = s .. "(" ..  key .. ") " .. tostring(value) .. ", "
          end
          print (s)
      end
    end
  else
    -- log(str)
  end

end

-- Sort the calling player's hand.
function sortHand(obj, player_color)
	-- Table to store the sortable list of cards present in the hand.
	local cards = {}
	-- Table to store the list of card positions in the hand.
	local handPos = {}
	-- Grab the list of cards in the hand.  We'll use this to populate our tables.
	handObjects = Player[player_color].getHandObjects()
	-- Filter out any cards that are physically in the discard zone.
	-- Scripted discards (setPositionSmooth) may not immediately unregister from
	-- getHandObjects(), so we cross-check against the zone's actual contents.
	if obj_Zone_Discard then
	  pcall(function()
	    local discardGuids = {}
	    for _, dObj in ipairs(obj_Zone_Discard.getObjects()) do
	      discardGuids[dObj.guid] = true
	    end
	    local filtered = {}
	    for _, hObj in ipairs(handObjects) do
	      if not discardGuids[hObj.guid] then
	        table.insert(filtered, hObj)
	      end
	    end
	    handObjects = filtered
	  end)
	end
	-- Flag to indicate whether the error handling routine found an improperly named card.
	ErrorMode = 0

	-- Populate both tables.
	for i, j in pairs(handObjects) do

    _, cardNumber, cardSuit = cardDeets(j)

--		local cardNumber = j.getName()
--		local cardSuit = j.getDescription()

		-- Error Handling
		if cardNumber == '' or (groupSuitMode != 0 and cardSuit == '') then
			broadcastToColor("[00ff00]Sort Hand Tool[-]: Card missing name or needed description.", player_color, {1,1,1})
			debug(j, 'Card with missing name or needed description:',"sort")
			ErrorMode = 1
			return
		end

		table.insert(cards, {j, j.getName(), cardNumber, cardSuit})
		table.insert(handPos, j.getPosition())

	end

	if ErrorMode == 1 then
		return
	end

  setSortOrder(playerStuff[player_color].bSortLowLeft, playerStuff[player_color].bSortAceHigh)

	-- Sort the list of cards.
	table.sort(cards, sortLogic)

  bGroupWilds   = not (string.find(playerStuff[player_color].sSortMetaOrder,"w")==nil)
  bGroupBooks   = not (string.find(playerStuff[player_color].sSortMetaOrder,"b")==nil)
  bGroupPairs   = not (string.find(playerStuff[player_color].sSortMetaOrder,"p")==nil)
  bGroupAllOthers = not (string.find(playerStuff[player_color].sSortMetaOrder,"[a]")==nil)
  bGroupThrees  = not (string.find(playerStuff[player_color].sSortMetaOrder,"[3]")==nil)
  tableWild={}
  tableBooks={}
  tablePairs={}
  tableAllOthers={}
  tableThrees={}

  iStart = 1
  iEnd = iStart
  sLastCard=""
  printTab("cards",cards,"sort")
  for i, j in ipairs(cards) do
     debug("lastcard is " .. sLastCard .. " this card is " .. j[3] .. j[4], "sort")
     if (sLastCard=="" or  j[3]==sLastCard or (sLastCard=="Wild" and (j[3]=="2"  or j[3]=="Joker"))) then
       iEnd=i
       if(j[3]=="2" or j[3]=="Joker") then
         sLastCard="Wild"
       else
         sLastCard=j[3]
       end
     else
       metaGroupCards(iStart, iEnd, sLastCard, cards)
        iStart=i
        iEnd=iStart
        if(j[3]=="2" or j[3]=="Joker") then
          sLastCard="Wild"
        else
          sLastCard=j[3]
        end
     end
	end
  if (sLastCard != "") then
    metaGroupCards(iStart, iEnd, sLastCard, cards)
  end
  debug("Sorting Based on " .. playerStuff[player_color].sSortMetaOrder , "sort")
  cards = {}
  for m = 1,string.len(playerStuff[player_color].sSortMetaOrder) do
      sChar = string.sub(playerStuff[player_color].sSortMetaOrder,m,m)
      if (sChar=="w") then
        printTab("Wild", tableWild,"sort")
        TableConcat(cards,tableWild)
      elseif (sChar=="b") then
        printTab("Books", tableBooks,"sort")
        TableConcat(cards,tableBooks)
      elseif (sChar=="p") then
        printTab("Pairs", tablePairs,"sort")
        TableConcat(cards,tablePairs)
      elseif (sChar=="a") then
        printTab("AllOthers" , tableAllOthers,"sort")
        TableConcat(cards,tableAllOthers)
      elseif (sChar=="3") then
        printTab("Threes", tableThrees,"sort")
        TableConcat(cards,tableThrees)
      end
  end


	-- Sort the slot positions spatially so sorted card[1] always maps to the
	-- "first" slot (left or right depending on bSortLowLeft).
	-- getHandObjects() returns cards in TTS internal order, not positional order,
	-- so without this step the assignment is to arbitrary slots.
	do
	  local xMin, xMax, zMin, zMax = math.huge, -math.huge, math.huge, -math.huge
	  for _, p in ipairs(handPos) do
	    if p.x < xMin then xMin = p.x end
	    if p.x > xMax then xMax = p.x end
	    if p.z < zMin then zMin = p.z end
	    if p.z > zMax then zMax = p.z end
	  end
	  local bSpreadX = (xMax - xMin) >= (zMax - zMin)
	  local bAsc = playerStuff[player_color].bSortLowLeft
	  table.sort(handPos, function(a, b)
	    if bSpreadX then return bAsc and (a.x < b.x) or (a.x > b.x)
	    else             return bAsc and (a.z < b.z) or (a.z > b.z) end
	  end)
	end

	-- Take the sorted list of cards and apply the list of card positions in order to physically rearrange them.
	for i, j in ipairs(cards) do
		j[1].setPosition(handPos[i])
	end
end

function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function metaGroupCards(iStart, iEnd, sLastCard, cards)
  debug("Storing .." .. iEnd+1-iStart .. " ".. sLastCard, "sort")
  local m = 0
  if (bGroupWilds and sLastCard=="Wild") then
    for m = iStart, iEnd do
      table.insert(tableWild,cards[m])
    end
  elseif (bGroupThrees and sLastCard=="3") then
    for m = iStart, iEnd do
      table.insert(tableThrees,cards[m])
    end
  elseif (bGroupBooks and iEnd+1-iStart>2) then
    for m = iStart, iEnd do
      table.insert(tableBooks,cards[m])
    end
  elseif (bGroupPairs and iEnd+1-iStart==2) then
    for m = iStart, iEnd do
      table.insert(tablePairs,cards[m])
    end
  else
    for m = iStart, iEnd do
      table.insert(tableAllOthers,cards[m])
    end
  end
end

-- Comparison function used by table.sort()
-- The parameters supplied by table.sort() are tables, where parameter[1] is the object reference, and parameter[2] is the object Name.
function sortLogic(card1, card2)

	-- Grab the relevant information for both cards.
  _, card1Number,card1Suit = cardDeets(card1[1])
  --	card1Number = card1[1].getName()
  debug("looking for *" .. card1Number .. "*" .. card1Suit .. "*","decksort")
  debug("len=" .. #refCardOrderIndex,"decksort")
	card1NumberIndex = refCardOrderIndex[card1Number]
  --	card1Suit = card1[1].getDescription()
	card1SuitIndex = refSuitOrderIndex[card1Suit]
  debug("C1NI=" .. card1NumberIndex,"decksort")
  debug("C1SI=" .. card1SuitIndex,"decksort")

  _, card2Number, card2Suit = cardDeets(card2[1])
--	card2Number = card2[1].getName()
	card2NumberIndex = refCardOrderIndex[card2Number]
--	card2Suit = card2[1].getDescription()
	card2SuitIndex = refSuitOrderIndex[card2Suit]


	-- log(card1Number, 'card1Number:')
	-- log(card1NumberIndex, 'card1NumberIndex:')
	-- log(card1Suit, 'card1Suit:')
	-- log(card1SuitIndex, 'card1SuitIndex:')

  groupSuitMode = 2

	-- 0: Ignore all suits.
	if groupSuitMode == 0 then
		return card1NumberIndex < card2NumberIndex
	end

	-- 1: All suits are together
	if groupSuitMode == 1 then
		if card1Suit == card2Suit then
			return card1NumberIndex < card2NumberIndex
		else
			return card1SuitIndex < card2SuitIndex
		end
	end

	-- 2: All card numbers are together
	if groupSuitMode == 2 then
		if card1Number == card2Number then
			return card1SuitIndex < card2SuitIndex
		else
			return card1NumberIndex < card2NumberIndex
		end
	end
end


-- Function to determine whether a specified value/object exists in a table.
function tableContains(tableSpecified, element)
	for _, value in pairs(tableSpecified) do
		if value == element then
			return true
		end
	end
	return false
end