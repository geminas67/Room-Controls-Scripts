--[[
  Extron DXP Matrix Controller - NV32 Style Logic
  Author: (Your Name)
  Date: 2025-01-27
  
  Implements:
    - Interlocking source selection (btnVideoSource)
    - Multi-select destination selection (btnDestinations, with [5] as 'All')
    - Dynamic feedback in txtDestination
    - Modular routing logic (ready for Extron DXP integration)
]]--

local sourceNames = {"ClickShare", "Teams PC", "Laptop Front", "Laptop Rear", "No Source"}
local destinationNames = {"Mon1", "Mon2", "Mon3", "Mon4", "All Displays"}

-- Helper: Get selected source index
local function getSelectedSourceIdx()
  for i, btn in ipairs(Controls.btnVideoSource) do
    if btn.Boolean then return i end
  end
  return nil
end

-- Helper: Get selected destinations (returns table of indices)
local function getSelectedDestinations()
  local dests = {}
  for i = 1, 4 do
    if Controls.btnDestinations[i].Boolean then table.insert(dests, i) end
  end
  return dests
end

-- Routing logic (replace with Extron DXP API as needed)
local function routeSourceToDestinations(sourceIdx, destIndices)
  -- Example: print routing actions (replace with actual routing calls)
  for _, destIdx in ipairs(destIndices) do
    print("Routing " .. sourceNames[sourceIdx] .. " to " .. destinationNames[destIdx])
    -- Extron DXP: extronComponent["output_"..destIdx].String = tostring(sourceIdx)
  end
end

local function clearRoutingForDestination(destIdx)
  print("Clearing routing for " .. destinationNames[destIdx])
  -- Extron DXP: extronComponent["output_"..destIdx].String = '0'
end

-- Feedback update
local function updateTxtDestination()
  local srcIdx = getSelectedSourceIdx()
  local dests = getSelectedDestinations()
  if not srcIdx or #dests == 0 then
    Controls.txtDestination.String = ""
    return
  end
  local srcName = sourceNames[srcIdx]
  if #dests == 4 then
    Controls.txtDestination.String = srcName .. " → All Displays"
  else
    local destNames = {}
    for _, i in ipairs(dests) do table.insert(destNames, destinationNames[i]) end
    Controls.txtDestination.String = srcName .. " → " .. table.concat(destNames, ", ")
  end
end

-- Source selection (interlocking)
for i, btn in ipairs(Controls.btnVideoSource) do
  btn.EventHandler = function(ctl)
    if ctl.Boolean then
      -- Deselect all other sources
      for j, otherBtn in ipairs(Controls.btnVideoSource) do
        if j ~= i then otherBtn.Boolean = false end
      end
      Controls.txtSource.String = sourceNames[i]
      -- Route to all selected destinations
      local dests = getSelectedDestinations()
      if #dests > 0 then
        routeSourceToDestinations(i, dests)
      end
    else
      -- If all sources are off, clear txtSource
      local anyOn = false
      for _, b in ipairs(Controls.btnVideoSource) do if b.Boolean then anyOn = true break end end
      if not anyOn then Controls.txtSource.String = "" end
    end
    updateTxtDestination()
  end
end

-- Destination selection (multi-select, with All)
for i, btn in ipairs(Controls.btnDestinations) do
  btn.EventHandler = function(ctl)
    if i == 5 and ctl.Boolean then
      -- All Displays selected: set all 1-4 to true
      for j = 1, 4 do Controls.btnDestinations[j].Boolean = true end
    end
    -- If All is deselected, do nothing (user can deselect individually)
    -- Route current source to all selected destinations
    local srcIdx = getSelectedSourceIdx()
    local dests = getSelectedDestinations()
    if srcIdx and #dests > 0 then
      routeSourceToDestinations(srcIdx, dests)
    end
    -- If a destination is deselected, clear its routing
    if not ctl.Boolean and i <= 4 then
      clearRoutingForDestination(i)
    end
    updateTxtDestination()
  end
end

-- Optional: Initialize feedback on load
updateTxtDestination() 