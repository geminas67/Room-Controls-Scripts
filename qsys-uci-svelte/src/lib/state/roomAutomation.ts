import { writable, derived } from 'svelte/store';
import { getQrwc, qrwcReady } from '../qrwc/qrwcClient';

export const systemPowerState = writable<boolean>(false);
export const systemWarming = writable<boolean>(false);
export const systemCooling = writable<boolean>(false);

// Initialize room automation state monitoring
qrwcReady.subscribe((ready) => {
	if (!ready) return;

	const qrwc = getQrwc();
	if (!qrwc) return;

	try {
		// Get Room Controls component (adjust path based on your Q-SYS design)
		const roomControlsComponent = qrwc.components?.RoomControls;
		if (!roomControlsComponent) {
			console.warn('Room Controls component not found');
			return;
		}

		// Monitor ledSystemPower (authoritative status indicator)
		if (roomControlsComponent.controls?.ledSystemPower) {
			roomControlsComponent.controls.ledSystemPower.on('update', ({ Bool }: any) => {
				systemPowerState.set(!!Bool);
			});
		}

		// Monitor warming/cooling states
		if (roomControlsComponent.controls?.ledSystemWarming) {
			roomControlsComponent.controls.ledSystemWarming.on('update', ({ Bool }: any) => {
				systemWarming.set(!!Bool);
			});
		}

		if (roomControlsComponent.controls?.ledSystemCooling) {
			roomControlsComponent.controls.ledSystemCooling.on('update', ({ Bool }: any) => {
				systemCooling.set(!!Bool);
			});
		}
	} catch (error) {
		console.error('Error initializing room automation state:', error);
	}
});

// Power control functions
export function powerOn(): boolean {
	const qrwc = getQrwc();
	if (!qrwc) {
		return false;
	}

	try {
		const roomControlsComponent = qrwc.components?.RoomControls;
		if (!roomControlsComponent) {
			return false;
		}

		const btnSystemOnOff = roomControlsComponent.controls?.btnSystemOnOff;
		if (btnSystemOnOff) {
			btnSystemOnOff.update({ Bool: true });
			return true;
		}
	} catch (error) {
		console.error('Error powering on system:', error);
	}

	return false;
}

export function powerOff(): boolean {
	const qrwc = getQrwc();
	if (!qrwc) {
		return false;
	}

	try {
		const roomControlsComponent = qrwc.components?.RoomControls;
		if (!roomControlsComponent) {
			return false;
		}

		const btnSystemOnOff = roomControlsComponent.controls?.btnSystemOnOff;
		if (btnSystemOnOff) {
			btnSystemOnOff.update({ Bool: false });
			return true;
		}
	} catch (error) {
		console.error('Error powering off system:', error);
	}

	return false;
}

// Get timing from component or UCI variables
export function getTiming(isPoweringOn: boolean): number {
	const qrwc = getQrwc();
	if (!qrwc) {
		return isPoweringOn ? 10 : 5; // Default fallback
	}

	try {
		const roomControlsComponent = qrwc.components?.RoomControls;
		if (roomControlsComponent) {
			if (isPoweringOn) {
				const warmupTime = roomControlsComponent.controls?.warmupTime;
				if (warmupTime) {
					return warmupTime.Value || 10;
				}
			} else {
				const cooldownTime = roomControlsComponent.controls?.cooldownTime;
				if (cooldownTime) {
					return cooldownTime.Value || 5;
				}
			}
		}

		// Fallback to UCI variables
		const uciVars = qrwc.components?.Uci?.variables;
		if (isPoweringOn) {
			const timeProgressWarming = uciVars?.timeProgressWarming?.Value;
			if (timeProgressWarming) {
				return timeProgressWarming;
			}
		} else {
			const timeProgressCooling = uciVars?.timeProgressCooling?.Value;
			if (timeProgressCooling) {
				return timeProgressCooling;
			}
		}
	} catch (error) {
		console.error('Error getting timing:', error);
	}

	return isPoweringOn ? 10 : 5; // Default fallback
}

