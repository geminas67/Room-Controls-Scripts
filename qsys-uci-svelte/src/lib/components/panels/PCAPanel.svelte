<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerPCA } from '../../state/layers';
	import {
		showHDMIDisconnectedPCA,
		showConferenceControlsPCA,
		showConnectUsbPCA,
		showHelpPCA,
		showCameraSelectionPCA,
		showVideoPrivacySeparatedA,
		showVideoPrivacyCombinedA,
		showACPRBtnCombined,
		showACPRBtnSeparated
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
	let $showCameraSelection: boolean;
	let $showVideoPrivacySeparated: boolean;
	let $showVideoPrivacyCombined: boolean;
	let $showACPRBtnCombined: boolean;
	let $showACPRBtnSeparated: boolean;

	activeLayer.subscribe((val) => { $activeLayer = val; });
	showHDMIDisconnectedPCA.subscribe((val) => { $showHDMIDisconnected = val; });
	showConferenceControlsPCA.subscribe((val) => { $showConferenceControls = val; });
	showConnectUsbPCA.subscribe((val) => { $showConnectUsb = val; });
	showHelpPCA.subscribe((val) => { $showHelp = val; });
	showCameraSelectionPCA.subscribe((val) => { $showCameraSelection = val; });
	showVideoPrivacySeparatedA.subscribe((val) => { $showVideoPrivacySeparated = val; });
	showVideoPrivacyCombinedA.subscribe((val) => { $showVideoPrivacyCombined = val; });
	showACPRBtnCombined.subscribe((val) => { $showACPRBtnCombined = val; });
	showACPRBtnSeparated.subscribe((val) => { $showACPRBtnSeparated = val; });
</script>

{#if $activeLayer === kLayerPCA}
	<div class="pca-panel" transition:fade>
		{#if $showHDMIDisconnected}
			<HDMIDisconnected sourceName="PC A" />
		{:else}
			<div class="pca-content">
				<h2>PC A</h2>
				
				{#if $showHelp}
					<HelpOverlay helpType="PCA" />
				{:else if $showConferenceControls}
					<ConferenceControls sourceName="PCA" />
					{#if $showCameraSelection}
						<div class="camera-selection">Camera Selection</div>
					{/if}
					{#if $showVideoPrivacySeparated}
						<div class="video-privacy">Video Privacy (Separated)</div>
					{/if}
					{#if $showVideoPrivacyCombined}
						<div class="video-privacy">Video Privacy (Combined)</div>
					{/if}
					{#if $showACPRBtnCombined}
						<div class="acpr-button">ACPR Button (Combined)</div>
					{/if}
					{#if $showACPRBtnSeparated}
						<div class="acpr-button">ACPR Button (Separated)</div>
					{/if}
				{:else if $showConnectUsb}
					<ConnectUSB sourceName="PCA" />
				{/if}
			</div>
		{/if}
		
		<CallActiveOverlay />
	</div>
{/if}

<style>
	.pca-panel {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(20, 20, 30, 0.98);
		z-index: 100;
		padding: 2rem;
	}

	.pca-content h2 {
		color: white;
		font-size: 2rem;
		margin-bottom: 2rem;
	}

	.camera-selection,
	.video-privacy,
	.acpr-button {
		margin-top: 1rem;
		padding: 1rem;
		background: rgba(255, 255, 255, 0.1);
		border-radius: 4px;
		color: white;
	}
</style>

