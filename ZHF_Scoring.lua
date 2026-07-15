--==============================================================================
-- ZHF_Scoring.lua
-- Score tally, scoresheet UI updates, daily log + notebook writing.
-- Bundled into Global.-1.lua via require("ZHF_Scoring").
--==============================================================================

function recordScores(iHand)
  -- execute a tally of scores and update the current hand on the scoresheet
  -- iHand must be captured at the time the hand ends (passed from checkFootNote)
  -- to avoid a race where the user deals before this fires and giHand is already incremented.
  iHand = (type(iHand) == "number") and iHand or giHand
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
      debug("iHand="..iHand,"panel")
      UI.setAttribute("P".. playerStuff[sColor].num .. "R" .. iHand .. "Score","text",iScore)
      gtScores[i][iHand]=iScore
      debug("S["..i.."]["..iHand.."]=" ..gtScores[i][iHand],"panel")
      debug(dump(gtScores),"panel")
    end
    refreshScoresheet()
    debug(dump(gtScores),"panel")
    gbHandOver = false   -- scoring complete; allow dealing now
    pcall(updateDailyLog)
    -- Belt-and-suspenders: re-write the log a few seconds later, after any end-of-hand booking
    -- animation/diagnostics have settled, so a single dropped Notes write can't lose the hand's
    -- score from the notebook.
    Wait.time(function() pcall(updateDailyLog) end, 3.0)

end

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

function ClearScores()
  -- name says it all.. reset the scores in the array to zero
  gtScores = {[1]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [2]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [3]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0},
            [4]={[1]=0,[2]=0,[3]=0,[4]=0,[5]=0}}
end

function resetScoresheet()
  -- clear scores and redisplay the scoresheet
  ClearScores()
  refreshScoresheet()
end

function setHand(iNewHand)
  giHand = iNewHand
  if giHand > 4 then
    -- Seal the completed game into today's log before wiping scores.
    if not gCompletedGames then gCompletedGames = {} end
    table.insert(gCompletedGames, snapshotCurrentGame(4))
    pcall(updateDailyLog)
    giHand = 1
    printToAll("Starting a new game!")
    ClearScores()
  end
end

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

function getOrderedPlayerNames()
  local byNum = {}
  for _, color in ipairs({"White","Green","Blue","Red"}) do
    if Player[color] and Player[color].seated and playerStuff and playerStuff[color] then
      byNum[playerStuff[color].num] = coolName(color)
    end
  end
  local names = {}
  for i = 1, 4 do names[i] = byNum[i] or ("P"..i) end
  return names
end

function findOrCreateNotebookTab(title, color)
  local tabs = Notes.getNotebookTabs()
  for i, tab in ipairs(tabs) do
    if tab.title == title then return i - 1 end
  end
  Notes.addNotebookTab({ title=title, body="", color=color or "Grey" })
  tabs = Notes.getNotebookTabs()
  for i, tab in ipairs(tabs) do
    if tab.title == title then return i - 1 end
  end
  return 0
end

function snapshotCurrentGame(handsComplete)
  local scoresCopy = {}
  for i = 1, 4 do
    scoresCopy[i] = {}
    for h = 1, 4 do
      scoresCopy[i][h] = (gtScores and gtScores[i] and gtScores[i][h]) or 0
    end
  end
  return {
    scores        = scoresCopy,
    playerNames   = getOrderedPlayerNames(),
    firstColor    = gsFirstToGoFirstColor or "",
    handsComplete = handsComplete or math.max(0, (giHand or 1) - 1),
  }
end

function formatScoreGrid(snap)
  local names  = snap.playerNames or {}
  local scores = snap.scores or {}
  local done   = snap.handsComplete or 0
  local NW = 14  -- name column width
  local HW = 8   -- hand column width (2-space gap + "Hand 1" = 8; 4-digit scores = 4 leading spaces)
  local TW = 8   -- total column width (3-space gap + 5-digit max total)

  local hdr = string.format("%-"..NW.."s", "")
  for h = 1, 4 do hdr = hdr .. string.format("%"..HW.."s", "Hand "..h) end
  hdr = hdr .. string.format("%"..TW.."s", "Total")
  local sep = string.rep("-", NW + HW * 4 + TW)

  local rows = {}
  for i = 1, 4 do
    local nm = names[i] or ("P"..i)
    -- Skip placeholder names (P1/P2/P3/P4 = empty player slots)
    if nm ~= ("P"..i) then
      if #nm > NW-1 then nm = string.sub(nm,1,NW-1) end
      local row = string.format("%-"..NW.."s", nm)
      local tot = 0
      for h = 1, 4 do
        if h <= done then
          local v = (scores[i] and scores[i][h]) or 0
          tot = tot + v
          row = row .. string.format("%"..HW.."d", v)
        else
          row = row .. string.format("%"..HW.."s", "----")
        end
      end
      row = row .. string.format("%"..TW.."s", done > 0 and tostring(tot) or "----")
      table.insert(rows, row)
    end
  end
  return hdr.."\n"..sep.."\n"..table.concat(rows,"\n")
