<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerPCB } from '../../state/layers';
	import {
		showHDMIDisconnectedPCB,
		showConferenceControlsPCB,
		showConnectUsbPCB,
		showHelpPCB
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
	showHDMIDisconnectedPCB.subscribe((val) => { $showHDMIDisconnected = val; });
	showConferenceControlsPCB.subscribe((val) => { $showConferenceControls = val; });
	showConnectUsbPCB.subscribe((val) => { $showConnectUsb = val; });
	showHelpPCB.subscribe((val) => { $showHelp = val; });
</script>

{#if $activeLayer === kLayerPCB}
	<div class="pcb-panel" transition:fade>
		{#if $showHDMIDisconnected}
			<HDMIDisconnected sourceName="PC B" />
		{:else}
			<div class="pcb-content">
				<h2>PC B</h2>
				
				{#if $showHelp}
					<HelpOverlay helpType="PCB" />
				{:else if $showConferenceControls}
					<ConferenceControls sourceName="PCB" />
				{:else if $showConnectUsb}
					<ConnectUSB sourceName="PCB" />
				{/if}
			</div>
		{/if}
		
		<CallActiveOverlay />
	</div>
{/if}

<style>
	.pcb-panel {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(20, 20, 30, 0.98);
		z-index: 100;
		padding: 2rem;
	}

	.pcb-content h2 {
		color: white;
		font-size: 2rem;
		margin-bottom: 2rem;
	}
</style>

