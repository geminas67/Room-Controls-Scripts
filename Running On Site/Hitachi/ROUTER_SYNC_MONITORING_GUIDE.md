# Router Sync Monitoring Guide
**CameraPresetsController - Hitachi Site**  
**Last Updated:** 2026-01-31  
**Version:** 5.1 (Enhanced Logging)

---

## 🎯 Purpose

This document explains how `compCamRouter` synchronization works, specifically monitoring when and how "select.1" and "select.2" (router outputs) should change between rooms in a divisible space setup.

---

## 📋 Key Changes Made to Hitachi.lua

### 1. **Camera Discovery - FIXED** ✅
**Problem:** Original code filtered cameras by room number suffix (e.g., "Camera01", "Camera02")  
**Solution:** Removed filtering to discover ALL cameras for ALL rooms (matches copy.lua behavior)

```lua
// BEFORE (line 239-241):
local roomStr = string.format("%02d", roomIdx)
if comp.Name and comp.Name:match(roomStr .. "$") then  // Only cameras ending in "01", "02"

// AFTER:
if comp.Name then  // All cameras discovered
```

**Impact:** All cameras are now available in all rooms, allowing flexible routing.

---

### 2. **Enhanced Router Sync Logging** 📊

Added comprehensive logging at every step of the router sync process:

#### **When `compcamRouter` Changes** (Line ~656-672)
```
=== compcamRouter changed to: [RouterName] (Source: User Selection) ===
  → Room[1]: Updating output choices...
  → Room[1]: Re-establishing router sync...
  → Room[2]: Updating output choices...
  → Room[2]: Re-establishing router sync...
=== Router change complete for all rooms ===
```

#### **When `routerOutput[roomIdx]` Changes** (Line ~674-681)
```
Room[1] routerOutput changed to: select.1 (Source: User Selection)
Room[1] Re-establishing router sync with new output...
```

#### **During `setupRouterSync(roomIdx)`** (Line ~453-506)
```
Room[1] === setupRouterSync START === Router: VideoRouter01
Room[1] Using routerOutput control value: select.1
Room[1] Connecting: Router[VideoRouter01].select.1 → devCams[1]
Room[1] Setting up sync monitor for router output: select.1
Room[1] Initializing router output select.1 handler...
Room[1] Router output select.1 handler registered and initialized ✓
Room[1] === setupRouterSync END === Success: true
```

#### **During `updateRouterOutputChoices(roomIdx)`** (Line ~879-940)
```
Room[1] updateRouterOutputChoices: Router='VideoRouter01'
Room[1] Found 4 router outputs: [select.1, select.2, select.3, select.4]
Room[1] Router output changed: '[empty]' → 'select.1' (cache invalid or room-specific assignment)
```

**Smart Room-to-Output Matching:**
- Room 1 → select.1
- Room 2 → select.2
- Fallback to first available output if room-specific output doesn't exist

#### **When Router Output Value Changes** (Line ~508-549)
```
Room[1] Router output select.1 changed: input=3, current camera=Camera01 (Source: Router Output EventHandler)
Room[1] Camera switched: Camera01 → Camera03 via router output select.1 (Source: Router Sync)
```

---

## 🔄 Event Flow Sequence

### **Initialization (Lines 577-634)**

```
1. Load JSON presets
2. FOR EACH ROOM (1 to numRooms):
     ├─ Discover cameras (ALL cameras, no filtering)
     ├─ Discover routers
     ├─ Discover room controls
     ├─ Initialize presets
     ├─ Setup camera monitoring
     └─ Setup camera choices
3. Populate shared router choices (aggregated from all rooms)
4. FOR EACH ROOM:
     └─ Update router output choices
        ├─ Discover: [select.1, select.2, select.3, ...]
        └─ Assign: Room 1 → select.1, Room 2 → select.2
5. FOR EACH ROOM:
     └─ Setup router sync
        └─ Attach event handler to router[select.X]
6. FOR EACH ROOM:
     └─ Update preset match LEDs
```

---

## 🎛️ How "select.1" and "select.2" Get Assigned

### **Automatic Room-to-Output Matching (NEW):**

```lua
// Line ~914-919
local newOutput = outputNames[roomIdx] or outputNames[1]
-- Room 1 tries outputNames[1] = "select.1"
-- Room 2 tries outputNames[2] = "select.2"
-- Falls back to first output if room-specific doesn't exist
```

### **Manual Override (User-Controlled):**

User can change `routerOutput[roomIdx]` control in Q-Sys Designer:
- `routerOutput[1]` = User selects from dropdown: [select.1, select.2, select.3, ...]
- `routerOutput[2]` = User selects from dropdown: [select.1, select.2, select.3, ...]

---

## 📊 What to Monitor in Q-Sys Debug Output

### **Expected Output on Initialization:**