end

function buildScoreCommand(snap)
  local scores = snap.scores or {}
  local cmd = "#score set"
  for h = 1, 4 do
    cmd = cmd .. " " .. h
    for i = 1, 4 do cmd = cmd .. " " .. ((scores[i] and scores[i][h]) or 0) end
  end
  return cmd .. " hand " .. (snap.handsComplete or 0) .. " first " .. (snap.firstColor or "")
end

function buildDailyLogContent()
  local today = getTodayDate()
  local out   = {}
  local function L(s) table.insert(out, s) end

  L("=== Hand and Foot  —  " .. today .. " ===")
  L("")

  local gameNum = 1
  for _, snap in ipairs(gCompletedGames or {}) do
    L("--- Game " .. gameNum .. " (Complete) ---")
    L(formatScoreGrid(snap))
    L("")
    L(buildScoreCommand(snap))
    L("")
    gameNum = gameNum + 1
  end

  -- Current in-progress game: show when at least one hand has been scored.
  -- Scan gtScores directly so this is accurate whether called from recordScores()
  -- (giHand = the hand just scored) or any other context.
  local done = 0
  if gtScores then
    for h = 1, 4 do
      for i = 1, 4 do
        local v = gtScores[i] and gtScores[i][h]
        if v and v ~= 0 then done = h; break end
      end
    end
  end
  if done >= 1 then
    local snap = snapshotCurrentGame(done)
    local label = done == 4 and "Complete" or ("Hand " .. done .. " of 4 complete")
    L("--- Game " .. gameNum .. " (" .. label .. ") ---")
    L(formatScoreGrid(snap))
    L("")
    L(buildScoreCommand(snap))
    L("")
  end

  return table.concat(out, "\n")
end

function updateDailyLog()
  local idx = findOrCreateNotebookTab(_DL_SCORES_TAB, _DL_TAB_COLOR)
  local content = buildDailyLogContent()
  Notes.editNotebookTab({ index=idx, title=_DL_SCORES_TAB, body=content, color=_DL_TAB_COLOR })
end

function archiveToPreviousGames()
  -- Read current Scores tab content.
  local todayBody = ""
  for _, tab in ipairs(Notes.getNotebookTabs()) do
    if tab.title == _DL_SCORES_TAB then todayBody = tab.body or ""; break end
  end
  if todayBody == "" then return end

  -- Find/create archive tab and read its current content.
  local archIdx = findOrCreateNotebookTab(_DL_ARCHIVE_TAB, _DL_TAB_COLOR)
  local archBody = ""
  for _, tab in ipairs(Notes.getNotebookTabs()) do
    if tab.title == _DL_ARCHIVE_TAB then archBody = tab.body or ""; break end
  end

  -- Prepend today's session.
  local combined = archBody == "" and todayBody or (todayBody .. _DL_SEPARATOR .. archBody)

  -- Trim to _DL_MAX_DAYS sessions.
  local sessions = {}
  local rem = combined
  while rem ~= "" do
    local s = string.find(rem, _DL_SEPARATOR, 1, true)
    if s then
      table.insert(sessions, string.sub(rem, 1, s-1))
      rem = string.sub(rem, s + #_DL_SEPARATOR)
    else
      table.insert(sessions, rem); rem = ""
    end
  end
  while #sessions > _DL_MAX_DAYS do table.remove(sessions) end

  Notes.editNotebookTab({
    index=archIdx, title=_DL_ARCHIVE_TAB,
    body=table.concat(sessions, _DL_SEPARATOR), color=_DL_TAB_COLOR
  })
end

function checkDateOnLoad()
  local today = getTodayDate()
  if gsSavedDate and gsSavedDate ~= "" and gsSavedDate ~= today then
    pcall(archiveToPreviousGames)
    gCompletedGames = {}
    local idx = findOrCreateNotebookTab(_DL_SCORES_TAB, _DL_TAB_COLOR)
    Notes.editNotebookTab({ index=idx, title=_DL_SCORES_TAB, body="", color=_DL_TAB_COLOR })
  end
  gsSavedDate = today
  pcall(updateDailyLog)
end

