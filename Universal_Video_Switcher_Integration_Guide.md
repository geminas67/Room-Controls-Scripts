# Universal Video Switcher Integration Guide

## Overview

All UCIController versions now include a **Universal Video Switcher Integration System** that automatically detects and integrates with various video switcher types, including:

- **NV32** (QSC NV-32-H)
- **Extron DXP** (Extron DXP Matrix Switchers)
- **Generic** (Other video switchers with auto-detection)

## Key Features

### 🔍 **Auto-Detection**
- Automatically discovers video switcher components in your Q-SYS system
- Supports multiple UCI variable naming conventions
- Falls back to component discovery if no UCI variables are configured

### 🎛️ **Easy Configuration**
- Pre-configured mappings for common video switcher types
- Easy-to-edit input mappings
- Runtime configuration changes

### 🔧 **Flexible Integration**
- Works with any video switcher type
- Supports both Value and String property routing methods
- Timer-based monitoring for reliable operation

## Setup Instructions

### 1. **Automatic Setup (Recommended)**

The system will automatically detect and configure your video switcher. No manual setup required!

### 2. **Manual Configuration via UCI Variables**

If you prefer manual configuration, add one of these UCI variables to your design:

#### For NV32:
```
Variable Name: devNV32
Type: String
Value: NV32-H-01 (or your actual device name)
```

#### For Extron DXP:
```
Variable Name: devExtronDXP
Type: String
Value: Extron DXP 84 HD 4K Plus (or your actual device name)
```

#### For Generic Video Switchers:
```
Variable Name: devVideoSwitcher
Type: String
Value: Your-Video-Switcher-Name
```

### 3. **Alternative Variable Names**

The system also supports these alternative variable names:
- `codenameNV32`, `varNV32CodeName`, `nv32Device`, `nv32Component`
- `codenameExtronDXP`, `varExtronDXPCodeName`, `extronDXPDevice`, `extronDXPComponent`
- `codenameVideoSwitcher`, `varVideoSwitcherCodeName`

## Default Mappings

### NV32 Default Mapping
```lua
[7] = 5, -- btnNav07 → HDMI2 (Input 5)
[8] = 4, -- btnNav08 → HDMI1 (Input 4)
[9] = 6  -- btnNav09 → HDMI3 (Input 6)
```

### Extron DXP Default Mapping
```lua
[7] = 2, -- btnNav07 → Teams PC (Input 2)
[8] = 4, -- btnNav08 → Laptop Front (Input 4)
[9] = 1  -- btnNav09 → ClickShare (Input 1)
```

### Generic Default Mapping
```lua
[7] = 1, -- btnNav07 → Input 1
[8] = 2, -- btnNav08 → Input 2
[9] = 3  -- btnNav09 → Input 3
```

## Custom Configuration

### Changing Input Mappings

You can customize the UCI button to video switcher input mappings:

```lua
-- Example: Custom mapping for a different video switcher
local customMapping = {
    [7] = 3, -- btnNav07 → Input 3 (PC)
    [8] = 1, -- btnNav08 → Input 1 (Laptop)
    [9] = 2  -- btnNav09 → Input 2 (Wireless)
}

-- Apply the custom mapping
myUCI:updateVideoSwitcherMapping(customMapping)
```

### Adding New Video Switcher Types

To add support for a new video switcher type, modify the `VideoSwitcherIntegration.SwitcherTypes` table:

```lua
NewSwitcherType = {
    name = "New Switcher",
    componentType = "your_component_type",
    variableNames = {"devNewSwitcher", "codenameNewSwitcher"},
    routingMethod = "output_1", -- or "hdmi.out.1.select.index"
    defaultMapping = {
        [7] = 1, -- btnNav07 → Input 1
        [8] = 2, -- btnNav08 → Input 2
        [9] = 3  -- btnNav09 → Input 3
    }
}
```

## API Reference

### Video Switcher Methods

#### `getVideoSwitcherStatus()`
Returns the current status of the video switcher integration.

