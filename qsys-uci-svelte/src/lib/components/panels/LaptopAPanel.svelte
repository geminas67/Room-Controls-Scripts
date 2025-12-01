<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerLaptopA } from '../../state/layers';
	import {
		showHDMIDisconnectedLaptopA,
		showConferenceControlsLaptopA,
		showConnectUsbLaptopA,
		showHelpLaptopA
	} from '../../state/sublayers';
	import CallActiveOverlay from '../sublayers/CallActiveOverlay.svelte';
	import HDMIDisconnected from '../sublayers/HDMIDisconnected.svelte';
	import ConferenceControls from '../sublayers/ConferenceControls.svelte';
	import ConnectUSB from '../sublayers/ConnectUSB.svelte';
	import HelpOverlay from '../sublayers/HelpOverlay.svelte';

	let $activeLayer: number;
	let $showHDMIDisconnected: boolean;
	let $showConferenceControls: boolean;
	let $showConnectUsb: boolean;
	let $showHelp: boolean;

	activeLayer.subscribe((val) => { $activeLayer = val; });
	showHDMIDisconnectedLaptopA.subscribe((val) => { $showHDMIDisconnected = val; });
	showConferenceControlsLaptopA.subscribe((val) => { $showConferenceControls = val; });
	showConnectUsbLaptopA.subscribe((val) => { $showConnectUsb = val; });
	showHelpLaptopA.subscribe((val) => { $showHelp = val; });
</script>

{#if $activeLayer === kLayerLaptopA}
	<div class="laptop-a-panel" transition:fade>
		{#if $showHDMIDisconnected}
			<HDMIDisconnected sourceName="Laptop A" />
		{:else}
			<div class="laptop-content">
				<h2>Laptop A</h2>
				
				{#if $showHelp}
					<HelpOverlay helpType="LaptopA" />
				{:else if $showConferenceControls}
					<ConferenceControls sourceName="LaptopA" />
				{:else if $showConnectUsb}
					<ConnectUSB sourceName="LaptopA" />
				{/if}
			</div>
		{/if}
		
		<CallActiveOverlay />
	</div>
{/if}

<style>
	.laptop-a-panel {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(20, 20, 30, 0.98);
		z-index: 100;
		padding: 2rem;
	}

	.laptop-content h2 {
		color: white;
		font-size: 2rem;
		margin-bottom: 2rem;
	}
</style>

