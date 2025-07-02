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
Controls['Text-Destination']
Controls['AV Mute BTN']
Controls['Destination Selector - ClickShare']
Controls['Destination Selector - Teams PC']
Controls['Destination Selector - Laptop Front']
Controls['Destination Selector - Laptop Rear']
Controls['Destination Selector - No Source']
Controls['Destination Feedback - No Source']
Controls['Destination - All Displays']
Controls['Extron DXP Signal Presence']
]]--

-- Set Up Named Components --
namedComponent_BDRMMNUCI_Layer_Selector = Component.New('BDRM-UCI Layer Selector')
namedComponent_BDRM_Status_Bar = Component.New('BDRM Status Bar')
namedComponent_Extron_DXP_84_HD_4K_Plus_ = Component.New('Extron DXP 84 HD 4K Plus ')
namedComponent_Extron_DXP_Routing_Controller = Component.New('Extron DXP Routing Controller')
namedComponent_BDRM_Power_State_SEL = Component.New('BDRM Power State_SEL')
namedComponent_HID_Conferencing_IOBMN01 = Component.New('HID Conferencing IOB-01')

-- Available Connections --

----  QSYS Initialization  ----


ExecuteCodeThatRunsFirst()

function Deselect_ALL_Sources_MN_MONMN02()
  Delect_ALL_Displays_MN_Destinations()
  namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '0'
  Controls['Destination Feedback - No Source'][2].Boolean = false
end


function Deselect_ALL_Sources_MN_MONMN03()
  Delect_ALL_Displays_MN_Destinations()
  namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '0'
  Controls['Destination Feedback - No Source'][3].Boolean = false
end


function Deselect_ALL_Sources_MN_MONMN04()
  Delect_ALL_Displays_MN_Destinations()
  namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '0'
  Controls['Destination Feedback - No Source'][4].Boolean = false
end


function Deselect_ALL_Sources_MN_ALL_Displays()
  Deselect_ALL_Sources_MN_MONMN01()
  Deselect_ALL_Sources_MN_MONMN02()
  Deselect_ALL_Sources_MN_MONMN03()
  Deselect_ALL_Sources_MN_MONMN04()
end


function Deselect_ALL_Sources_MN_MONMN01()
  Delect_ALL_Displays_MN_Destinations()
  namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '0'
  Controls['Destination Feedback - No Source'][1].Boolean = false
end


function Delect_ALL_Displays_MN_Destinations()
  Controls['Destination - All Displays'][1].Boolean = false
  Controls['Destination - All Displays'][2].Boolean = false
  Controls['Destination - All Displays'][3].Boolean = false
  Controls['Destination - All Displays'][4].Boolean = false
  Controls['Destination - All Displays'][5].Boolean = false
end


Controls['Destination Selector - ClickShare'][1].EventHandler = function()
  local control_index = 1
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('ClickShare to MON-0%01d' , tostring(control_index) ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Destination - All Displays'][1].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - ClickShare'][2].EventHandler = function()
  local control_index = 2
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('ClickShare to MON-0%01d' , tostring(control_index) ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Destination - All Displays'][1].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - ClickShare'][3].EventHandler = function()
  local control_index = 3
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('ClickShare to MON-0%01d' , tostring(control_index) ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Destination - All Displays'][1].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - ClickShare'][4].EventHandler = function()
  local control_index = 4
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('ClickShare to MON-0%01d' , tostring(control_index) ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Destination - All Displays'][1].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - ClickShare'][5].EventHandler = function()
  local control_index = 5
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('ClickShare to MON-0%01d' , tostring(control_index) ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '1'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '1'
    Controls['Destination - All Displays'][1].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end

Controls['Destination Selector - Teams PC'][1].EventHandler = function()
  local control_index = 1
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Teams PC to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    Controls['Text-Destination'].String = 'Front Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
      Controls['Text-Destination'].String = 'Front Displays'

    end,0.2)
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    Controls['Text-Destination'].String = 'Rear Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
      Controls['Text-Destination'].String = 'Rear Displays'

    end,0.2)
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
    Controls['Destination - All Displays'][2].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Teams PC'][2].EventHandler = function()
  local control_index = 2
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Teams PC to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    Controls['Text-Destination'].String = 'Front Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
      Controls['Text-Destination'].String = 'Front Displays'

    end,0.2)
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    Controls['Text-Destination'].String = 'Rear Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
      Controls['Text-Destination'].String = 'Rear Displays'

    end,0.2)
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
    Controls['Destination - All Displays'][2].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Teams PC'][3].EventHandler = function()
  local control_index = 3
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Teams PC to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    Controls['Text-Destination'].String = 'Front Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
      Controls['Text-Destination'].String = 'Front Displays'

    end,0.2)
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    Controls['Text-Destination'].String = 'Rear Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
      Controls['Text-Destination'].String = 'Rear Displays'

    end,0.2)
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
    Controls['Destination - All Displays'][2].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Teams PC'][4].EventHandler = function()
  local control_index = 4
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Teams PC to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    Controls['Text-Destination'].String = 'Front Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
      Controls['Text-Destination'].String = 'Front Displays'

    end,0.2)
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    Controls['Text-Destination'].String = 'Rear Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
      Controls['Text-Destination'].String = 'Rear Displays'

    end,0.2)
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
    Controls['Destination - All Displays'][2].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Teams PC'][5].EventHandler = function()
  local control_index = 5
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Teams PC to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    Controls['Text-Destination'].String = 'Front Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
      Controls['Text-Destination'].String = 'Front Displays'

    end,0.2)
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    Controls['Text-Destination'].String = 'Rear Displays'
    Timer.CallAfter(function()
        namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
      Controls['Text-Destination'].String = 'Rear Displays'

    end,0.2)
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '3'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '2'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '3'
    Controls['Destination - All Displays'][2].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end