```
[CameraPreset] === Initialization Started ===
[CameraPreset] Initializing Room[1]...
[CameraPreset] Room[1] Camera found: Camera01 (Source: Component Discovery)
[CameraPreset] Room[1] Camera found: Camera02 (Source: Component Discovery)
[CameraPreset] Room[1] Router found: VideoRouter01
[CameraPreset] Room[2] Camera found: Camera01 (Source: Component Discovery)
[CameraPreset] Room[2] Camera found: Camera02 (Source: Component Discovery)
[CameraPreset] Room[2] Router found: VideoRouter01
[CameraPreset] Router choices updated: 1 available (aggregated from 2 rooms)
[CameraPreset] Room[1] Found 4 router outputs: [select.1, select.2, select.3, select.4]
[CameraPreset] Room[1] Router output changed: '[empty]' → 'select.1'
[CameraPreset] Room[2] Found 4 router outputs: [select.1, select.2, select.3, select.4]
[CameraPreset] Room[2] Router output changed: '[empty]' → 'select.2'
[CameraPreset] Room[1] === setupRouterSync START === Router: VideoRouter01
[CameraPreset] Room[1] Using routerOutput control value: select.1
[CameraPreset] Room[1] Connecting: Router[VideoRouter01].select.1 → devCams[1]
[CameraPreset] Room[1] Router output select.1 handler registered and initialized ✓
[CameraPreset] Room[2] === setupRouterSync START === Router: VideoRouter01
[CameraPreset] Room[2] Using routerOutput control value: select.2
[CameraPreset] Room[2] Connecting: Router[VideoRouter01].select.2 → devCams[2]
[CameraPreset] Room[2] Router output select.2 handler registered and initialized ✓
[CameraPreset] === Initialization Complete ===
```

### **When Router Input Changes (Physical Router Event):**

```
[CameraPreset] Room[1] Router output select.1 changed: input=3 (Source: Router Output EventHandler)
[CameraPreset] Room[1] Camera switched: Camera01 → Camera03 via router output select.1
```

### **When User Changes Router Selector:**

```
[CameraPreset] === compcamRouter changed to: VideoRouter02 (Source: User Selection) ===
[CameraPreset]   → Room[1]: Updating output choices...
[CameraPreset] Room[1] Found 2 router outputs: [select.1, select.2]
[CameraPreset]   → Room[1]: Re-establishing router sync...
[CameraPreset] Room[1] Cleaned up 1 old handler(s) for output: select.1
[CameraPreset] Room[1] Connecting: Router[VideoRouter02].select.1 → devCams[1]
[CameraPreset]   → Room[2]: Updating output choices...
[CameraPreset]   → Room[2]: Re-establishing router sync...
[CameraPreset] === Router change complete for all rooms ===
```

---

## 🔍 Troubleshooting

### **Problem: Room 1 and Room 2 both monitoring "select.1"**

**Check:**
1. Are both `routerOutput[1]` and `routerOutput[2]` set to "select.1"?
2. Does the router have enough outputs (select.1, select.2, etc.)?

**Debug Output to Look For:**
```
Room[1] Router output changed: '[empty]' → 'select.1'
Room[2] Router output changed: '[empty]' → 'select.1'  ← PROBLEM: Both using select.1
```

**Solution:** Manually set `routerOutput[2]` to "select.2" in Q-Sys Designer, or verify router has multiple outputs.

---

### **Problem: Router outputs not discovered**

**Check:**
```
Room[1] Found 0 router outputs: []
Room[1] Router outputs: 0 available
```

**Possible Causes:**
1. Router component not using standard "select.X" naming
2. Router component not properly initialized

**Solution:** Check router component controls - they should be named "select.1", "select.2", etc.

---

### **Problem: Cameras not syncing with router changes**

**Check:**
```
Room[1] Router output select.1 changed: input=3, current camera=Camera01
Room[1] Camera already set to Camera01 (no change needed)  ← Camera not switching
```

**Possible Causes:**
1. Camera choices not populated in devCams[roomIdx]
2. Router input index doesn't match camera choice index

**Debug Output to Look For:**
```
Room[1] Invalid router input: idx=5, choices=3  ← Router input 5, but only 3 cameras
```

**Solution:** Verify camera discovery is working and choices are populated.

---

## 🎯 Key Architectural Differences from copy.lua

| Aspect | Hitachi.lua (CURRENT) | Hitachi copy.lua (REFERENCE) |
|--------|----------------------|----------------------------|
| **Camera Discovery** | ALL cameras to ALL rooms | ALL cameras to ALL rooms (SAME now) |
| **Router Choices** | Aggregated from all rooms | Per-room (overwrites shared control) ❌ |
| **Init Sequence** | Discover all → Populate shared → Sync | Per-room loop (problematic) ❌ |
| **Room-to-Output** | Smart matching (Room N → select.N) | First available only |
| **Logging** | Comprehensive event tracking | Basic logging |

**Conclusion:** Hitachi.lua now has BETTER architecture than copy.lua for divisible space scenarios.

---

## 📝 Next Steps

1. **Deploy and test** with debug output enabled (`debugging = true`)
2. **Monitor logs** for the expected output patterns shown above
3. **Verify** Room 1 uses select.1 and Room 2 uses select.2
4. **Test** router input changes and verify cameras switch correctly
5. **Document** any site-specific router output naming conventions

---

## 📞 Support

If router sync issues persist after these changes:

1. Capture full debug output from initialization
2. Check that router component has multiple "select.X" outputs
3. Verify `routerOutput[1]` and `routerOutput[2]` controls are set correctly
4. Review router component type matches `componentTypes.videoRouter`

---

**End of Guide**
