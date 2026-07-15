--==============================================================================
-- ZHF_Events.lua
-- TTS event callbacks (onObject*, onPlayer*) and immediate helpers.
-- Bundled into Global.-1.lua via require("ZHF_Events").
--==============================================================================

function onObjectSpawn(obj)
    obj.addContextMenuItem('Layout Pretty', function(x) spread3("s",x,1) end, false)
    obj.addContextMenuItem('Layout TowardCam', function(x) spread3("s",x,0) end, false)
    -- Card-only items: do NOT add these to all objects — hand zone scripting zones
    -- break if they receive more than 3 items total (2 from here + 1 from onLoad).
    if obj.tag == "Card" then
      obj.addContextMenuItem('Layout Hand', function(playerColor)
        local _, rank, _ = cardDeets(obj)
        layoutHandRank(playerColor, rank, false, true)
      end, false)
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
  local ok, tag = pcall(function() return leave_object.tag end)
  if not ok then return end
  if (tag=="Deck") then
    local ok2, objs = pcall(function() return leave_object.getObjects() end)
    if ok2 and objs then
      for _, oneCard in ipairs(objs) do
        onObjectLeaveScriptingZone(zone, oneCard)
      end
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

function playerZoneBoundary (player_color, obj)
  if not gbInitializing then

    if not gbDealing then
      local name = coolName(player_color)
      if tablepop(fromdeck,obj.guid) then
        if (not playerStuff[player_color].bMaskActions) then
          if (playerStuff[player_color].drawcountqueued==false) then
            playerStuff[player_color].drawcountqueued=true
            Wait.time(function()
                setReminder("White")
                setReminder("Green")
                setReminder("Blue")
                setReminder("Red")
                playerStuff[player_color].drawcountqueued=false;
                end, 2)
          end
          announceAll(name .. " drew 1");
          addToDrawCount(player_color,1,false)
        end
      else
        if tablepop(fromdiscard,obj.guid) then
          if (not playerStuff[player_color].bMaskActions) then
            -- Hard limit: max 7 cards from the discard pile per turn.
            if playerStuff[player_color].drawcountdisc >= 7 then
              printToColor("Draw blocked — max 7 cards from the discard pile per turn.", player_color)
              pcall(function()
                if obj_Zone_Discard then
                  local dpos = obj_Zone_Discard.getPosition()
                  obj.setPosition({dpos.x, dpos.y + 1, dpos.z})
                  obj.setRotation({0, 180, 0})
                end
              end)
              return
            end
            if (playerStuff[player_color].drawcountqueued==false) then
              playerStuff[player_color].drawcountqueued=true
              Wait.time(function()
                  setReminder("White")
                  setReminder("Green")
                  setReminder("Blue")
                  setReminder("Red")
                  playerStuff[player_color].drawcountqueued=false;
                end, 1)
            end
            announceAll(name .. " drew 1 (from discard)");
            addToDrawCount(player_color,1,true)
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

function enteredAndWaited(bag, oGuid, oTag, oDesc)
  return
end

function onObjectNumberTyped(object, color, number)
  if not object then return false end

  local pileType = nil  -- "deck", "discard", or "foot"
  local limit    = nil

  -- 1. Main deck
  pcall(function()
    if mainDeck and object.getGUID() == mainDeck.getGUID() then
      pileType = "deck"; limit = 2
    end
  end)

  -- 2. Discard pile — any Card/Deck currently inside the discard zone
  if not pileType then
    pcall(function()
      if obj_Zone_Discard then
        for _, obj in ipairs(obj_Zone_Discard.getObjects()) do
          if obj.getGUID() == object.getGUID() then
            pileType = "discard"; limit = 7; break
          end
        end
      end
    end)
  end

  -- 3. Foot pile — face-down Deck/Card in any player's score zone
  if not pileType then
    pcall(function()
      if object.is_face_down and (object.tag == "Deck" or object.tag == "Card") then
        for _, scoreColor in ipairs({"White", "Green", "Blue", "Red"}) do
          if objectInScoreZone(object, scoreColor) then
            pileType = "foot"; limit = 13; break
          end
        end
      end
    end)
  end

  if not limit or number <= limit then
    return false  -- within limit — let TTS deal normally
  end

  -- Over the limit.
  if pileType == "foot" then
    -- Foot: cap at 13 and deal that many.
    local qty = 1
    pcall(function() qty = object.getQuantity() end)
    local toDeal = math.min(limit, qty)
    if toDeal > 0 then pcall(function() object.deal(toDeal, color) end) end
    printToColor(string.format("Foot draw capped at %d.", limit), color)
  else
    -- Deck / Discard: warn and draw NOTHING.
    printToColor(string.format(
      "Draw blocked — max %d card%s from the %s.",
      limit, limit == 1 and "" or "s",
      pileType == "deck" and "main deck" or "discard pile"), color)
  end
  return true  -- block TTS's default deal in all cases
