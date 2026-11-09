--[[
  Input Selector
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2026-11-05
  Selects the input for the projector
]]

-------------------[ Configuration ]-------------------
compExitTrain = Component.New("compExitTrain")
defaultInput = 0
projPower = false

function selectInput(selected)

  if selected ~= 5 then
    Controls.btnPowerOn.Trigger()
    projPower = true
    print(string.format('Projector power : On', projPower))
  end

  for i = 1, #Controls.btnInput do
    Controls.btnInput[i].Boolean = (i == selected)
  
  end 
  print(string.format('Input %02d was selected.', selected))
  print('--------------------------------')
end

for i = 1, #Controls.btnInput do
  Controls.btnInput[i].EventHandler = function()
    selectInput(i)
  end
end

compExitTrain["momentary 1"].EventHandler = function(ctl)
  projPower = false
  print(string.format('Projector power : Off', projPower))
  selectInput(defaultInput)
end