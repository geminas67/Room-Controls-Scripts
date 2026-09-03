--[[
  Divisible Space Controller with Room Priority System
  Author: Nikolas Smith, Q-SYS
  Version: 4.1 | Date: 2026-03-24
  Firmware Req: 10.0.1+

  Room Priority Hierarchy:
    SalonD → SalonE           (D has priority over E)
    SalonA → SalonB → SalonC  (A highest priority in group)
    SalonF → SalonG → SalonH  (F highest priority in group)
]]

-----------------------------[ Configuration Tables ]-----------------------------
local roomNames = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"}

local roomIndexByName = {}
for i, name in ipairs(roomNames) do roomIndexByName[name] = i end

local roomNumberMap = {
  SalonD=1, SalonE=2, SalonA=3, SalonB=4, SalonC=5, SalonF=6, SalonG=7, SalonH=8
}

local numberToRoomMap = {}
for roomName, num in pairs(roomNumberMap) do numberToRoomMap[num] = roomName end

local gainControlNames = {
  "lvl-SalonD", "lvl-SalonE", "lvl-SalonA", "lvl-SalonB",
  "lvl-SalonC", "lvl-SalonF", "lvl-SalonG", "lvl-SalonH"
}

local wallRoomPairs = {
  [1]  = {"SalonD", "SalonE"},
  [2]  = {"SalonA", "SalonB"},
  [3]  = {"SalonB", "SalonC"},
  [4]  = {"SalonF", "SalonG"},
  [5]  = {"SalonG", "SalonH"},
  [6]  = {"SalonD", "SalonA", "SalonB", "SalonC"},
  [7]  = {"SalonE", "SalonF", "SalonG", "SalonH"},
  [8]  = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC"},
  [9]  = {"SalonD", "SalonE", "SalonF", "SalonG", "SalonH"},
  [10] = {"SalonA", "SalonB", "SalonC"},
  [11] = {"SalonF", "SalonG", "SalonH"},
  [12] = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"},
  -- Individual room separation buttons (13–20)
  [13] = {"SalonD"}, [14] = {"SalonE"}, [15] = {"SalonA"}, [16] = {"SalonB"},
  [17] = {"SalonC"}, [18] = {"SalonF"}, [19] = {"SalonG"}, [20] = {"SalonH"}
}

local wallInterlockMap = {
  [1]  = {13, 14},
  [6]  = {15, 13},
  [7]  = {14},
  [8]  = {15, 13, 14},
  [9]  = {13, 14},
  [10] = {15},
  [12] = {15, 13, 14}
}

local roomToSeparationButton = {
  SalonD=13, SalonE=14, SalonA=15, SalonB=16,
  SalonC=17, SalonF=18, SalonG=19, SalonH=20
}

