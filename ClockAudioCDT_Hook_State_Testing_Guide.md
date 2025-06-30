# ClockAudioCDT Hook State Testing Guide

## Overview
This guide explains how to set up and test the ClockAudioCDT microphone controller's hook state functionality in Q-SYS Designer.

## Prerequisites
- Q-SYS Designer software
- ClockAudioCDT microphone system
- Basic understanding of Q-SYS component configuration

## Required Q-SYS Components

### 1. Core Components
Add these components to your Q-SYS design:

| Component Name | Q-SYS Component Type | Purpose |
|----------------|---------------------|---------|
| `compMicBox` | ClockAudio CDT Mic Box | Main microphone interface |
| `compMicMixer` | Mic Mixer | Audio mixing and processing |
| `compCallSync` | Call Sync | Call state management |
| `compVideoBridge` | Video Bridge | Video conferencing interface |
| `compRoomControls` | Room Controls | System control interface |

### 2. Test Control
Add a Button control named `btnTestHookState` for manual hook state testing.

## Setup Instructions

### Step 1: Add Components to Design
1. Open Q-SYS Designer
2. Create a new design or open existing design
3. Add the required components listed above
4. Ensure component names match exactly (case-sensitive)

### Step 2: Configure Component Connections
1. Connect the ClockAudio CDT Mic Box to the Mic Mixer
2. Configure Call Sync component for your conferencing system
3. Set up Video Bridge for your video conferencing platform
4. Configure Room Controls for your room automation system

### Step 3: Add Test Button
1. Add a Button control to your design
2. Name it exactly: `btnTestHookState`
3. This button will be used to manually toggle hook state during testing

### Step 4: Load Scripts
1. Load the main controller script: `-- ClockAudioCDTMicController "class".lua`
2. Load the test script: `ClockAudioCDT_Test_Example.lua`
3. Save and reload the design

## Testing Procedures

### Automatic Test Mode
When `compCallSync` is not available, the controller automatically enables test mode:
- Hook state is emulated using the test button
- LED behavior can be tested without actual call sync
- Use `btnTestHookState` to toggle between ON-HOOK and OFF-HOOK

### Manual Testing Steps
1. **Hook State Testing:**
   - Click `btnTestHookState` to toggle hook state
   - Observe microphone LED behavior:
     - ON-HOOK: LEDs should be OFF
     - OFF-HOOK: LEDs should be ON

2. **LED Color Testing:**
   - Use Q-SYS emulation for other components:
     - **Mute State:** Emulate `compCallSync["mute"]` control
     - **Privacy State:** Emulate `compVideoBridge["toggle.privacy"]` control
     - **Fire Alarm:** Emulate `compRoomControls["ledFireAlarm"]` control
     - **System Power:** Emulate `compRoomControls["ledSystemPower"]` control

3. **Expected LED Behavior:**
   - **Green LEDs:** Microphone is ON and unmuted
   - **Red LEDs:** Microphone is ON but muted
   - **No LEDs:** Microphone is OFF (on-hook) or system is powered off

### Test Mode Verification
Run the test script to verify:
- All required controls are available
- Test mode is active (when call sync is not present)
- Hook state transitions work correctly
- LED states respond appropriately

## Troubleshooting

### Common Issues

#### "Controller not available" Error
**Cause:** Required controls are missing from the Q-SYS design
**Solution:** 
1. Verify all required components are added
2. Check component names match exactly
3. Ensure components are properly connected
4. Reload the design

#### "Hook state test mode is not active" Message
**Cause:** Call sync component is present, so test mode is disabled
**Solution:**
1. Use actual call sync controls for testing
2. Or temporarily remove `compCallSync` to enable test mode

#### LEDs Not Responding
**Cause:** Component connections or configuration issues
**Solution:**
1. Check ClockAudio CDT Mic Box connections
2. Verify LED controls are properly mapped
3. Test with Q-SYS emulation mode

### Debug Mode
Enable debug mode by modifying the controller configuration:
```lua
myClockAudioCDTMicController = createClockAudioCDTMicController("Room Name", {debugging = true})
```

## Test Script Output
The test script provides detailed feedback:
- Control availability status
- Hook state transitions
- LED state verification
- Manual testing instructions

## Advanced Testing

### Component Emulation
Use Q-SYS Designer's emulation features to test different states:
1. Right-click on components in the design
2. Select "Emulate" option
3. Toggle various controls to test different scenarios

### State Combinations
Test various state combinations:
- Hook state + Mute state
- Hook state + Privacy state  
- Hook state + Fire alarm
- Hook state + System power

## Support
For additional support or questions about the ClockAudioCDT controller, refer to the main controller documentation or contact your system integrator. 