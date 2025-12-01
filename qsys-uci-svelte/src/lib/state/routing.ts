import { writable } from 'svelte/store';

export const routingLayers = ['R01', 'R02', 'R03', 'R04', 'R05'];
export const activeRoutingLayer = writable<number>(1);

export function goToRoutingLayer(index: number): void {
	if (index < 1 || index > routingLayers.length) {
		index = 1;
	}
	activeRoutingLayer.set(index);
}