end

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
  -- Capture identifiers via guarded property reads.  TTS can fire this mid-merge with
  -- a transiently-invalid reference; touching it then throws a C# "Object reference not
  -- set" error (same hazard as onObjectEnterContainer).  Read .guid (a property, safer
  -- than method calls), bail if it fails, and use the captured strings thereafter so the
  -- deferred Wait.time closures never re-touch obj.
  local okO, lGuid = pcall(function() return obj.guid end)
  if not okO or not lGuid then return end
  local okB, lBagGuid = pcall(function() return bag.guid end)
  if not okB then lBagGuid = nil end

  debug("Object " .. lGuid .. " left container " .. tostring(lBagGuid), "discard")
  if obj_Zone_Discard then
    local okZ, inDiscard = pcall(function() return objectInZone(obj, obj_Zone_Discard) end)
    if okZ and inDiscard then
      tablepush(fromdiscard, lGuid)
      Wait.time(function() tablepop(fromdiscard, lGuid) end, 2.0, 0)
    end
  end
  if not gbInitializing and mainDeck and lBagGuid then
    -- local player, idx = findUsedThing(tablePlayerDecks, bag.getGUID())
    --log ("b: " .. bag.guid)
    --log ("md: " ..mainDeck.getGUID())
    --log ("#fd:" .. #fromdeck)

    if (lBagGuid == mainDeck.guid) then
      tablepush(fromdeck, lGuid)
      Wait.time(function() tablepop(fromdeck, lGuid) end, 2.0, 0)
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

gRestackPending = gRestackPending or {}
function onObjectEnterContainer(bag, obj)
  -- A card was added to a container (by auto-play OR a player dropping it).  If the container
  -- is a book Deck, re-stack its top card to show the right colour.  CRITICAL: do NOT touch the
  -- entering `obj` — it's mid-merge and TTS invalidates its reference, throwing a C# "Object
  -- reference not set" that escapes pcall (the reason this handler used to be a no-op).  We only
  -- capture the BAG's guid and act on the re-fetched deck later, once it's stationary.  The
  -- restack is deferred (settle) and retried while the deck is still moving, and debounced per
  -- deck so a 7-card formation doesn't schedule 7 restacks.
  if gbInitializing or gbDealing then return end
  local guid
  local ok = pcall(function() if bag and bag.tag == "Deck" then guid = bag.getGUID() end end)
  if not ok or not guid then return end
  if gRestackPending[guid] then return end
  gRestackPending[guid] = true
  local tries = 0
  local function attempt()
    tries = tries + 1
    local deck = getObjectFromGUID(guid)
    if not deck then gRestackPending[guid] = nil; return end
    local moving = false
    pcall(function()
      local v = deck.getVelocity()
      if v and (math.abs(v.x) + math.abs(v.y) + math.abs(v.z)) > 0.1 then moving = true end
    end)
    if moving and tries < 8 then
      Wait.time(attempt, 0.5)   -- still sliding to its slot — retry once parked
      return
    end
    gRestackPending[guid] = nil
    pcall(function() restackBookTop(deck) end)
  end
  Wait.time(attempt, 0.6)   -- let the just-added card settle before re-stacking
end

function objectInZone(obj, zone)
  local zoneObjects = shallowCopy(zone.getObjects())
  for k, oneCard in pairs(zoneObjects) do
    if (oneCard.guid == obj.guid) then
      return true
    end
  end
  return false
end

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
    -- Report which card was discarded (single-card discards only).
    local cardStr = ""
    if discardedObj.tag == "Card" then
      pcall(function()
        local _, sName, sSuit = cardDeets(discardedObj)
        if sName then
          if sSuit and sSuit ~= "" and sName ~= "Joker" then
            cardStr = " " .. sName .. " of " .. sSuit
          else
            cardStr = " " .. sName
          end
        end
      end)
    end
    announceAll(name .. " discarded" .. cardStr)
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

