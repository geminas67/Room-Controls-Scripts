import { writable } from 'svelte/store';
import { getQrwc, qrwcReady } from '../qrwc/qrwcClient';
import { roomIdentity } from './divisibleSpace';

export const videoSwitcherEnabled = writable<boolean>(false);
export const videoSwitcherType = writable<string | null>(null);

// AVProEdge switcher configuration (matching DivisibleSpace UCIController)
const switcherTypes = {
	AVProEdge: {
		componentType: '%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f',
		switcherNames: ['devAVProEdge', 'compAVProEdge', 'varAVProEdge'],
		outputMappings: {
			CollabA: {
				7: 'Input 3',   // kLayerPCA -> Input 3
				8: 'Input 4',   // kLayerPCB -> Input 4
				9: 'Input 1',   // kLayerLaptopA -> Input 1
				10: 'Input 2'   // kLayerLaptopB -> Input 2
			},
			CollabB: {
				7: 'Input 7',   // kLayerPCA -> Input 7
				8: 'Input 8',   // kLayerPCB -> Input 8
				9: 'Input 5',   // kLayerLaptopA -> Input 5
				10: 'Input 6'   // kLayerLaptopB -> Input 6
			}
		}
	}
};

// Initialize video switcher detection
qrwcReady.subscribe((ready) => {
	if (!ready) return;

	const qrwc = getQrwc();
	if (!qrwc) return;

	try {
		// Auto-detect switcher
		for (const [switcherType, config] of Object.entries(switcherTypes)) {
			// Check UCI variables first
			const uciVars = qrwc.components?.Uci?.variables;
			for (const switchName of config.switcherNames) {
				if (uciVars?.[switchName]?.String) {
					videoSwitcherType.set(switcherType);
					videoSwitcherEnabled.set(true);
					return;
				}
			}

			// Check available components
			const components = qrwc.components;
			if (components) {
				for (const compName in components) {
					const comp = components[compName];
					if (comp?.Type === config.componentType) {
						videoSwitcherType.set(switcherType);
						videoSwitcherEnabled.set(true);
						return;
					}
				}
			}
		}
	} catch (error) {
		console.error('Error initializing video switcher:', error);
	}
});

// Switch to input based on UCI button and room identity
export function switchToInput(uciButton: number): boolean {
	const qrwc = getQrwc();
	if (!qrwc) {
		return false;
	}

	let $switcherEnabled = false;
	let $switcherType: string | null = null;
	let $roomIdentity: 'CollabA' | 'CollabB' | null = null;

	videoSwitcherEnabled.subscribe((val) => { $switcherEnabled = val; })();
	videoSwitcherType.subscribe((val) => { $switcherType = val; })();
	roomIdentity.subscribe((val) => { $roomIdentity = val; })();

	if (!$switcherEnabled) {
		return false;
	}

	if (!$switcherType || !$roomIdentity) {
		return false;
	}

	const config = switcherTypes[$switcherType as keyof typeof switcherTypes];
	if (!config) {
		return false;
	}

	const inputMapping = config.outputMappings[$roomIdentity];
	if (!inputMapping) {
		return false;
	}

	const inputControlName = inputMapping[uciButton as keyof typeof inputMapping];
	if (!inputControlName) {
		return false;
	}

	try {
		const switcherComponent = qrwc.components?.VideoSwitcher;
		if (!switcherComponent) {
			return false;
		}

		const inputControl = switcherComponent.controls?.[inputControlName];
		if (inputControl) {
			inputControl.trigger();
			return true;
		}
	} catch (error) {
		console.error('Error switching video input:', error);
	}

	return false;
}