Controls['Destination Selector - Laptop Front'][1].EventHandler = function()
  local control_index = 1
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Laptop Front to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Destination - All Displays'][3].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Front'][2].EventHandler = function()
  local control_index = 2
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Laptop Front to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Destination - All Displays'][3].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Front'][3].EventHandler = function()
  local control_index = 3
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Laptop Front to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Destination - All Displays'][3].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Front'][4].EventHandler = function()
  local control_index = 4
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Laptop Front to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Destination - All Displays'][3].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Front'][5].EventHandler = function()
  local control_index = 5
  Delect_ALL_Displays_MN_Destinations()
  print(string.format('Laptop Front to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '4'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '4'
    Controls['Destination - All Displays'][3].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end

Controls['Destination Selector - Laptop Rear'][1].EventHandler = function()
  local control_index = 1
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('Laptop Rear to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Destination - All Displays'][4].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Rear'][2].EventHandler = function()
  local control_index = 2
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('Laptop Rear to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Destination - All Displays'][4].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Rear'][3].EventHandler = function()
  local control_index = 3
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('Laptop Rear to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Destination - All Displays'][4].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Rear'][4].EventHandler = function()
  local control_index = 4
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('Laptop Rear to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Destination - All Displays'][4].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - Laptop Rear'][5].EventHandler = function()
  local control_index = 5
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('Laptop Rear to MON-0%01d' , control_index ))
  if control_index == 1 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_2'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_3'].String = '5'
    namedComponent_Extron_DXP_84_HD_4K_Plus_['output_4'].String = '5'
    Controls['Destination - All Displays'][4].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end

Controls['Destination Selector - No Source'][1].EventHandler = function()
  local control_index = 1
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('No Source to MON-0%01d' , control_index ))
  if control_index == 1 then
    Deselect_ALL_Sources_MN_MONMN01()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    Deselect_ALL_Sources_MN_MONMN02()
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    Deselect_ALL_Sources_MN_MONMN03()
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    Deselect_ALL_Sources_MN_MONMN04()
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    Deselect_ALL_Sources_MN_ALL_Displays()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Destination - All Displays'][5].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - No Source'][2].EventHandler = function()
  local control_index = 2
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('No Source to MON-0%01d' , control_index ))
  if control_index == 1 then
    Deselect_ALL_Sources_MN_MONMN01()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    Deselect_ALL_Sources_MN_MONMN02()
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    Deselect_ALL_Sources_MN_MONMN03()
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    Deselect_ALL_Sources_MN_MONMN04()
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    Deselect_ALL_Sources_MN_ALL_Displays()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Destination - All Displays'][5].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - No Source'][3].EventHandler = function()
  local control_index = 3
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('No Source to MON-0%01d' , control_index ))
  if control_index == 1 then
    Deselect_ALL_Sources_MN_MONMN01()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    Deselect_ALL_Sources_MN_MONMN02()
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    Deselect_ALL_Sources_MN_MONMN03()
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    Deselect_ALL_Sources_MN_MONMN04()
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    Deselect_ALL_Sources_MN_ALL_Displays()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Destination - All Displays'][5].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - No Source'][4].EventHandler = function()
  local control_index = 4
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('No Source to MON-0%01d' , control_index ))
  if control_index == 1 then
    Deselect_ALL_Sources_MN_MONMN01()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    Deselect_ALL_Sources_MN_MONMN02()
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    Deselect_ALL_Sources_MN_MONMN03()
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    Deselect_ALL_Sources_MN_MONMN04()
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    Deselect_ALL_Sources_MN_ALL_Displays()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Destination - All Displays'][5].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end