```lua
local status = myUCI:getVideoSwitcherStatus()
print("Enabled: " .. tostring(status.enabled))
print("Type: " .. tostring(status.switcherType))
print("Component Valid: " .. tostring(status.componentValid))
```

#### `updateVideoSwitcherMapping(newMapping)`
Updates the UCI button to input mapping.

```lua
local success = myUCI:updateVideoSwitcherMapping(customMapping)
if success then
    print("Mapping updated successfully")
end
```

#### `switchVideoInput(inputNumber)`
Manually switch to a specific input.

```lua
local success = myUCI:switchVideoInput(5)
if success then
    print("Switched to input 5")
end
```

### Debug Functions

#### `printVideoSwitcherStatus()`
Prints detailed status information to the console.

```lua
printVideoSwitcherStatus()
```

#### `configureCustomVideoSwitcherMapping()`
Example function showing how to configure custom mappings.

```lua
configureCustomVideoSwitcherMapping()
```

## Troubleshooting

### Video Switcher Not Detected

1. **Check UCI Variables**: Ensure you have the correct UCI variable set
2. **Verify Component Name**: Make sure the device name in the UCI variable matches your actual component
3. **Check Component Type**: Verify the component type is supported
4. **Review Console Output**: Look for debug messages indicating detection issues

### Input Switching Not Working

1. **Verify Mapping**: Check that the UCI button numbers match your actual buttons
2. **Check Input Numbers**: Ensure the input numbers are correct for your video switcher
3. **Review Routing Method**: Verify the routing method is appropriate for your switcher type
4. **Check Permissions**: Ensure the script has permission to control the video switcher

### Performance Issues

1. **Reduce Monitoring Frequency**: Change the timer interval from 0.1 to 0.2 seconds
2. **Disable Debug Mode**: Set `debugMode = false` in the VideoSwitcherIntegration class
3. **Optimize Mappings**: Only map the buttons you actually need

## Console Output Examples

### Successful Detection
```
[Video Switcher] Initializing Video Switcher Integration
[Video Switcher] Found NV32 via UCI variable: devNV32
[Video Switcher] Video switcher component created: NV32-H-01
[Video Switcher] UCI button monitoring started
[Video Switcher] Video Switcher Integration initialized successfully
```

### Custom Mapping Applied
```
=== Video Switcher Status ===
Enabled: true
Type: NV32
Component Valid: true
Current Mapping:
  btnNav07 → Input 3
  btnNav08 → Input 1
  btnNav09 → Input 2
=== End Video Switcher Status ===
```

### Input Switching
```
[Video Switcher] UCI Button 7 pressed, switching to input 3
[Video Switcher] ✓ Successfully switched to input 3
```

## Best Practices

### 1. **Use UCI Variables for Configuration**
- Makes it easy to change device names without editing code
- Supports multiple UCI designs with different video switchers
- Provides clear documentation of which device is being used

### 2. **Test Your Mappings**
- Use the `printVideoSwitcherStatus()` function to verify configuration
- Test each UCI button to ensure it switches to the correct input
- Verify that the video switcher responds correctly

### 3. **Document Your Configuration**
- Keep a record of your UCI button to input mappings
- Document any custom configurations
- Note any special requirements for your specific video switcher

### 4. **Monitor Console Output**
- Watch for debug messages during initialization
- Check for any error messages or warnings
- Use the status functions to verify operation

## Version Compatibility

This universal video switcher integration is included in all UCIController versions:

- ✅ **UCIController Enhanced** (Version 1.1)
- ✅ **UCIController Enhanced UCI External** (Version 1.3)
- ✅ **UCIController Perplexity** (Version 1.1)

All versions provide the same video switcher integration capabilities with consistent APIs and configuration options.

## Support

If you encounter issues with the video switcher integration:

1. Check the console output for error messages
2. Verify your video switcher is properly configured in Q-SYS Designer
3. Test with the provided debug functions
4. Review the troubleshooting section above

The system is designed to be robust and provide clear feedback about its operation status. 