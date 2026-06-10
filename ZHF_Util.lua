--==============================================================================
-- ZHF_Util.lua
-- Pure helper functions: math, table ops, formatting, debug aids.
-- No TTS API calls, no game-state dependencies.
-- Included by Global.-1.lua via -- #include.
--==============================================================================

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

function tableDump(tab)
  for k, playersCards in pairs(tab) do
    debug(#playersCards .. " ".. k .. " **********************************")
    for i, card in ipairs(playersCards) do
      debug("guid = " .. card.guid .. "  - score= " .. card.score .. "  - inhand=" .. tostring(card.in_hand) .. "  - desc = " .. card.desc)
    end
  end
end

function iif(crit, iftrue, ifnot)
  if (crit) then
    return iftrue
  end
  return ifnot
end

function coolName(sColor)
  return iif(playerStuff[sColor].nick,playerStuff[sColor].nick,iif(Player[sColor].steam_name,Player[sColor].steam_name,sColor))
end

function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function getTodayDate()
  local ok, result = pcall(function() return os.date("%Y-%m-%d") end)
  if ok and result and result ~= "" then return result end
  return gsSavedDate or "unknown"
end

function tableContains(tableSpecified, element)
	for _, value in pairs(tableSpecified) do
		if value == element then
			return true
		end
	end
	return false
end
