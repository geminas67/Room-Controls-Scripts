import { writable, derived } from 'svelte/store';
import { getQrwc, qrwcReady } from './qrwcClient';

// Pin Input Stores (DivisibleSpace version - 4 sources)
export const pinCallActive = writable<boolean>(false);
export const pinLEDUSBLaptopA = writable<boolean>(false);
export const pinLEDUSBLaptopB = writable<boolean>(false);
export const pinLEDUSBPCA = writable<boolean>(false);
export const pinLEDUSBPCB = writable<boolean>(false);
export const pinLEDOffHookLaptopA = writable<boolean>(false);
export const pinLEDOffHookLaptopB = writable<boolean>(false);
export const pinLEDOffHookPCA = writable<boolean>(false);
export const pinLEDOffHookPCB = writable<boolean>(false);
export const pinLEDHDMIActiveLaptopA = writable<boolean>(false);
export const pinLEDHDMIActiveLaptopB = writable<boolean>(false);
export const pinLEDHDMIActivePCA = writable<boolean>(false);
export const pinLEDHDMIActivePCB = writable<boolean>(false);
export const pinLEDHDMIConnectedLaptopA = writable<boolean>(false);
export const pinLEDHDMIConnectedLaptopB = writable<boolean>(false);
export const pinLEDHDMIConnectedPCA = writable<boolean>(false);
export const pinLEDHDMIConnectedPCB = writable<boolean>(false);
export const pinLEDPresetSaved = writable<boolean>(false);
export const pinLEDACPRBypassSeparated = writable<boolean>(false);
export const pinLEDACPRBypassCombined = writable<boolean>(false);
export const pinLEDTouchActivity = writable<boolean>(false);

// Navigation Button Stores (15 buttons for DivisibleSpace)
export const btnNav01 = writable<boolean>(false);
export const btnNav02 = writable<boolean>(false);
export const btnNav03 = writable<boolean>(false);
export const btnNav04 = writable<boolean>(false);
export const btnNav05 = writable<boolean>(false);
export const btnNav06 = writable<boolean>(false);
export const btnNav07 = writable<boolean>(false);
export const btnNav08 = writable<boolean>(false);
export const btnNav09 = writable<boolean>(false);
export const btnNav10 = writable<boolean>(false);
export const btnNav11 = writable<boolean>(false);
export const btnNav12 = writable<boolean>(false);
export const btnNav13 = writable<boolean>(false);
export const btnNav14 = writable<boolean>(false);
export const btnNav15 = writable<boolean>(false);

// System Control Stores
export const btnStartSystem = writable<boolean>(false);
export const btnNavShutdown = writable<boolean>(false);
export const btnShutdownCancel = writable<boolean>(false);
export const btnShutdownConfirm = writable<boolean>(false);

// Help Button Stores (8 pairs for DivisibleSpace)
export const btnOpenHelpLaptopA = writable<boolean>(false);
export const btnOpenHelpLaptopB = writable<boolean>(false);
export const btnOpenHelpPCA = writable<boolean>(false);
export const btnOpenHelpPCB = writable<boolean>(false);
export const btnOpenHelpWirelessA = writable<boolean>(false);
export const btnOpenHelpWirelessB = writable<boolean>(false);
export const btnOpenHelpRouting = writable<boolean>(false);
export const btnOpenHelpStreamMusic = writable<boolean>(false);

export const btnCloseHelpLaptopA = writable<boolean>(false);
export const btnCloseHelpLaptopB = writable<boolean>(false);
export const btnCloseHelpPCA = writable<boolean>(false);
export const btnCloseHelpPCB = writable<boolean>(false);
export const btnCloseHelpWirelessA = writable<boolean>(false);
export const btnCloseHelpWirelessB = writable<boolean>(false);
export const btnCloseHelpRouting = writable<boolean>(false);
export const btnCloseHelpStreamMusic = writable<boolean>(false);

// Progress Control Stores
export const knbProgressBar = writable<number>(0);
export const txtProgressBar = writable<string>('0%');

// Array of navigation button stores for easier iteration
export const navButtonStores = [
	btnNav01, btnNav02, btnNav03, btnNav04, btnNav05, btnNav06,
	btnNav07, btnNav08, btnNav09, btnNav10, btnNav11, btnNav12,
	btnNav13, btnNav14, btnNav15
];

