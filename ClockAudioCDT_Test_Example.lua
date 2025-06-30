--[[
  ClockAudioCDT Hook State Test Example
  Author: Test Script
  Date: 2025-01-27
  Description: Simple example of how to test hook state logic using the test button
]]--

-- This script demonstrates how to test the ClockAudioCDTMicController
-- hook state logic using the built-in test mode functionality

-- Example 1: Basic Hook State Testing
function testHookStateLogic()
    print("=== Testing Hook State Logic ===")
    
    if myClockAudioCDTMicController then
        -- Check if test mode is active
        if myClockAudioCDTMicController:isTestModeActive() then
            print("Hook state test mode is active")
            
            -- Get current hook state
            local hookState = myClockAudioCDTMicController:getHookState()
            print("Current Hook State: " .. tostring(hookState))
            
            -- Test hook state transitions
            print("\nTesting Hook State Transitions:")
            
            -- Simulate going off-hook
            print("1. Going OFF-HOOK...")
            myClockAudioCDTMicController.testModule.toggleHookState()
            Timer.CallAfter(function()
                print("   Hook state changed to: " .. tostring(myClockAudioCDTMicController:getHookState()))
            end, 0.5)
            
            -- Simulate going on-hook after 2 seconds
            Timer.CallAfter(function()
                print("2. Going ON-HOOK...")
                myClockAudioCDTMicController.testModule.toggleHookState()
                Timer.CallAfter(function()
                    print("   Hook state changed to: " .. tostring(myClockAudioCDTMicController:getHookState()))
                end, 0.5)
            end, 2.0)
            
        else
            print("Hook state test mode is not active - call sync component may be present")
        end
    else
        print("ClockAudioCDTMicController not available")
        print("ERROR: Controller failed to initialize. Check the following:")
        print("1. Required Q-SYS controls are missing from your design")
        print("2. Add the following controls to your Q-SYS design:")
        print("   - compMicBox (ClockAudio CDT Mic Box component)")
        print("   - compMicMixer (Mic Mixer component)")
        print("   - compCallSync (Call Sync component)")
        print("   - compVideoBridge (Video Bridge component)")
        print("   - compRoomControls (Room Controls component)")
        print("   - btnTestHookState (Button control for testing)")
        print("3. Ensure all components are properly connected")
    end
end

-- Example 2: Manual Test Instructions
function showManualTestInstructions()
    print("\n=== Manual Test Instructions ===")
    
    if myClockAudioCDTMicController then
        print("To test hook state logic manually:")
        print("1. Ensure btnTestHookState control is added to your Q-SYS design")
        print("2. Click btnTestHookState to toggle between ON-HOOK and OFF-HOOK")
        print("3. Observe microphone LED behavior:")
        print("   - ON-HOOK: LEDs should be OFF")
        print("   - OFF-HOOK: LEDs should be ON (green when unmuted, red when muted)")
        print("4. Use Q-SYS emulation for other components (mute, privacy, fire alarm, etc.)")
        
        -- Check if test mode is active
        if myClockAudioCDTMicController:isTestModeActive() then
            print("\n✓ Hook state test mode is active")
            print("✓ Ready for testing")
        else
            print("\n✗ Hook state test mode is not active")
            print("  - Check that compCallSync is not selected")
            print("  - Verify btnTestHookState control exists")
        end
    else
        print("Controller not available")
        print("\nSETUP INSTRUCTIONS:")
        print("1. Open Q-SYS Designer")
        print("2. Add the following components to your design:")
        print("   - ClockAudio CDT Mic Box (compMicBox)")
        print("   - Mic Mixer (compMicMixer)")
        print("   - Call Sync (compCallSync)")
        print("   - Video Bridge (compVideoBridge)")
        print("   - Room Controls (compRoomControls)")
        print("3. Add a Button control named 'btnTestHookState'")
        print("4. Save and reload the design")
        print("5. Run this test script again")
    end
end

-- Example 3: LED State Verification
function verifyLEDStates()
    print("\n=== LED State Verification ===")
    
    if myClockAudioCDTMicController then
        local hookState = myClockAudioCDTMicController:getHookState()
        print("Current Hook State: " .. tostring(hookState))
        
        if hookState then
            print("Expected LED behavior:")
            print("  Hook: OFF-HOOK - LEDs should be ON")
            print("  Note: LED color depends on mute/privacy state (use Q-SYS emulation)")
        else
            print("Expected LED behavior:")
            print("  Hook: ON-HOOK - LEDs should be OFF")
        end
        
        print("\nFor other states, use Q-SYS component emulation:")
        print("- Mute state: Emulate call sync mute control")
        print("- Privacy state: Emulate video bridge privacy control")
        print("- Fire alarm: Emulate room controls fire alarm")
        print("- System power: Emulate room controls system power")
    else
        print("Controller not available")
        print("Complete the setup instructions above first")
    end
end

-- Example 4: Control Validation Check
function checkRequiredControls()
    print("\n=== Required Controls Check ===")
    
    local missingControls = {}
    local availableControls = {}
    
    -- Check each required control
    local requiredControls = {
        "compMicBox",
        "compMicMixer", 
        "compCallSync",
        "compVideoBridge",
        "compRoomControls",
        "btnTestHookState"
    }
    
    for _, controlName in ipairs(requiredControls) do
        if Controls[controlName] then
            table.insert(availableControls, controlName)
            print("✓ " .. controlName .. " - Available")
        else
            table.insert(missingControls, controlName)
            print("✗ " .. controlName .. " - Missing")
        end
    end
    
    print("\nSummary:")
    print("Available controls: " .. #availableControls .. "/" .. #requiredControls)
    print("Missing controls: " .. #missingControls .. "/" .. #requiredControls)
    
    if #missingControls > 0 then
        print("\nMissing controls that need to be added:")
        for _, controlName in ipairs(missingControls) do
            print("  - " .. controlName)
        end
    end
    
    return #missingControls == 0
end

-- Main test execution
print("ClockAudioCDT Hook State Test Example")
print("======================================")

-- Check required controls first
local controlsReady = checkRequiredControls()

-- Wait for controller to initialize
Timer.CallAfter(function()
    print("\nStarting hook state test...")
    
    if controlsReady then
        -- Run basic hook state test
        testHookStateLogic()
        
        -- Show manual test instructions
        Timer.CallAfter(function()
            showManualTestInstructions()
        end, 5.0)
        
        -- Verify LED states
        Timer.CallAfter(function()
            verifyLEDStates()
        end, 10.0)
    else
        print("Cannot run tests - required controls are missing")
        print("Please add the missing controls to your Q-SYS design and reload")
    end
    
end, 2.0)

print("Test example scheduled - check console output for results") 