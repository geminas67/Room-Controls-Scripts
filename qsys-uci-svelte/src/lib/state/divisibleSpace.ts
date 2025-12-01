import { writable, derived } from 'svelte/store';
import { getQrwc, qrwcReady } from '../qrwc/qrwcClient';

export type RoomIdentity = 'CollabA' | 'CollabB' | null;
export type RoomState = 'separated' | 'combinedA' | 'combinedB';

export const roomIdentity = writable<RoomIdentity>(null);
export const roomState = writable<RoomState>('separated');

// Initialize room identity from UCI variable
qrwcReady.subscribe((ready) => {
	if (!ready) return;

	const qrwc = getQrwc();
	if (!qrwc) return;

	try {
		// Try to get room identity from UCI variable compRoomControls
		// This would need to be exposed via QRWC - adjust path as needed
		const uciVars = qrwc.components?.Uci?.variables;
		if (uciVars?.compRoomControls) {
			const roomControlsName = uciVars.compRoomControls.String || '';
			if (roomControlsName.includes('CollabA')) {
				roomIdentity.set('CollabA');
			} else if (roomControlsName.includes('CollabB')) {
				roomIdentity.set('CollabB');
			}
		}

		// Subscribe to room state changes from DivisibleSpaceControls component
		const divisibleSpaceComponent = qrwc.components?.DivisibleSpaceControls;
		if (divisibleSpaceComponent) {
			const btnRoomState = [
				divisibleSpaceComponent.controls?.['btnRoomState 1'],
				divisibleSpaceComponent.controls?.['btnRoomState 2'],
				divisibleSpaceComponent.controls?.['btnRoomState 3']
			];

			btnRoomState.forEach((btn, index) => {
				if (btn) {
					btn.on('update', ({ Bool }: any) => {
						if (Bool) {
							if (index === 0) {
								roomState.set('separated');
							} else if (index === 1) {
								roomState.set('combinedA');
							} else if (index === 2) {
								roomState.set('combinedB');
							}
						}
					});
				}
			});
		}
	} catch (error) {
		console.error('Error initializing divisible space state:', error);
	}
});

// Helper to determine if a layer should be shown based on room state and identity
export function shouldShowLayer(layerIndex: number, $roomState: RoomState, $roomIdentity: RoomIdentity): boolean {
	// Define layer availability for each room in separated mode
	const layerAvailability: Record<string, Record<number, boolean>> = {
		CollabA: {
			7: true,  // kLayerPCA
			9: true   // kLayerLaptopA
		},
		CollabB: {
			8: true,  // kLayerPCB
			10: true  // kLayerLaptopB
		}
	};

	// If rooms are combined, all source layers are available
	if ($roomState === 'combinedA' || $roomState === 'combinedB') {
		return true;
	}

	// If separated, check if the layer is available for this room
	if ($roomState === 'separated' && $roomIdentity && layerAvailability[$roomIdentity]) {
		const isAvailable = layerAvailability[$roomIdentity][layerIndex];
		if (isAvailable !== undefined) {
			return isAvailable;
		}
	}

	// Default to showing the layer (for non-source layers like Routing, Wireless, etc.)
	return true;
}

// Get the correct RoomControls layer name based on room state
export function getRoomControlsLayerName($roomState: RoomState): string {
	if ($roomState === 'separated') {
		return 'H09-RoomControlsSeparated';
	} else {
		return 'H08-RoomControlsCombined';
	}
}

// Get default layer after warming based on room state and identity
export function getDefaultLayerAfterWarming($roomState: RoomState, $roomIdentity: RoomIdentity): number {
	if ($roomState === 'separated') {
		if ($roomIdentity === 'CollabA') {
			return 7; // kLayerPCA
		} else if ($roomIdentity === 'CollabB') {
			return 8; // kLayerPCB
		}
		return 7; // Fallback to PCA
	} else if ($roomState === 'combinedA') {
		return 7; // kLayerPCA
	} else if ($roomState === 'combinedB') {
		return 8; // kLayerPCB
	}

	return 12; // Fallback to kLayerRouting
}