local roomCombinations = {
  {id=1,  name="SalonD+SalonE Combined",                       activeRooms={SalonD=true, SalonE=true},                                                           priority="SalonD"},
  {id=2,  name="SalonA+SalonB Combined",                       activeRooms={SalonA=true, SalonB=true},                                                           priority="SalonA"},
  {id=3,  name="SalonB+SalonC Combined",                       activeRooms={SalonB=true, SalonC=true},                                                           priority="SalonB"},
  {id=4,  name="SalonF+SalonG Combined",                       activeRooms={SalonF=true, SalonG=true},                                                           priority="SalonF"},
  {id=5,  name="SalonG+SalonH Combined",                       activeRooms={SalonG=true, SalonH=true},                                                           priority="SalonG"},
  {id=6,  name="SalonD+SalonA+SalonB+SalonC Combined",         activeRooms={SalonD=true, SalonA=true, SalonB=true, SalonC=true},                                  priority="SalonD"},
  {id=7,  name="SalonE+SalonF+SalonG+SalonH Combined",         activeRooms={SalonE=true, SalonF=true, SalonG=true, SalonH=true},                                  priority="SalonE"},
  {id=8,  name="SalonD+SalonE+SalonA+SalonB+SalonC Combined",  activeRooms={SalonD=true, SalonE=true, SalonA=true, SalonB=true, SalonC=true},                     priority="SalonD"},
  {id=9,  name="SalonD+SalonE+SalonF+SalonG+SalonH Combined",  activeRooms={SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true},                     priority="SalonD"},
  {id=10, name="SalonA+SalonB+SalonC Combined",                activeRooms={SalonA=true, SalonB=true, SalonC=true},                                               priority="SalonA"},
  {id=11, name="SalonF+SalonG+SalonH Combined",                activeRooms={SalonF=true, SalonG=true, SalonH=true},                                               priority="SalonF"},
  {id=12, name="All Combined",                                 activeRooms={SalonD=true, SalonE=true, SalonA=true, SalonB=true, SalonC=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonD"},
  {id=13, name="All Separated",                                activeRooms={SalonD=true, SalonE=true, SalonA=true, SalonB=true, SalonC=true, SalonF=true, SalonG=true, SalonH=true}, priority=nil},
}

-----------------------------[ Controls ]-----------------------------
local controls = {
  compRoomControls  = Controls.compRoomControls,
  compAudioRouter   = Controls.compAudioRouter,
  compRoomCombiner  = Controls.compRoomCombiner,
  txtStatus         = Controls.txtStatus,
  selCombination    = Controls.selRoomCombination,
  wallOpenButtons   = Controls.wallOpenButtons,
  uciButtons        = Controls.uciButtons,
}

-----------------------------[ Utilities ]-----------------------------
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
  if not ctrl or ctrl[prop] == val then return end
  ctrl[prop] = val
end

local function bind(ctrl, handler)
  if not ctrl or not handler then return false end
  local ok = pcall(function() ctrl.EventHandler = handler end)
  return ok
end

local function bindArray(ctrls, handler)
  if not ctrls or not handler then return 0 end
  local array = isArr(ctrls) and ctrls or {ctrls}
  local count = 0
  for i, ctrl in ipairs(array) do
    if bind(ctrl, function(ctl)
      local ok, err = pcall(handler, i, ctl)
      if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
    end) then
      count = count + 1
    end
  end
  return count
end

local function cleanupComponentHandlers(oldComp, controlNames, debugCb)
  if not oldComp or not controlNames then return 0 end
  local cleaned = 0
  for _, name in ipairs(controlNames) do
    if oldComp[name] and oldComp[name].EventHandler then
      oldComp[name].EventHandler = nil
      cleaned = cleaned + 1
    end
  end
  if debugCb and cleaned > 0 then debugCb("Cleaned up " .. cleaned .. " handler(s) from old component") end
  return cleaned
end

local function tableContains(t, val)
  for _, v in ipairs(t) do if v == val then return true end end
  return false
end

local function validateControls()
  local required = {"compRoomControls", "compAudioRouter", "compRoomCombiner", "txtStatus", "wallOpenButtons", "uciButtons"}
  local missing = {}
  for _, name in ipairs(required) do
    if not controls[name] then table.insert(missing, name) end
  end
  if #missing > 0 then
    print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
    return false
  end
  if not controls.selCombination then
    print("WARNING: selRoomCombination not found - combination selector disabled")
  end
  return true
end

local function normalizeControlArrays()
  for _, name in ipairs({"compRoomControls", "compAudioRouter", "wallOpenButtons", "uciButtons"}) do
    local ctrl = controls[name]
    if ctrl and not isArr(ctrl) then controls[name] = {ctrl} end
  end
end

-----------------------------[ Config ]-----------------------------
local const = {
  roomName = "Raleigh Marriott Salon",
  debug = true,
  clearString = "[Clear]",
}

-----------------------------[ State ]-----------------------------
local components = {
  roomCombiner = nil,
  roomControls = {},
  audioRouter  = {},
  uciButtons   = {},
  invalid      = {roomCombiner=false, roomControls=false, audioRouter=false, uciButtons=false}
}

local roomComponentNames = {}
local audioRouterNames   = {}
local uciButtonNames     = {}
local powerSyncInProgress = false

-----------------------------[ Debug ]-----------------------------
local function debugPrint(str)
  if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-----------------------------[ Functions ]-----------------------------

local function parseConfiguration(configString)
  if not configString or configString == "" then return {} end
  local roomGroups    = {}
  local currentGroup  = {}
  local inGroup       = false
  local currentNumber = ""
  for idx = 1, #configString do
    local char = configString:sub(idx, idx)
    if     char == "["                  then inGroup = true; currentGroup = {}
    elseif char == "]"                  then
      if #currentNumber > 0 then table.insert(currentGroup, tonumber(currentNumber)); currentNumber = "" end
      if #currentGroup   > 0 then table.insert(roomGroups, currentGroup) end
      inGroup = false
    elseif char == "," and inGroup      then
      if #currentNumber > 0 then table.insert(currentGroup, tonumber(currentNumber)); currentNumber = "" end
    elseif char:match("%d")             then
      currentNumber = currentNumber .. char
    end
  end
  return roomGroups
end

local function checkStatus()
  if not controls.txtStatus then return end
  local invalidList = {}
  for compType, isInvalid in pairs(components.invalid) do
    if isInvalid then table.insert(invalidList, compType) end
  end
  if #invalidList > 0 then
    setProp(controls.txtStatus, "String", "Invalid: " .. table.concat(invalidList, ", "))
    setProp(controls.txtStatus, "Value", 1)
    return
  end
  local connRooms, connRouters, connSelectors = 0, 0, 0
  for i = 1, #roomNames do
    if roomComponentNames[i] and roomComponentNames[i] ~= "" then connRooms     = connRooms     + 1 end
    if audioRouterNames[i]   and audioRouterNames[i]   ~= "" then connRouters   = connRouters   + 1 end
    if uciButtonNames[i]     and uciButtonNames[i]     ~= "" then connSelectors = connSelectors + 1 end
  end
  local status = "OK"
  if connRooms     < #roomNames then status = status .. " (Rooms:"     .. connRooms     .. "/" .. #roomNames .. ")" end
  if connRouters   < #roomNames then status = status .. " (Routers:"   .. connRouters   .. "/" .. #roomNames .. ")" end
  if connSelectors < #roomNames then status = status .. " (Selectors:" .. connSelectors .. "/" .. #roomNames .. ")" end
  setProp(controls.txtStatus, "String", status)
  setProp(controls.txtStatus, "Value", 0)
end

local function isRoomPoweredOn(roomName)
  local idx = roomIndexByName[roomName]
  if not idx then return false end
  local comp = components.roomControls[idx]
  return comp and comp["ledSystemPower"] and comp["ledSystemPower"].Boolean or false
end

local function anyRoomInPairPoweredOn(roomPair)
  for _, roomName in ipairs(roomPair) do
    if isRoomPoweredOn(roomName) then return true end
  end
  return false
end

-- Returns the highest-priority room number for an audio/gain group
local function getPriorityInputForGroup(group, combinationPriority)
  local priorityNum = combinationPriority and roomNumberMap[combinationPriority]
  if priorityNum and tableContains(group, priorityNum) then return priorityNum end
  local highest = math.huge
  for _, num in ipairs(group) do if num < highest then highest = num end end
  return highest
end

local function getInputForRoom(roomName, roomGroups, combinationPriority)
  local roomNum = roomNumberMap[roomName]
  if not roomNum            then return 1       end
  if #roomGroups == 0       then return roomNum  end
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNum) then
      return getPriorityInputForGroup(group, combinationPriority)
    end
  end
  return roomNum
end

local function getGainControlForRoom(roomName, roomGroups, combinationPriority)
  local roomNum = roomNumberMap[roomName]
  if not roomNum      then return gainControlNames[1]       end
  if #roomGroups == 0 then return gainControlNames[roomNum] end
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNum) then
      return gainControlNames[getPriorityInputForGroup(group, combinationPriority)]
    end
  end
  return gainControlNames[roomNum]
