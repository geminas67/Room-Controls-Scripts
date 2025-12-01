<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerLaptopB } from '../../state/layers';
	import {
		showHDMIDisconnectedLaptopB,
		showConferenceControlsLaptopB,
		showConnectUsbLaptopB,
		showHelpLaptopB
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
	showHDMIDisconnectedLaptopB.subscribe((val) => { $showHDMIDisconnected = val; });
	showConferenceControlsLaptopB.subscribe((val) => { $showConferenceControls = val; });
	showConnectUsbLaptopB.subscribe((val) => { $showConnectUsb = val; });
	showHelpLaptopB.subscribe((val) => { $showHelp = val; });
</script>

{#if $activeLayer === kLayerLaptopB}
	<div class="laptop-b-panel" transition:fade>
		{#if $showHDMIDisconnected}
			<HDMIDisconnected sourceName="Laptop B" />
		{:else}
			<div class="laptop-content">
				<h2>Laptop B</h2>
				
				{#if $showHelp}
					<HelpOverlay helpType="LaptopB" />
				{:else if $showConferenceControls}
					<ConferenceControls sourceName="LaptopB" />
				{:else if $showConnectUsb}
					<ConnectUSB sourceName="LaptopB" />
				{/if}
			</div>
		{/if}
		
		<CallActiveOverlay />
	</div>
{/if}

<style>
	.laptop-b-panel {
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

