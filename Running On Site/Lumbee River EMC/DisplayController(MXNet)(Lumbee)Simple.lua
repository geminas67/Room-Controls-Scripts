---- QSYS Initialization ----
----  BEGIN CODE THAT RUNS LAST
ListOfCodeThatRunsLast = {}
ExecuteCodeThatRunsLast = function()
  for ectrl_i, ectrl_fun in pairs(ListOfCodeThatRunsLast) do
    ectrl_fun()
  end
end
----  END CODE THAT RUNS LAST
----  BEGIN CODE THAT RUNS FIRST
ListOfCodeThatRunsFirst = {}
ExecuteCodeThatRunsFirst = function()
  for ectrl_i, ectrl_fun in pairs(ListOfCodeThatRunsFirst) do
    ectrl_fun()
  end
end
----  END CODE THAT RUNS FIRST

-- Available Controls --
--[[
Controls['btnDisplayPowerOffOn']
]]--

-- Set Up Named Components --
namedComponent_BDRM_Power_State_SEL = Component.New('BDRM Power State_SEL')
namedComponent_compDisplayControlsDec28 = Component.New('compDisplayControlsDec28')
namedComponent_compDisplayControlsDec29 = Component.New('compDisplayControlsDec29')
namedComponent_compDisplayControlsDec30 = Component.New('compDisplayControlsDec30')

-- Display components array for batch operations
local displayComponents = {
  namedComponent_compDisplayControlsDec28,
  namedComponent_compDisplayControlsDec29,
  namedComponent_compDisplayControlsDec30
}

-- Available Connections --

----  QSYS Initialization  ----

-------------------[ Control Validation ]-------------------
local function validateControls()
  local required = { 
    btnDisplayPowerOffOn = Controls['btnDisplayPowerOffOn'],
    selectorComponent = namedComponent_BDRM_Power_State_SEL
  }
  local missing = {}
  
  for name, ctrl in pairs(required) do
    if not ctrl then
      table.insert(missing, name)
    end
  end
  
  if #missing > 0 then
    print("WARNING: DisplayController validation - Missing controls:")
    for _, name in ipairs(missing) do
      print("  - " .. name)
    end
    return false
  end
  
  print("DisplayController validation passed")
  return true
end

ExecuteCodeThatRunsFirst()

-------------------[ Utility Functions ]-------------------
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function normalizeControlArrays()
  if Controls['btnDisplayPowerOffOn'] and not isArr(Controls['btnDisplayPowerOffOn']) then
    Controls['btnDisplayPowerOffOn'] = { Controls['btnDisplayPowerOffOn'] }
  end
end

-- Validate controls
validateControls()

-- Normalize control arrays
normalizeControlArrays()

local function setProp(ctrl, prop, val)
  if not ctrl or ctrl[prop] == val then return false end
  ctrl[prop] = val
  return true
end

local function bind(ctrl, handler)
  if ctrl then ctrl.EventHandler = handler end
end

local function pulse(ctrl, duration)
  if not ctrl then return end
  local pulseTime = duration or 0.2
  ctrl.Boolean = true
  Timer.CallAfter(function()
    if ctrl then ctrl.Boolean = false end
  end, pulseTime)
end

function funcInterlock(argArray, argControlThatIsOn)
  local buttonArray = Controls['btnDisplayPowerOffOn']
  if not buttonArray then return end
  
  -- Interlock buttons: set all false, then set active one to true
  for i = 1, 2 do
    if buttonArray[i] then
      setProp(buttonArray[i], "Boolean", i == argControlThatIsOn)
    end
  end
  
  -- Set all display components to same state (1 = false, 2 = true)
  local displayState = argControlThatIsOn == 2
  for _, comp in ipairs(displayComponents) do
    if comp and comp['btnDisplayPowerSingle 1'] then
      setProp(comp['btnDisplayPowerSingle 1'], "Boolean", displayState)
    end
  end
end


bind(Controls['btnDisplayPowerOffOn'][1], function()
  local control_index = 1
  print('----------------------------------------')
  print(string.format('The index of button pressed is %01d.' , control_index ))
  funcInterlock(Controls['btnDisplayPowerOffOn'], control_index)
end)

bind(Controls['btnDisplayPowerOffOn'][2], function()
  local control_index = 2
  print('----------------------------------------')
  print(string.format('The index of button pressed is %01d.' , control_index ))
  funcInterlock(Controls['btnDisplayPowerOffOn'], control_index)
end)


bind(namedComponent_BDRM_Power_State_SEL['selector'], function(ctl)
  -- In Q-Sys, programmatic control changes don't trigger EventHandlers
  -- So we call funcInterlock directly instead of pulsing the button
  if namedComponent_BDRM_Power_State_SEL['selector.1'].Boolean then
    -- Selector is ON - power displays on
    funcInterlock(Controls['btnDisplayPowerOffOn'], 2)
   else
    -- Selector is OFF - power displays off
    funcInterlock(Controls['btnDisplayPowerOffOn'], 1)
  end
end)

ExecuteCodeThatRunsLast()