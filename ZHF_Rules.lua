--==============================================================================
-- ZHF_Rules.lua
-- Pure card-classification and meld-rule functions.
-- No TTS API calls.  Included by Global.-1.lua via -- #include.
--==============================================================================

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
