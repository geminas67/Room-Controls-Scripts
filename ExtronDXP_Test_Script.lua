--[[
  Extron DXP Matrix Routing Controller - Test Script
  Author: Nikolas Smith, Q-SYS
  2025-01-27
  
  Test script to validate the refactored Extron DXP Controller functionality
]]--

-- Test function to validate controller initialization
function TestExtronDXPController()
    print("=== Extron DXP Controller Test ===")
    
    -- Check if controller was created successfully
    if not _G.ExtronDXPController then
        print("ERROR: ExtronDXPController not found in global scope")
        return false
    end
    
    local controller = _G.ExtronDXPController
    
    -- Test 1: Check controller properties
    print("Test 1: Controller Properties")
    if not controller.inputs then
        print("ERROR: inputs property not found")
        return false
    end
    
    if not controller.outputs then
        print("ERROR: outputs property not found")
        return false
    end
    
    if not controller.uciLayerToInput then
        print("ERROR: uciLayerToInput property not found")
        return false
    end
    
    print("✓ Controller properties validated")
    
    -- Test 2: Check input mappings
    print("Test 2: Input Mappings")
    local expectedInputs = {
        ClickShare = 1,
        TeamsPC = 2,
        LaptopFront = 4,
        LaptopRear = 5,
        NoSource = 0
    }
    
    for name, value in pairs(expectedInputs) do
        if controller.inputs[name] ~= value then
            print("ERROR: Input mapping mismatch for " .. name .. " (expected " .. value .. ", got " .. tostring(controller.inputs[name]) .. ")")
            return false
        end
    end
    
    print("✓ Input mappings validated")
    
    -- Test 3: Check UCI layer mappings
    print("Test 3: UCI Layer Mappings")
    local expectedUCIMappings = {
        [7] = controller.inputs.TeamsPC,
        [8] = controller.inputs.LaptopFront,
        [9] = controller.inputs.ClickShare
    }
    
    for layer, input in pairs(expectedUCIMappings) do
        if controller.uciLayerToInput[layer] ~= input then
            print("ERROR: UCI mapping mismatch for layer " .. layer .. " (expected " .. input .. ", got " .. tostring(controller.uciLayerToInput[layer]) .. ")")
            return false
        end
    end
    
    print("✓ UCI layer mappings validated")
    
    -- Test 4: Check source priority
    print("Test 4: Source Priority")
    if not controller.sourcePriority then
        print("ERROR: sourcePriority property not found")
        return false
    end
    
    if #controller.sourcePriority ~= 5 then
        print("ERROR: Expected 5 source priorities, got " .. #controller.sourcePriority)
        return false
    end
    
    print("✓ Source priority validated")
    
    -- Test 5: Check component discovery
    print("Test 5: Component Discovery")
    local discovered = controller:discoverComponents()
    
    if not discovered then
        print("ERROR: Component discovery failed")
        return false
    end
    
    if not discovered.ExtronDXPNames then
        print("ERROR: ExtronDXPNames not found in discovery results")
        return false
    end
    
    if not discovered.ClickShareNames then
        print("ERROR: ClickShareNames not found in discovery results")
        return false
    end
    
    if not discovered.RoomControlsNames then
        print("ERROR: RoomControlsNames not found in discovery results")
        return false
    end
    
    print("✓ Component discovery validated")
    print("  - Extron DXP components found: " .. #discovered.ExtronDXPNames)
    print("  - ClickShare components found: " .. #discovered.ClickShareNames)
    print("  - Room Controls components found: " .. #discovered.RoomControlsNames)
    
    -- Test 6: Check status reporting
    print("Test 6: Status Reporting")
    local status = controller:getStatus()
    
    if not status then
        print("ERROR: Status reporting failed")
        return false
    end
    
    if type(status.systemPowered) ~= "boolean" then
        print("ERROR: systemPowered status not boolean")
        return false
    end
    
    if type(status.systemWarming) ~= "boolean" then
        print("ERROR: systemWarming status not boolean")
        return false
    end
    
    if type(status.currentSource) ~= "number" and status.currentSource ~= nil then
        print("ERROR: currentSource status not number or nil")
        return false
    end
    
    if type(status.currentDestinations) ~= "table" then
        print("ERROR: currentDestinations status not table")
        return false
    end
    
    if type(status.componentsValid) ~= "boolean" then
        print("ERROR: componentsValid status not boolean")
        return false
    end
    
    print("✓ Status reporting validated")
    print("  - System Powered: " .. tostring(status.systemPowered))
    print("  - System Warming: " .. tostring(status.systemWarming))
    print("  - Current Source: " .. tostring(status.currentSource))
    print("  - Components Valid: " .. tostring(status.componentsValid))
    
    -- Test 7: Check UCI integration methods
    print("Test 7: UCI Integration Methods")
    
    -- Test enable/disable UCI integration
    controller:enableUCIIntegration()
    if not controller.uciIntegrationEnabled then
        print("ERROR: UCI integration not enabled")
        return false
    end
    
    controller:disableUCIIntegration()
    if controller.uciIntegrationEnabled then
        print("ERROR: UCI integration not disabled")
        return false
    end
    
    -- Re-enable for normal operation
    controller:enableUCIIntegration()
    
    print("✓ UCI integration methods validated")
    
    print("=== All Tests Passed ===")
    return true
end

-- Test function to simulate routing operations
function TestRoutingOperations()
    print("=== Routing Operations Test ===")
    
    local controller = _G.ExtronDXPController
    if not controller then
        print("ERROR: Controller not available for routing tests")
        return false
    end
    
    -- Test 1: Set source
    print("Test 1: Source Setting")
    controller:setSource(controller.inputs.ClickShare)
    
    if controller.currentSource ~= controller.inputs.ClickShare then
        print("ERROR: Source not set correctly")
        return false
    end
    
    print("✓ Source setting validated")
    
    -- Test 2: Set destination
    print("Test 2: Destination Setting")
    controller:setDestination(1, true)
    
    if not controller.currentDestinations[1] then
        print("ERROR: Destination not set correctly")
        return false
    end
    
    print("✓ Destination setting validated")
    
    -- Test 3: Clear destinations
    print("Test 3: Destination Clearing")
    controller:clearAllDestinations()
    
    for i = 1, 4 do
        if controller.currentDestinations[i] then
            print("ERROR: Destination " .. i .. " not cleared")
            return false
        end
    end
    
    print("✓ Destination clearing validated")
    
    -- Test 4: Multiple destinations
    print("Test 4: Multiple Destinations")
    controller:setDestination(1, true)
    controller:setDestination(2, true)
    controller:setDestination(3, true)
    controller:setDestination(4, true)
    
    local activeCount = 0
    for i = 1, 4 do
        if controller.currentDestinations[i] then
            activeCount = activeCount + 1
        end
    end
    
    if activeCount ~= 4 then
        print("ERROR: Expected 4 active destinations, got " .. activeCount)
        return false
    end
    
    print("✓ Multiple destinations validated")
    
    -- Test 5: Destination feedback for different sources
    print("Test 5: Destination Feedback")
    
    -- Test ClickShare feedback
    controller:setSource(controller.inputs.ClickShare)
    if not controller.controls.btnDestClickShare[1].Boolean then
        print("ERROR: ClickShare destination feedback not set")
        return false
    end
    
    -- Test No Source feedback
    controller:setSource(controller.inputs.NoSource)
    if not controller.controls.btnDestNoSource[1].Boolean then
        print("ERROR: No Source destination feedback not set")
        return false
    end
    
    print("✓ Destination feedback validated")
    
    -- Clean up
    controller:clearAllDestinations()
    controller:setSource(controller.inputs.NoSource)
    
    print("=== Routing Operations Tests Passed ===")
    return true
end

-- Test function to validate auto-switching logic
function TestAutoSwitching()
    print("=== Auto-Switching Test ===")
    
    local controller = _G.ExtronDXPController
    if not controller then
        print("ERROR: Controller not available for auto-switching tests")
        return false
    end
    
    -- Test 1: Check auto-switching when system not powered
    print("Test 1: Auto-Switching with System Off")
    controller.systemPowered = false
    controller.systemWarming = false
    
    local originalSource = controller.currentSource
    controller:checkAutoSwitch()
    
    if controller.currentSource ~= originalSource then
        print("ERROR: Auto-switching occurred when system not powered")
        return false
    end
    
    print("✓ Auto-switching correctly blocked when system off")
    
    -- Test 2: Check auto-switching when system warming
    print("Test 2: Auto-Switching with System Warming")
    controller.systemPowered = true
    controller.systemWarming = true
    
    originalSource = controller.currentSource
    controller:checkAutoSwitch()
    
    if controller.currentSource ~= originalSource then
        print("ERROR: Auto-switching occurred when system warming")
        return false
    end
    
    print("✓ Auto-switching correctly blocked when system warming")
    
    -- Test 3: Check auto-switching when system ready
    print("Test 3: Auto-Switching with System Ready")
    controller.systemPowered = true
    controller.systemWarming = false
    
    -- Note: This test would require actual signal presence to be true
    -- For now, just verify the method doesn't crash
    controller:checkAutoSwitch()
    print("✓ Auto-switching method executed without errors")
    
    print("=== Auto-Switching Tests Passed ===")
    return true
end

-- Main test execution
function RunAllTests()
    print("Starting Extron DXP Controller Tests...")
    print("")
    
    local allTestsPassed = true
    
    -- Run basic controller tests
    if not TestExtronDXPController() then
        allTestsPassed = false
    end
    
    print("")
    
    -- Run routing operation tests
    if not TestRoutingOperations() then
        allTestsPassed = false
    end
    
    print("")
    
    -- Run auto-switching tests
    if not TestAutoSwitching() then
        allTestsPassed = false
    end
    
    print("")
    
    if allTestsPassed then
        print("🎉 ALL TESTS PASSED! 🎉")
        print("The refactored Extron DXP Controller is working correctly.")
    else
        print("❌ SOME TESTS FAILED! ❌")
        print("Please review the error messages above.")
    end
    
    return allTestsPassed
end

-- Execute tests if this script is run directly
if _G.ExtronDXPController then
    RunAllTests()
else
    print("ERROR: ExtronDXPController not found. Please ensure the controller is loaded before running tests.")
end 