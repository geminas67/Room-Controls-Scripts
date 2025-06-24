--[[
  NV32-UCI Integration Test Script
  Author: Nikolas Smith, Q-SYS
  2025-06-23
  Version: 1.0

  This script tests the UCI button monitoring functionality for NV32 control.
]]--

print("=== NV32-UCI Integration Test Script Started ===")

-- Test UCI button monitoring
local function testUCIButtonMonitoring()
    print("=== Testing UCI Button Monitoring ===")
    
    -- Define the UCI button to NV32 input mapping
    local uciToNV32Mapping = {
        [7] = {input = 5, name = "HDMI2"}, -- btnNav07 → HDMI2
        [8] = {input = 4, name = "HDMI1"}, -- btnNav08 → HDMI1  
        [9] = {input = 6, name = "HDMI3"}  -- btnNav09 → HDMI3
    }
    
    -- Store previous button states to detect changes
    local previousButtonStates = {}
    
    -- Create a timer to monitor button states without overriding EventHandlers
    local testMonitorTimer = Timer.New()
    testMonitorTimer.EventHandler = function()
        for uciButton, mapping in pairs(uciToNV32Mapping) do
            local buttonName = "btnNav" .. string.format("%02d", uciButton)
            if Controls[buttonName] then
                local currentState = Controls[buttonName].Boolean
                local previousState = previousButtonStates[uciButton]
                
                -- Check if button state changed to true
                if currentState and not previousState then
                    print("🎯 TEST: UCI Button " .. uciButton .. " pressed, should switch NV32 to " .. mapping.name)
                    print("🎯 TEST: Target input = " .. mapping.input)
                    
                    -- Try to control NV32 directly if available
                    if Controls.devNV32 and Controls.devNV32.String ~= "" then
                        local nv32Component = Component.New(Controls.devNV32.String)
                        if nv32Component then
                            nv32Component["hdmi.out.1.select.index"].Value = mapping.input
                            print("✓ TEST: Direct NV32 control successful - Set Output 1 to Input " .. mapping.input)
                        else
                            print("⚠ TEST: Failed to create NV32 component reference")
                        end
                    else
                        print("⚠ TEST: NV32 device not selected or not available")
                    end
                end
                
                -- Update previous state
                previousButtonStates[uciButton] = currentState
            end
        end
        
        -- Continue monitoring
        testMonitorTimer:Start(0.1) -- Check every 100ms
    end
    
    -- Start the monitoring timer
    testMonitorTimer:Start(0.1)
    print("✓ Timer-based UCI button monitoring started")
    print("=== UCI Button Monitoring Test Setup Complete ===")
end

-- Test NV32 device availability
local function testNV32Device()
    print("=== Testing NV32 Device Availability ===")
    
    if Controls.devNV32 then
        print("✓ NV32 device control found")
        if Controls.devNV32.String ~= "" then
            print("✓ NV32 device selected: " .. Controls.devNV32.String)
            
            -- Try to create component reference
            local success, component = pcall(function()
                return Component.New(Controls.devNV32.String)
            end)
            
            if success and component then
                print("✓ NV32 component reference created successfully")
                
                -- Test if we can read the current output selection
                local currentInput = component["hdmi.out.1.select.index"].Value
                print("✓ Current Output 1 input: " .. tostring(currentInput))
                
                return true
            else
                print("⚠ Failed to create NV32 component reference")
                return false
            end
        else
            print("⚠ No NV32 device selected")
            return false
        end
    else
        print("⚠ NV32 device control not found")
        return false
    end
end

-- Run tests
local nv32Available = testNV32Device()
testUCIButtonMonitoring()

if nv32Available then
    print("=== All Tests Passed ===")
    print("🎯 Ready to test UCI button functionality!")
    print("📋 Press UCI navigation buttons 7, 8, or 9 to test NV32 input switching")
else
    print("=== Tests Completed with Warnings ===")
    print("⚠ NV32 device not available - UCI buttons will be monitored but NV32 control will not work")
end

print("=== NV32-UCI Integration Test Script Complete ===") 