Controls['Destination Selector - No Source'][5].EventHandler = function()
  local control_index = 5
  Delect_ALL_Displays_MN_Destinations()
  print(control_index)
  print(string.format('No Source to MON-0%01d' , control_index ))
  if control_index == 1 then
    Deselect_ALL_Sources_MN_MONMN01()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Text-Destination'].String = 'Front Left'
   elseif control_index == 2 then
    Deselect_ALL_Sources_MN_MONMN02()
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Text-Destination'].String = 'Front Right'
   elseif control_index == 3 then
    Deselect_ALL_Sources_MN_MONMN03()
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Text-Destination'].String = 'Rear Left'
   elseif control_index == 4 then
    Deselect_ALL_Sources_MN_MONMN04()
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Text-Destination'].String = 'Rear Right '
   elseif control_index == 5 then
    Deselect_ALL_Sources_MN_ALL_Displays()
    Controls['Destination Feedback - No Source'][1].Boolean = true
    Controls['Destination Feedback - No Source'][2].Boolean = true
    Controls['Destination Feedback - No Source'][3].Boolean = true
    Controls['Destination Feedback - No Source'][4].Boolean = true
    Controls['Destination - All Displays'][5].Boolean = true
    Controls['Text-Destination'].String = 'All Displays'
    Timer.CallAfter(function()
        Controls['Text-Destination'].String = ''

    end,3)
  end
end

Controls['Extron DXP Signal Presence'][1].EventHandler = function()
  local control_index = 1
  if namedComponent_BDRM_Power_State_SEL['value'].String == 'ON' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end


Controls['Extron DXP Signal Presence'][2].EventHandler = function()
  local control_index = 2
  if namedComponent_BDRM_Power_State_SEL['value'].String == 'ON' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end


Controls['Extron DXP Signal Presence'][3].EventHandler = function()
  local control_index = 3
  if namedComponent_BDRM_Power_State_SEL['value'].String == 'ON' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end


Controls['Extron DXP Signal Presence'][4].EventHandler = function()
  local control_index = 4
  if namedComponent_BDRM_Power_State_SEL['value'].String == 'ON' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end


Controls['Extron DXP Signal Presence'][5].EventHandler = function()
  local control_index = 5
  if namedComponent_BDRM_Power_State_SEL['value'].String == 'ON' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end


-- Source = No Source on System Initialize
namedComponent_SYS_MN_Initialize_Trigger['percent_output'].EventHandler = function(ctl)
  if namedComponent_SYS_MN_Initialize_Trigger['percent_output'].Position == 1 then
    Deselect_ALL_Sources_MN_ALL_Displays()
  end
end
-- Teams PC - Disable Output buttons for Mon-02 and Mon-04
namedComponent_BDRMMNUCI_Layer_Selector['selector'].EventHandler = function(ctl)
  Controls['Destination Selector - Teams PC'][2].Color = '#ff6666'
  Controls['Destination Selector - Teams PC'][4].Color = '#ff6666'
  Controls['Destination Selector - Teams PC'][2].Legend = 'N/A'
  Controls['Destination Selector - Teams PC'][4].Legend = 'N/A'
end
-- Auto Switch Priority - System has powered ON
namedComponent_BDRM_Status_Bar['percent_1'].EventHandler = function(ctl)
  if namedComponent_BDRM_Status_Bar['percent_1'].String == '100%' then
    if namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean or namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 3'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 4'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 5'].Boolean then
      NamedControl.Trigger('BDRM-UCI-Laptop Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 1'].Boolean then
      NamedControl.Trigger('BDRM-UCI-WPres Page_SEL')
     elseif namedComponent_Extron_DXP_Routing_Controller['Extron DXP Signal Presence 2'].Boolean then
      NamedControl.Trigger('BDRM-UCI-PC Conf Page_ SEL')
    end
  end
end
-- Auto Switch Priority - System is ON


ExecuteCodeThatRunsLast()