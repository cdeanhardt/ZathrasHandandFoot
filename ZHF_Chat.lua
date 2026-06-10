--==============================================================================
-- ZHF_Chat.lua
-- onChat dispatcher + chat-driven helpers (sort, notebook writing, debug print).
-- Bundled into Global.-1.lua via require("ZHF_Chat").
--==============================================================================

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
    Player[sColor].print ("#date <string> : archive today's log and start fresh for a new session")
    Player[sColor].print ("#footnote [true|false] [, <color>] : turn footnote warnings on/off for self or target color")
    Player[sColor].print ("#align [true|false] [, <color>] : evenly space card stacks")
    Player[sColor].print ("#playhand : auto-play matching cards from hand to table")
    Player[sColor].print ("#sweep [<color>|all] : re-spread any merged meld piles")
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
      pcall(updateDailyLog)
      printToColor("Daily log updated in Notebook tab", sColor)
      return false
    end
    refreshScoresheet()
    pcall(updateDailyLog)
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

  if string.sub(message, 1, 6) == "#sweep" then
    local arg = string.match(message, "^#sweep%s+(.*)")
    local target = arg and string.gsub(arg, "^%s*(.-)%s*$", "%1") or ""
    if target == "" then
      sweepMeldsForPlayer(sColor)
    elseif string.lower(target) == "all" then
      for _, color in ipairs(playerList or {}) do
        sweepMeldsForPlayer(color)
      end
    else
      sweepMeldsForPlayer(target:gsub("^%l", string.upper))
    end
    return false
  end

    if (string.gsub(message,"%s+","")=="#sort") then
      displaySort(sender.color, sender.color, playerStuff[sender.color].sSortMetaOrder)
      return false
    end
    if string.sub(message, 1, 5) == "#date" then
      local arg = string.match(message, "^#date%s+(.*)")
      local newDate = arg and string.gsub(arg, "^%s*(.-)%s*$", "%1") or ""
      if newDate ~= "" then
        if newDate ~= gsSavedDate then
          pcall(archiveToPreviousGames)
          gCompletedGames = {}
          local idx = findOrCreateNotebookTab("Scores", "Grey")
          Notes.editNotebookTab({ index=idx, title="Scores", body="", color="Grey" })
          gsSavedDate = newDate
          pcall(updateDailyLog)
          printToColor("Daily log archived. Starting fresh for: " .. newDate, sColor)
        else
          printToColor("Date string unchanged — no action taken.", sColor)
        end
      else
        printToColor("Usage: #date <string>  (any unique string marks a new session)", sColor)
      end
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