end

local function configMatchesCombination(roomGroups, combination)
  if #roomGroups == 0 then return combination.id == 13 end
  local activeRooms = {}
  for roomName, isActive in pairs(combination.activeRooms) do
    if isActive then
      local num = roomNumberMap[roomName]
      if num then activeRooms[num] = true end
    end
  end
  local groupedRooms = {}
  for _, group in ipairs(roomGroups) do
    for _, num in ipairs(group) do groupedRooms[num] = true end
  end
  for num in pairs(activeRooms)  do if not groupedRooms[num] then return false end end
  for num in pairs(groupedRooms) do if not activeRooms[num]  then return false end end
  return true
end

local function getCombinationContext()
  if not components.roomCombiner then
    return {}, roomCombinations[13], nil
  end
  local configControl = components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    return {}, roomCombinations[13], nil
  end
  local roomGroups = parseConfiguration(configControl.String or "")
  for _, combo in ipairs(roomCombinations) do
    if configMatchesCombination(roomGroups, combo) then
      return roomGroups, combo, combo.priority
    end
  end
  return roomGroups, roomCombinations[13], nil
end

local function applyAudioRouting()
  if not components.roomCombiner then debugPrint("ERROR: No room combiner for audio routing"); return end
  local roomGroups, _, combinationPriority = getCombinationContext()
  debugPrint("Applying audio routing (" .. #roomGroups .. " groups, priority: " .. (combinationPriority or "none") .. ")...")
  local routed, skipped = 0, 0
  for i, roomName in ipairs(roomNames) do
    local router = components.audioRouter[i]
    if router and router["select.1"] then
      local inputNum = getInputForRoom(roomName, roomGroups, combinationPriority)
      setProp(router["select.1"], "Value", inputNum)
      routed = routed + 1
      debugPrint("  " .. roomName .. " → Input " .. inputNum)
    else
      skipped = skipped + 1
    end
  end
  debugPrint("Audio routing complete: " .. routed .. " routed, " .. skipped .. " skipped")
end

local function applyGainRouting()
  if not components.roomCombiner then return end
  local roomGroups, _, combinationPriority = getCombinationContext()
  debugPrint("Applying gain routing (" .. #roomGroups .. " groups, priority: " .. (combinationPriority or "none") .. ")...")
  local routed, skipped = 0, 0
  for i, roomName in ipairs(roomNames) do
    local roomComp = components.roomControls[i]
    if roomComp and roomComp["compGains 1"] then
      local gainName = getGainControlForRoom(roomName, roomGroups, combinationPriority)
      setProp(roomComp["compGains 1"], "String", gainName)
      routed = routed + 1
      debugPrint("  " .. roomName .. " → " .. gainName)
    else
      skipped = skipped + 1
    end
  end
  debugPrint("Gain routing complete: " .. routed .. " routed, " .. skipped .. " skipped")
end

-- Component Management -----------------------------------------------------------

local function setComponent(ctrl, componentType)
  if not ctrl then
    components.invalid[componentType] = true
    checkStatus()
    return nil
  end
  local name = ctrl.String
  if not name or name == "" or name == const.clearString then
    if name == const.clearString then setProp(ctrl, "String", "") end
    setProp(ctrl, "Color", "white")
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("No " .. componentType .. " component selected")
    return nil
  end
  local comp     = Component.New(name)
  local ctrlList = comp and Component.GetControls(comp)
  if not ctrlList or #ctrlList < 1 then
    setProp(ctrl, "String", "[Invalid Component Selected]")
    setProp(ctrl, "Color", "pink")
    components.invalid[componentType] = true
    checkStatus()
    debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
    return nil
  end
  setProp(ctrl, "Color", "white")
  components.invalid[componentType] = false
  checkStatus()
  debugPrint("Connected " .. componentType .. ": " .. name)
  return comp
end

local function updateNamedSlot(name, roomIndex, nameTable, compTable, logPrefix)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local old = nameTable[roomIndex] or ""
  nameTable[roomIndex] = name
  compTable[roomIndex] = (name and name ~= "") and Component.New(name) or nil
  if old ~= (name or "") then
    debugPrint(logPrefix .. " " .. roomIndex .. " (" .. roomNames[roomIndex] .. "): '" .. old .. "' → '" .. (name or "") .. "'")
    checkStatus()
  end
end

local function updateRoomComponent(name, roomIndex)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local oldComp = components.roomControls[roomIndex]
  if oldComp and oldComp["btnSystemOnOff"] then
    cleanupComponentHandlers(oldComp, {"btnSystemOnOff"}, function(msg) debugPrint("[Room Controls] " .. msg) end)
  end
  updateNamedSlot(name, roomIndex, roomComponentNames, components.roomControls, "Room component")
end

local function updateAudioRouter(name, roomIndex)
  updateNamedSlot(name, roomIndex, audioRouterNames, components.audioRouter, "Audio router")
end

local function updateButtonRoomSelector(name, roomIndex)
  updateNamedSlot(name, roomIndex, uciButtonNames, components.uciButtons, "RoomSelector")
end

-- Component Discovery ---------------------------------------------------------------

local function discoverComponents()
  debugPrint("Discovering components...")
  local roomControlNames, audioRouterDiscNames, roomCombinerNames, uciCtrlNames = {}, {}, {}, {}
  for _, comp in ipairs(Component.GetComponents()) do
    if comp.Type == "device_controller_script" then
      if     comp.Name:match("^compRoomControls")   then table.insert(roomControlNames,       comp.Name); debugPrint("  Found room controls: "  .. comp.Name)
      elseif comp.Name:match("^uciControllerSalon") then table.insert(uciCtrlNames,           comp.Name); debugPrint("  Found UCI controller: " .. comp.Name)
      end
    elseif comp.Type == "router_with_output" then table.insert(audioRouterDiscNames, comp.Name); debugPrint("  Found audio router: "   .. comp.Name)
    elseif comp.Type == "room_combiner"      then table.insert(roomCombinerNames,     comp.Name); debugPrint("  Found room combiner: "  .. comp.Name)
    end
  end
  local function sortedWithClear(t)
    table.sort(t); table.insert(t, const.clearString); return t
  end
  local rcNames   = sortedWithClear(roomControlNames)
  local arNames   = sortedWithClear(audioRouterDiscNames)
  local combNames = sortedWithClear(roomCombinerNames)
  local uciNames  = sortedWithClear(uciCtrlNames)
  if controls.compRoomCombiner then controls.compRoomCombiner.Choices = combNames end
  for _, ctrl in ipairs(controls.compRoomControls) do if ctrl then ctrl.Choices = rcNames  end end
  for _, ctrl in ipairs(controls.compAudioRouter)  do if ctrl then ctrl.Choices = arNames  end end
  for _, ctrl in ipairs(controls.uciButtons)       do if ctrl then ctrl.Choices = uciNames end end
  debugPrint("Discovery complete - " .. #roomControlNames .. " room controls, " .. #audioRouterDiscNames ..
    " audio routers, " .. #roomCombinerNames .. " combiners, " .. #uciCtrlNames .. " UCI controllers found")
end

local function setWallOpenState(wallIndex, isOpen)
  local wallButton = controls.wallOpenButtons[wallIndex]
  if wallButton then setProp(wallButton, "Boolean", isOpen) end
  if components.roomCombiner then
    local wallControl = components.roomCombiner["wall." .. wallIndex .. ".open"]
    if wallControl then setProp(wallControl, "Boolean", isOpen) end
  end
end

-- Wall Management --------------------------------------------------------------------

local function updateWallStates()
  for wallIndex, roomPair in pairs(wallRoomPairs) do
    local wallButton = controls.wallOpenButtons[wallIndex]
    if not wallButton then goto continue end
    local shouldDisable = anyRoomInPairPoweredOn(roomPair)
    setProp(wallButton, "IsDisabled", shouldDisable)
    if shouldDisable then debugPrint("Wall " .. wallIndex .. " DISABLED (room powered on)") end
    ::continue::
  end
end

local function syncWallButtonStates()
  if not components.roomCombiner then return end
  debugPrint("Syncing wall button states from room combiner...")
  for wallIdx = 1, 12 do
    local wallButton  = controls.wallOpenButtons[wallIdx]
    local wallControl = components.roomCombiner["wall." .. wallIdx .. ".open"]
    if wallButton and wallControl then
      setProp(wallButton, "Boolean", wallControl.Boolean)
      local wallPair = wallRoomPairs[wallIdx]
      debugPrint("  Wall " .. wallIdx ..
        (wallPair and " (" .. table.concat(wallPair, "/") .. ")" or "") ..
        " → " .. (wallControl.Boolean and "OPEN" or "CLOSED"))
    end
  end
end

local function disableIndividualSeparationButtons(roomList)
  for _, roomName in ipairs(roomList) do
    local buttonIndex = roomToSeparationButton[roomName]
    if buttonIndex then
      local button = controls.wallOpenButtons[buttonIndex]
      if button then setProp(button, "Boolean", false) end
    end
  end
end

local function applyBidirectionalInterlock(wallIndex)
  local targetButtons = wallInterlockMap[wallIndex]
  if not targetButtons then return end
  for _, buttonIndex in ipairs(targetButtons) do
    local button = controls.wallOpenButtons[buttonIndex]
    if button then
      setProp(button, "Boolean", false)
      debugPrint("  Bidirectional interlock: Wall " .. wallIndex .. " → Button " .. buttonIndex .. " = false")
    end
  end
end

local function applyWallInterlock(currentWallIndex)
  for wallIndex, otherWallPair in pairs(wallRoomPairs) do
    if wallIndex == currentWallIndex or wallIndex >= 13 then goto continue end
    if not anyRoomInPairPoweredOn(otherWallPair) then
      setWallOpenState(wallIndex, false)
      debugPrint("  INTERLOCK: Wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ") → CLOSED")
    end
    ::continue::
  end
end

-- Room Button Visibility --------------------------------------------------------------

local function updateRoomButtonVisibility()
  if not controls.uciButtons or #controls.uciButtons == 0 then return end
  local roomGroups = select(1, getCombinationContext())
  debugPrint("Updating RoomSelector visibility (" .. #roomGroups .. " active groups)...")
  for i, roomName in ipairs(roomNames) do
    local uciButton = components.uciButtons[i]
    if not uciButton then
      local name = uciButtonNames[i]
      if name and name ~= "" then uciButton = Component.New(name); components.uciButtons[i] = uciButton end
    end
    if not uciButton then goto continue end
    local sourceRoomNum = roomNumberMap[roomName]
    local sourceGroup   = nil
    for _, group in ipairs(roomGroups) do
      if tableContains(group, sourceRoomNum) then sourceGroup = group; break end
    end
    for toggleIndex = 1, 8 do
      local toggleName = "pinLEDIsVisibleBtn" .. string.format("%02d", toggleIndex)
      local pin = uciButton[toggleName]
      if pin then
        local isVisible = sourceGroup
          and tableContains(sourceGroup, roomNumberMap[roomNames[toggleIndex]])
          or  (not sourceGroup and toggleIndex == i)
        setProp(pin, "Boolean", isVisible)
      end
    end
    debugPrint("  " .. roomName .. " RoomSelector updated" ..
      (sourceGroup and " (group: " .. #sourceGroup .. " rooms)" or " (separated)"))
    ::continue::
  end
end

local function refreshRoutingAndVisibility()
  applyAudioRouting()
  applyGainRouting()
  updateRoomButtonVisibility()
end

-- Power Synchronization ---------------------------------------------------------------

local function syncPowerToRooms(roomsToSync, powerState)
  powerSyncInProgress = true
  for _, roomName in ipairs(roomsToSync) do
    local idx = roomIndexByName[roomName]
    if not idx then goto continue end
    local comp = components.roomControls[idx]
    if comp and comp["btnSystemOnOff"] and comp["btnSystemOnOff"].Boolean ~= powerState then
      setProp(comp["btnSystemOnOff"], "Boolean", powerState)
      debugPrint("  SYNCED: " .. roomName .. " → " .. (powerState and "ON" or "OFF"))
    end
    ::continue::
  end
  powerSyncInProgress = false
end

local function separateGroup(group)
  if not components.roomCombiner then return end
  local groupRooms = {}
  for _, num in ipairs(group) do
    local name = numberToRoomMap[num]
    if name then groupRooms[name] = true end
  end
  local wallsClosed = 0
  for wallIndex = 1, 12 do
    local wallPair = wallRoomPairs[wallIndex]
    if not wallPair then goto continue end
    local allInGroup = true
    for _, roomName in ipairs(wallPair) do
      if not groupRooms[roomName] then allInGroup = false; break end
    end
    if allInGroup then
      local wallControl = components.roomCombiner["wall." .. wallIndex .. ".open"]
      if wallControl and wallControl.Boolean then
        setProp(wallControl, "Boolean", false)
        wallsClosed = wallsClosed + 1
        debugPrint("  Auto-separated wall " .. wallIndex .. " (" .. table.concat(wallPair, "/") .. ")")
      end
    end
    ::continue::
  end
  debugPrint("Group separation complete: " .. wallsClosed .. " walls closed")
  syncWallButtonStates()
  refreshRoutingAndVisibility()
end

local function onRoomPowerChanged(roomName, roomIndex)
  if powerSyncInProgress then return end
  debugPrint("Power state changed: " .. roomName)
  if not components.roomCombiner then updateWallStates(); return end

  local roomGroups = select(1, getCombinationContext())
  local changedRoomNum = roomNumberMap[roomName]
  local group          = nil
  for _, g in ipairs(roomGroups) do
    if tableContains(g, changedRoomNum) then group = g; break end
  end

  if not group or #group < 2 then
    debugPrint(roomName .. " is not in a combined group - no power sync needed")
    updateWallStates()
    return
  end

  local newPowerState = isRoomPoweredOn(roomName)
  debugPrint(roomName .. " → " .. (newPowerState and "ON" or "OFF"))

  if not newPowerState then
    local allOff = true
    for _, num in ipairs(group) do
      local name = numberToRoomMap[num]
      if name and isRoomPoweredOn(name) then allOff = false; break end
    end
    if allOff then
      debugPrint("All rooms in group powered OFF - auto-separating (Source: Power Sync)")
      separateGroup(group)
      updateWallStates()
      return
    end
  end

  local roomsToSync = {}
  for _, num in ipairs(group) do
    if num ~= changedRoomNum then
      local otherName = numberToRoomMap[num]
      if otherName then table.insert(roomsToSync, otherName) end
    end
  end
  if #roomsToSync > 0 then
    debugPrint("Syncing " .. (newPowerState and "ON" or "OFF") ..
      " to: " .. table.concat(roomsToSync, ", ") .. " (Source: Power Sync)")
    syncPowerToRooms(roomsToSync, newPowerState)
  end
  updateWallStates()
end

local function setupRoomPowerHandlers()
  debugPrint("Setting up room power handlers...")
  local count = 0
  for i, roomName in ipairs(roomNames) do
    local comp = components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      local capturedRoom  = roomName
      local capturedIndex = i
      if bind(comp["btnSystemOnOff"], function()
        onRoomPowerChanged(capturedRoom, capturedIndex)
      end) then
        count = count + 1
        debugPrint("  Power handler registered: " .. roomName)
      else
        debugPrint("  WARNING: Failed to bind power handler for " .. roomName)
      end
    else
      debugPrint("  WARNING: No btnSystemOnOff for " .. roomName)
    end
  end
  debugPrint("Room power handlers: " .. count .. "/" .. #roomNames .. " registered")
end

-- Individual Room Separation ----------------------------------------------------------

local function separateIndividualRoom(targetRoom)
  local wallsClosed = 0
  for wallIndex, otherWallPair in pairs(wallRoomPairs) do
    if wallIndex >= 13                              then goto continue end
    if not tableContains(otherWallPair, targetRoom) then goto continue end
    local hasOtherRoomOn = false
    for _, roomName in ipairs(otherWallPair) do
      if roomName ~= targetRoom and isRoomPoweredOn(roomName) then hasOtherRoomOn = true; break end
    end
    if not hasOtherRoomOn then
      setWallOpenState(wallIndex, false)
      wallsClosed = wallsClosed + 1
      debugPrint("  Closed wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ")")
    else
      debugPrint("  Wall " .. wallIndex .. " kept open (other rooms powered on)")
    end
    ::continue::
  end
  debugPrint("Individual separation complete: " .. wallsClosed .. " walls closed for " .. targetRoom)
  refreshRoutingAndVisibility()
end

local function handleIndividualRoomSeparation(wallIndex, wallButton, wallPair, uiState)
  local targetRoom = wallPair[1]
  if isRoomPoweredOn(targetRoom) then
    setProp(wallButton, "Boolean", not uiState)
    debugPrint("SAFETY BLOCK: Individual separation " .. wallIndex .. " (" .. targetRoom .. ") - room is powered ON")
    return
  end
  if uiState then
    debugPrint("Individual separation: " .. targetRoom .. " from all others (Source: Wall Button " .. wallIndex .. ")")
    separateIndividualRoom(targetRoom)
  end
  updateWallStates()
end

local function handleMultiRoomWall(wallIndex, wallButton, wallPair, uiState)
  if anyRoomInPairPoweredOn(wallPair) then
    setProp(wallButton, "Boolean", not uiState)
    debugPrint("SAFETY BLOCK: Wall " .. wallIndex .. " (" .. table.concat(wallPair, "/") .. ") - room powered ON")
    return
  end
  if uiState then applyWallInterlock(wallIndex) end
  if not components.roomCombiner then
    setProp(wallButton, "Boolean", not uiState)
    debugPrint("ERROR: No room combiner for wall " .. wallIndex)
    return
  end
  local wallControl = components.roomCombiner["wall." .. wallIndex .. ".open"]
  if not wallControl then
    setProp(wallButton, "Boolean", not uiState)
    debugPrint("ERROR: Wall control not found for wall " .. wallIndex)
    return
  end
  setProp(wallControl, "Boolean", uiState)
  debugPrint("Wall " .. wallIndex .. " (" .. table.concat(wallPair, "/") .. ") → " ..
    (uiState and "OPEN" or "CLOSED") .. " (Source: Wall Button)")
  if uiState then disableIndividualSeparationButtons(wallPair) end
  applyBidirectionalInterlock(wallIndex)
  updateWallStates()
end

local function handleWallButtonPress(wallIndex, wallButton)
  local wallPair = wallRoomPairs[wallIndex]
  if not wallPair then return end
  local uiState = wallButton.Boolean
  if wallIndex >= 13 and wallIndex <= 20 then
    handleIndividualRoomSeparation(wallIndex, wallButton, wallPair, uiState)
  else
    handleMultiRoomWall(wallIndex, wallButton, wallPair, uiState)
  end
end

-- Room Combiner Setup ------------------------------------------------------------------

local function cleanupRoomCombinerHandlers(oldComp)
  if not oldComp then return end
  local names = {"room.combiner.output.configuration"}
  for wallIdx = 1, 12 do
    names[#names + 1] = "wall." .. wallIdx .. ".open"
  end
  cleanupComponentHandlers(oldComp, names, function(msg) debugPrint("[Room Combiner] " .. msg) end)
end

local function setupRoomCombinerHandlers(roomCombinerComp)
  if not roomCombinerComp then return end
  local configControl = roomCombinerComp["room.combiner.output.configuration"]
  if not configControl then
    debugPrint("WARNING: room.combiner.output.configuration not found on room combiner")
    return
  end
  bind(configControl, function()
    debugPrint("Room combiner configuration changed - updating routing and visibility (Source: Room Combiner)")
    refreshRoutingAndVisibility()
  end)
  debugPrint("Registered: room combiner configuration handler")
  local wallHandlers = 0
  for wallIdx = 1, 12 do
    local wallControl = roomCombinerComp["wall." .. wallIdx .. ".open"]
    if wallControl then
      local capturedIdx = wallIdx
      bind(wallControl, function()
        local wallButton = controls.wallOpenButtons[capturedIdx]
        if not wallButton then return end
        setProp(wallButton, "Boolean", wallControl.Boolean)
        local wallPair = wallRoomPairs[capturedIdx]
        debugPrint("External wall change: Wall " .. capturedIdx ..
          (wallPair and " (" .. table.concat(wallPair, "/") .. ")" or "") ..
          " → " .. (wallControl.Boolean and "OPEN" or "CLOSED") .. " (Source: Room Combiner)")
        updateWallStates()
      end)
      wallHandlers = wallHandlers + 1
    end
  end
  debugPrint("Registered " .. wallHandlers .. " wall control event handlers")
end

-- Room Combinations --------------------------------------------------------------------

local function setupCombinationSelector()
  if not controls.selCombination then return end
  local choices = {}
  for _, combo in ipairs(roomCombinations) do table.insert(choices, combo.name) end
  controls.selCombination.Choices = choices
  debugPrint("Combination selector populated with " .. #choices .. " combinations")
end

local function getComboIndex(comboName)
  for idx, combo in ipairs(roomCombinations) do
    if combo.name == comboName then return idx end
  end
  return nil
end

local function activeRoomNamesList(combo)
  local list = {}
  for roomName, isActive in pairs(combo.activeRooms) do
    if isActive then table.insert(list, roomName) end
  end
  return list
end

local function setRoomStates(comboIdx, source)
  local combo = roomCombinations[comboIdx]
  if not combo then debugPrint("ERROR: Invalid combination index " .. tostring(comboIdx)); return false end
  debugPrint("Applying combination: " .. combo.name .. " (Source: " .. (source or "unknown") .. ")")

  if components.roomCombiner then
    for wallIndex, roomPair in pairs(wallRoomPairs) do
      if wallIndex > 12 then goto continueWall end
      local wallControl = components.roomCombiner["wall." .. wallIndex .. ".open"]
      if wallControl then
        local room1Active = combo.activeRooms[roomPair[1]] or false
        local room2Active = combo.activeRooms[roomPair[2]] or false
        setProp(wallControl, "Boolean", room1Active and room2Active)
      end
      ::continueWall::
    end
    syncWallButtonStates()
    local combinedRooms = activeRoomNamesList(combo)
    if #combinedRooms > 0 then disableIndividualSeparationButtons(combinedRooms) end
  else
    debugPrint("SKIP: Wall states - no room combiner component")
  end

  for i, roomName in ipairs(roomNames) do
    local comp = components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      local isActive = combo.activeRooms[roomName] or false
      setProp(comp["btnSystemOnOff"], "Boolean", isActive)
      debugPrint("  " .. roomName .. " → " .. (isActive and "ON" or "OFF"))
    else
      debugPrint("  WARNING: No btnSystemOnOff for " .. roomName)
    end
  end

  refreshRoutingAndVisibility()
  checkStatus()
  updateWallStates()
  return true
end

local function loadSlotArray(controlKey, componentType, updateFn)
  local arr = controls[controlKey]
  if not arr then return end
  for i, ctrl in ipairs(arr) do
    if ctrl and ctrl.String and ctrl.String ~= "" and ctrl.String ~= const.clearString then
      local comp = setComponent(ctrl, componentType)
      if comp then updateFn(ctrl.String, i) end
    end
  end
end

-----------------------------[ Events ]-----------------------------
local function registerEvents()
  debugPrint("--- Registering Event Handlers ---")

  bind(controls.compRoomCombiner, function(ctl)
    debugPrint("Room combiner selection changed: " .. tostring(ctl.String))
    cleanupRoomCombinerHandlers(components.roomCombiner)
    local comp = setComponent(ctl, "roomCombiner")
    components.roomCombiner = comp
    if not comp then return end
    setupRoomCombinerHandlers(comp)
    refreshRoutingAndVisibility()
    syncWallButtonStates()
  end)
  debugPrint("Registered: compRoomCombiner handler")

  bind(controls.selCombination, function(ctl)
    local comboIdx = getComboIndex(ctl.String)
    if comboIdx then setRoomStates(comboIdx, "Combination Selector") end
  end)
  debugPrint("Registered: selCombination handler")

  local rcCount = bindArray(controls.compRoomControls, function(i, ctl)
    debugPrint("Room control " .. i .. " changed: " .. tostring(ctl.String))
    local comp = setComponent(ctl, "roomControls")
    updateRoomComponent(comp and ctl.String or "", i)
    setupRoomPowerHandlers()
  end)
  debugPrint("Registered " .. rcCount .. " room control handlers")

  local arCount = bindArray(controls.compAudioRouter, function(i, ctl)
    debugPrint("Audio router " .. i .. " changed: " .. tostring(ctl.String))
    local comp = setComponent(ctl, "audioRouter")
    updateAudioRouter(comp and ctl.String or "", i)
  end)
  debugPrint("Registered " .. arCount .. " audio router handlers")

  local uciCount = bindArray(controls.uciButtons, function(i, ctl)
    debugPrint("RoomSelector " .. i .. " changed: " .. tostring(ctl.String))
    local comp = setComponent(ctl, "uciButtons")
    updateButtonRoomSelector(comp and ctl.String or "", i)
  end)
  debugPrint("Registered " .. uciCount .. " UCI button handlers")

  local wallCount = bindArray(controls.wallOpenButtons, function(i, wallButton)
    handleWallButtonPress(i, wallButton)
  end)
  debugPrint("Registered " .. wallCount .. " wall open button handlers")

  debugPrint("Event registration complete")
end

-----------------------------[ Init ]-----------------------------
local function loadInitialComponents()
  debugPrint("Loading initial component assignments...")

  loadSlotArray("compRoomControls", "roomControls", updateRoomComponent)
  loadSlotArray("compAudioRouter", "audioRouter", updateAudioRouter)
  loadSlotArray("uciButtons", "uciButtons", updateButtonRoomSelector)

  local combinerCtrl = controls.compRoomCombiner
  if combinerCtrl and combinerCtrl.String and combinerCtrl.String ~= "" and combinerCtrl.String ~= const.clearString then
    cleanupRoomCombinerHandlers(components.roomCombiner)
    local comp = setComponent(combinerCtrl, "roomCombiner")
    if comp then
      components.roomCombiner = comp
      setupRoomCombinerHandlers(comp)
      refreshRoutingAndVisibility()
      syncWallButtonStates()
    end
  end

  setupRoomPowerHandlers()
  debugPrint("Initial component loading complete")
end

local function init()
  debugPrint("=== Initialization Started ===")
  debugPrint("Configuration: roomName=" .. const.roomName .. ", debugging=" .. tostring(const.debug) ..
    ", rooms=" .. #roomNames .. ", wall buttons=20")

  setupCombinationSelector()
  discoverComponents()
  registerEvents()
  loadInitialComponents()
  checkStatus()
  updateWallStates()

  local delayTimer = Timer.New()
  delayTimer.EventHandler = function()
    delayTimer:Stop()
    debugPrint("Delayed RoomSelector visibility update executing...")
    updateRoomButtonVisibility()
  end
  delayTimer:Start(2.0)
  debugPrint("Scheduled delayed RoomSelector visibility update (2s)")

  debugPrint("=== Initialization Complete ===")
  debugPrint("Ready for operation")
end

-----------------------------[ Public API ]-----------------------------
DivisibleSpaceController = {
  applyAudioRouting          = applyAudioRouting,
  applyGainRouting           = applyGainRouting,
  updateRoomButtonVisibility = updateRoomButtonVisibility,
  updateWallStates           = updateWallStates,
  setRoomStates              = setRoomStates,
  debugCurrentRouterStates   = function()
    debugPrint("=== CURRENT ROUTER STATES ===")
    for i, roomName in ipairs(roomNames) do
      local router = components.audioRouter[i]
      debugPrint("  " .. roomName .. " → " .. (router and router["select.1"] and ("Input " .. router["select.1"].Value) or "NO ROUTER"))
    end
    debugPrint("=== END ROUTER STATES ===")
  end,
  debugCurrentGainStates = function()
    debugPrint("=== CURRENT GAIN STATES ===")
    for i, roomName in ipairs(roomNames) do
      local roomComp = components.roomControls[i]
      debugPrint("  " .. roomName .. " → " .. (roomComp and roomComp["compGains 1"] and roomComp["compGains 1"].String or "NO COMPONENT"))
    end
    debugPrint("=== END GAIN STATES ===")
  end,
}

-----------------------------[ Start ]-----------------------------
local ok, err = pcall(function()
  print("Initializing DivisibleSpaceController for " .. const.roomName .. "...")
  if not validateControls() then error("Control validation failed - check required UI controls") end
  normalizeControlArrays()
  init()
end)

if ok then
  print("✓ DivisibleSpaceController initialized for " .. const.roomName)
else
  local errMsg = tostring(err)
  print("✗ ERROR: Initialization failed: " .. errMsg)
  if errMsg:find("Control validation failed") then
    print("  Suggestion: Verify all required UI controls are named and connected")
  end
  if controls and controls.txtStatus then
    setProp(controls.txtStatus, "String", "INIT FAILED")
    setProp(controls.txtStatus, "Value", 2)
  end
end
