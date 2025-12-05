# Source Routing Controller Script Comparison

## Files Compared
1. **File 1**: `SourceRoutingController(Refactor)(Lumbee)EncoderRoutingcopy.lua` (640 lines)
2. **File 2**: `SourceRoutingController(Refactor)(Lumbee)EnocderRouting.lua` (645 lines)

## Summary
Both scripts share the same core architecture and routing logic, but **File 1 has significantly more functionality** for handling Room A and Room B display controller buttons. File 2 is missing handlers for individual room display controls.

---

## Key Functional Differences

### 1. Component References (Lines 15-31)

| Component | File 1 | File 2 | Impact |
|-----------|--------|--------|--------|
| EMC Display Controller | `displayControlsEMC` | `emcDisplayController` | Different variable name |
| Router PGM | ❌ Not present | ✅ `routerPGM` | File 2 has router component but doesn't use it |
| Component Order | `rmBPowerState` before `rmAPowerState` | `rmAPowerState` before `rmBPowerState` | No functional impact |

### 2. Event Handler Registration (Lines 424-601)

#### ✅ File 1 Has Complete Handler Set:
- EMC Display Controller handlers (4 buttons: DispatchPC01, DispatchPC02, SignagePC, MediaPlayer)
- **Room A Display Controller handlers (4 buttons: DispatchPC01, DispatchPC02, SignagePC, MediaPlayer)** ← Missing in File 2
- **Room B Display Controller handlers (4 buttons: DispatchPC01, DispatchPC02, SignagePC, MediaPlayer)** ← Missing in File 2

#### ❌ File 2 Only Has:
- EMC Display Controller handlers (4 buttons: DispatchPC01, DispatchPC02, SignagePC, MediaPlayer)
- **NO Room A or Room B display button handlers**

### 3. DispatchPC Button Muting Behavior

#### File 1 (Lines 506-518):
```lua
bind(components.displayControlsEMC['btnSource 1'], function(ctl)
    if ctl.Boolean and self.stateModule:isCombined() then
        self.sourceRoutingModule:handleEMCDisplayButtonPress(1)
        self.sourceRoutingModule:muteAllRooms()  -- ← Explicit mute call
    end
end)
```

#### File 2 (Lines 507-511):
```lua
bind(components.emcDisplayController['btnSource 1'], function(ctl)
    if ctl.Boolean and self.stateModule:isCombined() then
        self.sourceRoutingModule:handleEMCDisplayButtonPress(1)
        -- ← Relies on handleEMCDisplayButtonPress to mute (which it doesn't for DispatchPC)
    end
end)
```

**Impact**: File 1 explicitly mutes all rooms when DispatchPC buttons are pressed. File 2 relies on `handleEMCDisplayButtonPress()` which doesn't mute for DispatchPC sources (since they have `source = nil`).

### 4. Room A/B Display Button Handlers (File 1 Only)

File 1 includes comprehensive handlers for Room A and Room B display controllers (lines 537-600):

- **DispatchPC buttons**: Mute all channels in the respective room
- **SignagePC button**: Mute all, then unmute channel 6
- **MediaPlayer button**: Mute all, then unmute channel 7

These allow direct control of display sources from Room A and Room B interfaces independently.

**File 2 completely lacks these handlers**, meaning:
- ❌ Room A display buttons won't trigger any routing/muting
- ❌ Room B display buttons won't trigger any routing/muting
- ❌ Users can't control display sources from individual room interfaces

### 5. Cleanup Function Differences (Lines 615-657)

#### File 1 Cleanup:
- Cleans up `displayControlsEMC` handlers
- Cleans up `displayControlsA` handlers (4 buttons)
- Cleans up `displayControlsB` handlers (4 buttons)
- Total: 12 display button handlers cleaned up

#### File 2 Cleanup:
- Cleans up `emcDisplayController` handlers only (4 buttons)
- Total: 4 display button handlers cleaned up
- **Missing cleanup for Room A and Room B display controllers**

### 6. Mixer Channel Access Pattern

#### File 1 (Room A/B handlers):
```lua
setProp(components.rmAMixer['input.6.mute'], "Boolean", false)
setProp(components.rmAMixer['input.7.mute'], "Boolean", false)
```

#### File 1 (SourceRoutingModule methods):
```lua
setProp(mixer['input_' .. channel .. '_mute'], "Boolean", true)
```

**Note**: File 1 uses different syntax patterns (`input.6` vs `input_6`). This suggests the Room A/B handlers might need the same pattern consistency check as the SourceRoutingModule methods.

---

## Functional Completeness Comparison

| Feature | File 1 | File 2 | Winner |
|---------|--------|--------|--------|
| Core routing logic | ✅ | ✅ | Tie |
| EMC combined mode routing | ✅ | ✅ | Tie |
| Room A/B divided mode routing | ✅ | ✅ | Tie |
| EMC display button handling | ✅ | ✅ | Tie |
| **Room A display button handling** | ✅ | ❌ | **File 1** |
| **Room B display button handling** | ✅ | ❌ | **File 1** |
| DispatchPC explicit muting | ✅ | ❌ | **File 1** |
| Cleanup completeness | ✅ | ❌ | **File 1** |
| routerPGM component | ❌ | ✅ (unused) | Tie (unused in File 2) |

---

## Recommendations

### Option 1: Use File 1 as Base (Recommended)
**File 1 is more feature-complete** and includes critical functionality for Room A and Room B display controls. However:

1. Fix component name consistency:
   - Change `displayControlsEMC` → `emcDisplayController` for consistency
   
2. Fix mixer channel syntax consistency:
   - Update Room A/B handlers to use `input_X_mute` pattern instead of `input.X.mute`
   - OR verify which syntax is correct for your Q-Sys components

3. Consider adding routerPGM if needed (currently unused in File 2)

### Option 2: Merge Features
- Start with File 1 (more complete)
- Add routerPGM component if needed
- Standardize component naming
- Verify mixer channel access syntax matches your component structure

### Critical Missing Features in File 2
If File 2 is the target file, you **MUST** add:
1. Room A display controller button handlers (lines 537-567 from File 1)
2. Room B display controller button handlers (lines 570-600 from File 1)
3. Cleanup handlers for Room A and Room B display controllers
4. Explicit muting for DispatchPC buttons if that behavior is desired

---

## Code Quality Notes

Both files:
- ✅ Follow the same architectural pattern
- ✅ Use configuration-driven routing maps
- ✅ Have proper module separation
- ✅ Include proper cleanup functions
- ✅ Use consistent event binding patterns

**File 1** has better feature completeness and handles edge cases (explicit muting for DispatchPC).

---

## Conclusion

**File 1 is functionally superior** with complete Room A and Room B display button handling. File 2 appears to be an incomplete version missing critical display control handlers for individual rooms. Unless there's a specific reason to exclude Room A/B display button handling, **File 1 should be used as the base** with minor naming/consistency fixes.


