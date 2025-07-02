# DivisibleSpaceController UCI Controls Template

## Required Controls for DivisibleSpaceController

### 1. Room Controller Selection Controls
You need to create an array of dropdown controls to select room controllers:

**Control Name:** `compRoomControllers` (Array)
- **Type:** Component Selector
- **Array Size:** 4 (or however many rooms you want to support)
- **Purpose:** Allow users to select which room controllers to combine

### 2. Combine/Separate Button
**Control Name:** `btnCombine`
- **Type:** Button
- **Purpose:** Toggle between combined and separated room states

### 3. Status Display
**Control Name:** `txtStatus`
- **Type:** Text Display
- **Purpose:** Show system status (OK/Invalid Components)

## UCI Design Setup Instructions

### Step 1: Create Room Controller Selection Controls
1. In your UCI design, create a Component Selector control
2. Name it `compRoomControllers`
3. Make it an array with 4 elements (or your desired number)
4. Set the array elements to be named: `compRoomControllers[1]`, `compRoomControllers[2]`, etc.

### Step 2: Create Combine Button
1. Create a Button control
2. Name it `btnCombine`
3. Set it as a toggle button if desired

### Step 3: Create Status Display
1. Create a Text Display control
2. Name it `txtStatus`
3. Set initial text to "OK"

## Example UCI Layout

```
┌─────────────────────────────────────┐
│  Divisible Space Controller         │
├─────────────────────────────────────┤
│  Room 1: [compRoomControllers[1]]   │
│  Room 2: [compRoomControllers[2]]   │
│  Room 3: [compRoomControllers[3]]   │
│  Room 4: [compRoomControllers[4]]   │
├─────────────────────────────────────┤
│  [btnCombine] Combine/Separate      │
├─────────────────────────────────────┤
│  Status: [txtStatus]                │
└─────────────────────────────────────┘
```

## How It Works

1. **Component Discovery:** The script automatically finds all `device_controller_script` components that have `roomName` or `selDefaultConfigs` controls
2. **User Selection:** Users select which room controllers to include from dropdown menus
3. **Validation:** The script validates that selected components exist and are accessible
4. **Room Management:** When combined, all selected rooms are powered on with synchronized settings
5. **Status Monitoring:** The status display shows if any components are invalid

## Troubleshooting

### If controls don't appear in dropdowns:
- Make sure your room controller scripts have `roomName` or `selDefaultConfigs` controls
- Check that the room controller scripts are properly loaded in your design

### If "Invalid Components" appears:
- The selected component doesn't exist in the current design
- The component exists but isn't accessible from this script
- Clear the selection and choose a different component

### If rooms don't combine properly:
- Check that the selected room controllers are valid SystemAutomationController instances
- Verify that the room controllers have the expected modules (powerModule, audioModule)
- Enable debugging to see detailed error messages 