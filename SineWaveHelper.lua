--[[
    Sine Generator Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to set the frequency of the sine wave generator.
]]

local sineGen = Component.New('sineGenerator')

local valuesSines = { '400', '800', '1000', '2000', '4000', '8000' }

local hzProfiles = {
  { label = 'HF',  min = 500,  max = 16000 },
  { label = 'Sub', min = 40,   max = 160   },
}
local activeRange = 1

-- limit the sweep knobs to the active Hz profile range
local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function interlock(btns, index)
  for i, btn in ipairs(btns) do btn.Boolean = (i == index) end
end

local function clampHzKnobs()
  local profile = hzProfiles[activeRange]
  Controls.knbHzStart.Value = clamp(Controls.knbHzStart.Value, profile.min, profile.max)
  Controls.knbHzEnd.Value = clamp(Controls.knbHzEnd.Value, profile.min, profile.max)
end

local function updatePresetButtons()
  local profile = hzProfiles[activeRange]
  for i, btn in ipairs(Controls.btnPreset) do
    local hz = tonumber(valuesSines[i])
    local outOfRange = hz < profile.min or hz > profile.max
    btn.IsDisabled = outOfRange
    if outOfRange then btn.Boolean = false end
  end
end

local function setSine(i)
  if Controls.btnPreset[i].IsDisabled then return end
  sineGen.frequency.Value = tonumber(valuesSines[i])
  interlock(Controls.btnPreset, i)
end

for i = 1, #valuesSines do
  Controls.btnPreset[i].Legend = valuesSines[i] .. 'Hz'
  Controls.btnPreset[i].EventHandler = function() setSine(i) end
end

-------------------[ Sweep Frequency ]-------------------
local sweepTimer = Timer.New()
local hzStart, hzEnd, freqRatio, sweepDuration = 0, 0, 1, 0
local sweepStartTime, elapsedPrePause = 0, 0
local isSweeping, isPaused = false, false

local function setHzRange(i)
  local profile = hzProfiles[i]
  if not profile then return end
  interlock(Controls.btnHzRange, i)
  activeRange = i
  updatePresetButtons()
  Controls.knbHzStart.Value, Controls.knbHzEnd.Value = profile.min, profile.max
  sweepTimer:Stop()
  isSweeping, isPaused, elapsedPrePause = false, false, 0
end

local function setFreq(Hz)
  sineGen.frequency.RampTime = 0
  sineGen.frequency.Value = Hz
end

local function logSweepStart()
  hzStart = Controls.knbHzStart.Value
  hzEnd = Controls.knbHzEnd.Value
  sweepDuration = Controls.knbDuration.Value
  if hzStart <= 0 or hzEnd <= hzStart or sweepDuration <= 0 then return end

  freqRatio = hzEnd / hzStart
  sweepTimer:Stop()
  elapsedPrePause = 0
  sweepStartTime = Timer.Now()
  setFreq(hzStart)
  sineGen.mute.Boolean = false
  isSweeping, isPaused = true, false
  sweepTimer:Start(0.05)
end

local function logSweepPause()
  if not isSweeping then return end
  elapsedPrePause = elapsedPrePause + (Timer.Now() - sweepStartTime)
  sweepTimer:Stop()
  setFreq(sineGen.frequency.Value)
  sineGen.mute.Boolean = true
  isSweeping, isPaused = false, true
end

local function logSweepResume()
  if not isPaused or hzStart <= 0 or hzEnd <= hzStart or sweepDuration <= 0 then return end
  sweepStartTime = Timer.Now()
  sineGen.mute.Boolean = false
  isSweeping, isPaused = true, false
  sweepTimer:Start(0.05)
end

sweepTimer.EventHandler = function()
  local progress = math.min((elapsedPrePause + Timer.Now() - sweepStartTime) / sweepDuration, 1)
  setFreq(hzStart * (freqRatio ^ progress))
  if progress >= 1 then
    sweepTimer:Stop()
    setFreq(hzEnd)
    isSweeping, isPaused, elapsedPrePause = false, false, 0
  end
end

local sweepLabels = { 'Start/Restart', 'Pause', 'Resume' }
for i, btn in ipairs(Controls.btnSweep) do
  btn.Legend = sweepLabels[i]
  btn.EventHandler = ({ logSweepStart, logSweepPause, logSweepResume })[i]
end

for i, btn in ipairs(Controls.btnHzRange) do
  btn.Legend = hzProfiles[i].label
  btn.EventHandler = function() setHzRange(i) end
end

Controls.knbHzStart.EventHandler = clampHzKnobs
Controls.knbHzEnd.EventHandler = clampHzKnobs
setHzRange(1)