// Setup QRWC subscriptions once ready
let subscriptionsInitialized = false;

qrwcReady.subscribe((ready) => {
	if (!ready || subscriptionsInitialized) return;
	
	const qrwc = getQrwc();
	if (!qrwc) return;

	try {
		// Get Pins component (adjust path based on your Q-SYS design)
		const pinsComponent = qrwc.components?.Pins;
		if (!pinsComponent) {
			console.warn('Pins component not found in QRWC');
			return;
		}

		const controls = pinsComponent.controls;

		// Subscribe to pin inputs
		if (controls.pinCallActive) {
			controls.pinCallActive.on('update', ({ Bool }: any) => pinCallActive.set(!!Bool));
		}

		// USB pins
		if (controls.pinLEDUSBLaptopA) {
			controls.pinLEDUSBLaptopA.on('update', ({ Bool }: any) => pinLEDUSBLaptopA.set(!!Bool));
		}
		if (controls.pinLEDUSBLaptopB) {
			controls.pinLEDUSBLaptopB.on('update', ({ Bool }: any) => pinLEDUSBLaptopB.set(!!Bool));
		}
		if (controls.pinLEDUSBPCA) {
			controls.pinLEDUSBPCA.on('update', ({ Bool }: any) => pinLEDUSBPCA.set(!!Bool));
		}
		if (controls.pinLEDUSBPCB) {
			controls.pinLEDUSBPCB.on('update', ({ Bool }: any) => pinLEDUSBPCB.set(!!Bool));
		}

		// Off-hook pins
		if (controls.pinLEDOffHookLaptopA) {
			controls.pinLEDOffHookLaptopA.on('update', ({ Bool }: any) => pinLEDOffHookLaptopA.set(!!Bool));
		}
		if (controls.pinLEDOffHookLaptopB) {
			controls.pinLEDOffHookLaptopB.on('update', ({ Bool }: any) => pinLEDOffHookLaptopB.set(!!Bool));
		}
		if (controls.pinLEDOffHookPCA) {
			controls.pinLEDOffHookPCA.on('update', ({ Bool }: any) => pinLEDOffHookPCA.set(!!Bool));
		}
		if (controls.pinLEDOffHookPCB) {
			controls.pinLEDOffHookPCB.on('update', ({ Bool }: any) => pinLEDOffHookPCB.set(!!Bool));
		}

		// HDMI Active pins
		if (controls.pinLEDHDMIActiveLaptopA) {
			controls.pinLEDHDMIActiveLaptopA.on('update', ({ Bool }: any) => pinLEDHDMIActiveLaptopA.set(!!Bool));
		}
		if (controls.pinLEDHDMIActiveLaptopB) {
			controls.pinLEDHDMIActiveLaptopB.on('update', ({ Bool }: any) => pinLEDHDMIActiveLaptopB.set(!!Bool));
		}
		if (controls.pinLEDHDMIActivePCA) {
			controls.pinLEDHDMIActivePCA.on('update', ({ Bool }: any) => pinLEDHDMIActivePCA.set(!!Bool));
		}
		if (controls.pinLEDHDMIActivePCB) {
			controls.pinLEDHDMIActivePCB.on('update', ({ Bool }: any) => pinLEDHDMIActivePCB.set(!!Bool));
		}

		// HDMI Connection pins (required for DivisibleSpace)
		if (controls.pinLEDHDMIConnectedLaptopA) {
			controls.pinLEDHDMIConnectedLaptopA.on('update', ({ Bool }: any) => pinLEDHDMIConnectedLaptopA.set(!!Bool));
		}
		if (controls.pinLEDHDMIConnectedLaptopB) {
			controls.pinLEDHDMIConnectedLaptopB.on('update', ({ Bool }: any) => pinLEDHDMIConnectedLaptopB.set(!!Bool));
		}
		if (controls.pinLEDHDMIConnectedPCA) {
			controls.pinLEDHDMIConnectedPCA.on('update', ({ Bool }: any) => pinLEDHDMIConnectedPCA.set(!!Bool));
		}
		if (controls.pinLEDHDMIConnectedPCB) {
			controls.pinLEDHDMIConnectedPCB.on('update', ({ Bool }: any) => pinLEDHDMIConnectedPCB.set(!!Bool));
		}

		// Other pins
		if (controls.pinLEDPresetSaved) {
			controls.pinLEDPresetSaved.on('update', ({ Bool }: any) => pinLEDPresetSaved.set(!!Bool));
		}
		if (controls.pinLEDACPRBypassSeparated) {
			controls.pinLEDACPRBypassSeparated.on('update', ({ Bool }: any) => pinLEDACPRBypassSeparated.set(!!Bool));
		}
		if (controls.pinLEDACPRBypassCombined) {
			controls.pinLEDACPRBypassCombined.on('update', ({ Bool }: any) => pinLEDACPRBypassCombined.set(!!Bool));
		}
		if (controls.pinLEDTouchActivity) {
			controls.pinLEDTouchActivity.on('update', ({ Bool }: any) => pinLEDTouchActivity.set(!!Bool));
		}

		// Subscribe to navigation buttons
		for (let i = 1; i <= 15; i++) {
			const btnName = `btnNav${String(i).padStart(2, '0')}`;
			const btnStore = navButtonStores[i - 1];
			if (controls[btnName]) {
				controls[btnName].on('update', ({ Bool }: any) => btnStore.set(!!Bool));
			}
		}

		// Subscribe to system controls
		if (controls.btnStartSystem) {
			controls.btnStartSystem.on('update', ({ Bool }: any) => btnStartSystem.set(!!Bool));
		}
		if (controls.btnNavShutdown) {
			controls.btnNavShutdown.on('update', ({ Bool }: any) => btnNavShutdown.set(!!Bool));
		}
		if (controls.btnShutdownCancel) {
			controls.btnShutdownCancel.on('update', ({ Bool }: any) => btnShutdownCancel.set(!!Bool));
		}
		if (controls.btnShutdownConfirm) {
			controls.btnShutdownConfirm.on('update', ({ Bool }: any) => btnShutdownConfirm.set(!!Bool));
		}

		// Subscribe to help buttons
		const helpButtonPairs = [
			{ open: 'btnOpenHelpLaptopA', close: 'btnCloseHelpLaptopA' },
			{ open: 'btnOpenHelpLaptopB', close: 'btnCloseHelpLaptopB' },
			{ open: 'btnOpenHelpPCA', close: 'btnCloseHelpPCA' },
			{ open: 'btnOpenHelpPCB', close: 'btnCloseHelpPCB' },
			{ open: 'btnOpenHelpWirelessA', close: 'btnCloseHelpWirelessA' },
			{ open: 'btnOpenHelpWirelessB', close: 'btnCloseHelpWirelessB' },
			{ open: 'btnOpenHelpRouting', close: 'btnCloseHelpRouting' },
			{ open: 'btnOpenHelpStreamMusic', close: 'btnCloseHelpStreamMusic' }
		];

		// Subscribe to progress controls
		if (controls.knbProgressBar) {
			controls.knbProgressBar.on('update', ({ Value }: any) => knbProgressBar.set(Value || 0));
		}
		if (controls.txtProgressBar) {
			controls.txtProgressBar.on('update', ({ String: str }: any) => txtProgressBar.set(str || '0%'));
		}

		subscriptionsInitialized = true;
		console.log('QRWC control subscriptions initialized');
	} catch (error) {
		console.error('Error initializing QRWC subscriptions:', error);
	}
});

// Control write functions
export function writeControl(controlName: string, value: boolean | number | string): void {
	const qrwc = getQrwc();
	if (!qrwc) {
		console.warn('QRWC not initialized, cannot write control:', controlName);
		return;
	}

	try {
		const pinsComponent = qrwc.components?.Pins;
		if (!pinsComponent) {
			console.warn('Pins component not found');
			return;
		}

		const control = pinsComponent.controls[controlName];
		if (!control) {
			console.warn(`Control ${controlName} not found`);
			return;
		}

		if (typeof value === 'boolean') {
			control.update({ Bool: value });
		} else if (typeof value === 'number') {
			control.update({ Value: value });
		} else {
			control.update({ String: value });
		}
	} catch (error) {
		console.error(`Error writing control ${controlName}:`, error);
	}
}

