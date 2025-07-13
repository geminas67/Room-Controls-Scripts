--[[
  Extron DXP Component Discovery Test Script
  Author: Nikolas Smith, Q-SYS
  2025-01-27
  
  This script helps debug component discovery issues by:
  1. Testing Component.GetComponents() directly
  2. Checking component type strings
  3. Providing detailed debug output
  4. Testing the ExtronDXPController component discovery
]]--

print("=== Extron DXP Component Discovery Test ===")

-- Test 1: Direct Component.GetComponents() test
print("\n1. Testing Component.GetComponents() directly...")
local allComponents = Component.GetComponents()
print("Total components found: " .. #allComponents)

if #allComponents == 0 then
    print("ERROR: No components found! This indicates a problem with Component.GetComponents()")
else
    print("✓ Component.GetComponents() is working")
    
    -- Show first 10 components for debugging
    print("\nFirst 10 components:")
    for i = 1, math.min(10, #allComponents) do
        local comp = allComponents[i]
        print("  " .. i .. ". " .. comp.Name .. " (Type: " .. comp.Type .. ")")
    end
end

-- Test 2: Check for specific component types
print("\n2. Checking for specific component types...")

local componentTypes = {
    extronRouter = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    callSync = "call_sync",
    ClickShare = "%PLUGIN%_bb4217ac-401f-4698-aad9-9e4b2496ff46_%FP%_e0a4597b59bdca3247ccb142ce451198",
    roomControls = "device_controller_script"
}

local foundTypes = {}
for typeName, typeString in pairs(componentTypes) do
    foundTypes[typeName] = {}
    for _, comp in pairs(allComponents) do
        if comp.Type == typeString then
            table.insert(foundTypes[typeName], comp.Name)
        end
    end
    print("  " .. typeName .. ": " .. #foundTypes[typeName] .. " found")
    for _, name in ipairs(foundTypes[typeName]) do
        print("    - " .. name)
    end
end

-- Test 3: Test the ExtronDXPController if available
print("\n3. Testing ExtronDXPController component discovery...")

if _G.ExtronDXPMatrixController then
    print("✓ ExtronDXPController found")
    
    local status = _G.ExtronDXPMatrixController:getComponentDiscoveryStatus()
    print("Component discovery status:")
    print("  - Total components: " .. status.totalComponents)
    print("  - Extron DXP Routers: " .. status.extronDXPCount)
    print("  - CallSync components: " .. status.callSyncCount)
    print("  - ClickShare components: " .. status.clickShareCount)
    print("  - Room Controls: " .. status.roomControlsCount)
    
    -- Test manual refresh
    print("\n4. Testing manual component discovery refresh...")
    local refreshed = _G.ExtronDXPMatrixController:refreshComponentDiscovery()
    print("✓ Manual refresh completed")
    
else
    print("✗ ExtronDXPController not found - make sure the main script is loaded first")
end

-- Test 4: Check for combo box controls
print("\n5. Checking for combo box controls...")
local comboBoxControls = {
    "compExtronRouter", "compCallSync", "compClickShare", "compRoomControls",
    "compExtronDXP", "compExtron", "compRouter", "compMatrix",
    "compVideoRouter", "compVideoSwitcher", "compSwitcher"
}

local foundComboBoxes = {}
for _, controlName in ipairs(comboBoxControls) do
    if Controls[controlName] then
        table.insert(foundComboBoxes, controlName)
        print("  ✓ Found combo box: " .. controlName)
    end
end

if #foundComboBoxes == 0 then
    print("  ✗ No combo box controls found - this is normal if no combo boxes are defined in the design")
else
    print("  Found " .. #foundComboBoxes .. " combo box controls")
end

print("\n=== Component Discovery Test Complete ===")
print("\nIf no components are being discovered:")
print("1. Check that the Q-SYS design has the expected components")
print("2. Verify component type strings match your Q-SYS version")
print("3. Try restarting the script after the design is fully loaded")
print("4. Check the Q-SYS log for any component-related errors") 