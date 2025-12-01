# Q-SYS UCI Controller (Svelte)

A modern web-based recreation of the Q-SYS UCIController using Svelte and QWRC Svelte library.

## Features

- **Divisible Space Support**: Handles multiple rooms (CollabA/CollabB) with room combining/separating
- **Multiple Sources**: Supports PCA, PCB, LaptopA, LaptopB sources
- **Real-time State Sync**: Automatic synchronization with Q-SYS core via QRWC
- **Layer Management**: 15 navigation layers with conditional visibility
- **Video Switcher Integration**: AVProEdge switcher support with room-specific routing
- **Room Automation**: System power on/off with progress tracking
- **Conference Controls**: USB connection monitoring and conference control visibility

## Setup

1. Install dependencies:
```bash
npm install
```

2. Configure QRWC connection:
   - Set `VITE_QRWC_SOCKET_URL` environment variable to your Q-SYS core WebSocket URL
   - Default: `ws://localhost:1710`

3. Run development server:
```bash
npm run dev
```

4. Build for production:
```bash
npm run build
```

## Architecture

The application mirrors the modular structure of the Lua UCIController:

- **QRWC Client** (`src/lib/qrwc/`): Connection management and control subscriptions
- **State Stores** (`src/lib/state/`): Svelte stores for layers, sublayers, routing, video switcher, room automation, progress, and divisible space
- **Components** (`src/lib/components/`): Svelte components for panels, sublayers, routing, and system controls

## Key Files

- `src/lib/qrwc/qrwcClient.ts`: QRWC initialization and connection
- `src/lib/qrwc/controlsStore.ts`: All Q-SYS pin and control stores
- `src/lib/state/layers.ts`: Layer constants and navigation
- `src/lib/state/sublayers.ts`: Derived stores for sublayer visibility logic
- `src/lib/state/divisibleSpace.ts`: Room state management
- `src/routes/+page.svelte`: Main application entry point

## Notes

- Control paths in `controlsStore.ts` may need adjustment based on your Q-SYS design file structure
- Component names (Pins, RoomControls, etc.) should match your Q-SYS design
- UCI variable paths should be verified against your design file

