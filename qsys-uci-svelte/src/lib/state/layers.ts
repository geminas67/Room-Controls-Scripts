import { writable } from 'svelte/store';

// Layer constants matching DivisibleSpace UCIController
export const kLayerAlarm = 1;
export const kLayerIncomingCall = 2;
export const kLayerStart = 3;
export const kLayerWarming = 4;
export const kLayerCooling = 5;
export const kLayerRoomControls = 6;
export const kLayerPCA = 7;
export const kLayerPCB = 8;
export const kLayerLaptopA = 9;
export const kLayerLaptopB = 10;
export const kLayerWireless = 11;
export const kLayerRouting = 12;
export const kLayerDialer = 13;
export const kLayerStreamMusic = 14;
export const kLayerRoomCombining = 15;

// Active layer store
export const activeLayer = writable<number>(kLayerStart);

// Helper function to navigate to a layer
export function goToLayer(layerId: number): void {
	activeLayer.set(layerId);
}

// Layer to button index mapping (for interlocking)
export const layerToButtonMap: Record<number, number> = {
	[kLayerAlarm]: 1,
	[kLayerIncomingCall]: 2,
	[kLayerStart]: 3,
	[kLayerWarming]: 4,
	[kLayerCooling]: 5,
	[kLayerRoomControls]: 6,
	[kLayerPCA]: 7,
	[kLayerPCB]: 8,
	[kLayerLaptopA]: 9,
	[kLayerLaptopB]: 10,
	[kLayerWireless]: 11,
	[kLayerRouting]: 12,
	[kLayerDialer]: 13,
	[kLayerStreamMusic]: 14,
	[kLayerRoomCombining]: 15
};

