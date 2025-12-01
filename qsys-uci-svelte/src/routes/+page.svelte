<script lang="ts">
	import { onMount } from 'svelte';
	import { initQrwc, qrwcReady, qrwcError } from '../lib/qrwc/qrwcClient';
	import BaseLayout from '../lib/components/layout/BaseLayout.svelte';
	import ProgressBar from '../lib/components/system/ProgressBar.svelte';
	import ShutdownDialog from '../lib/components/system/ShutdownDialog.svelte';
	import StartPanel from '../lib/components/panels/StartPanel.svelte';
	import LaptopAPanel from '../lib/components/panels/LaptopAPanel.svelte';
	import LaptopBPanel from '../lib/components/panels/LaptopBPanel.svelte';
	import PCAPanel from '../lib/components/panels/PCAPanel.svelte';
	import PCBPanel from '../lib/components/panels/PCBPanel.svelte';
	import RoutingPanel from '../lib/components/panels/RoutingPanel.svelte';
	import { activeLayer, kLayerStart, kLayerWarming, kLayerCooling } from '../lib/state/layers';
	import { pinLEDHDMIActiveLaptopA, pinLEDHDMIActiveLaptopB, pinLEDHDMIActivePCA, pinLEDHDMIActivePCB } from '../lib/qrwc/controlsStore';
	import { goToLayer, kLayerLaptopA, kLayerLaptopB, kLayerPCA, kLayerPCB } from '../lib/state/layers';
	import { powerOn, systemPowerState } from '../lib/state/roomAutomation';
	import { startLoadingBar } from '../lib/state/progress';

	let $qrwcReady = false;
	let $qrwcError: string | null = null;
	let $activeLayer: number = kLayerStart;
	let $systemPowerState: boolean = false;

	// Subscribe to stores
	qrwcReady.subscribe((val) => { $qrwcReady = val; });
	qrwcError.subscribe((val) => { $qrwcError = val; });
	activeLayer.subscribe((val) => { $activeLayer = val; });
	systemPowerState.subscribe((val) => { $systemPowerState = val; });

	onMount(async () => {
		// Initialize QRWC connection
		// Adjust WebSocket URL based on your Q-SYS core configuration
		const socketUrl = import.meta.env.VITE_QRWC_SOCKET_URL || 'ws://localhost:1710';
		
		try {
			await initQrwc(socketUrl);
		} catch (error: any) {
			console.error('Failed to initialize QRWC:', error);
		}

		// Set up pin handlers for automatic layer switching
		pinLEDHDMIActiveLaptopA.subscribe((val) => {
			if (val && !$systemPowerState) {
				powerOn();
				startLoadingBar(true);
				goToLayer(kLayerWarming);
			} else if (val) {
				goToLayer(kLayerLaptopA);
			}
		});

		pinLEDHDMIActiveLaptopB.subscribe((val) => {
			if (val && !$systemPowerState) {
				powerOn();
				startLoadingBar(true);
				goToLayer(kLayerWarming);
			} else if (val) {
				goToLayer(kLayerLaptopB);
			}
		});

		pinLEDHDMIActivePCA.subscribe((val) => {
			if (val && !$systemPowerState) {
				powerOn();
				startLoadingBar(true);
				goToLayer(kLayerWarming);
			} else if (val) {
				goToLayer(kLayerPCA);
			}
		});

		pinLEDHDMIActivePCB.subscribe((val) => {
			if (val && !$systemPowerState) {
				powerOn();
				startLoadingBar(true);
				goToLayer(kLayerWarming);
			} else if (val) {
				goToLayer(kLayerPCB);
			}
		});
	});
</script>

<svelte:head>
	<title>Q-SYS UCI Controller</title>
</svelte:head>

<BaseLayout>
	{#if $qrwcError}
		<div class="error-banner">
			<p>Connection Error: {$qrwcError}</p>
		</div>
	{/if}

	{#if !$qrwcReady}
		<div class="loading-screen">
			<div class="loading-spinner"></div>
			<p>Connecting to Q-SYS Core...</p>
		</div>
	{:else}
		<!-- Main panel content based on active layer -->
		<StartPanel />
		<LaptopAPanel />
		<LaptopBPanel />
		<PCAPanel />
		<PCBPanel />
		<RoutingPanel />
		<!-- Additional panels (Wireless, Dialer, StreamMusic, RoomCombining, etc.) will be added here -->
	{/if}

	<!-- System components -->
	<ProgressBar />
	<ShutdownDialog />
</BaseLayout>

<style>
	:global(body) {
		margin: 0;
		padding: 0;
		font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
		background: #000;
		color: white;
		overflow: hidden;
	}

	.error-banner {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		background: #d32f2f;
		color: white;
		padding: 1rem;
		text-align: center;
		z-index: 5000;
	}

	.loading-screen {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		background: #000;
		z-index: 4000;
	}

	.loading-spinner {
		width: 50px;
		height: 50px;
		border: 4px solid rgba(255, 255, 255, 0.1);
		border-top-color: #0096ff;
		border-radius: 50%;
		animation: spin 1s linear infinite;
		margin-bottom: 1rem;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	.loading-screen p {
		color: #ccc;
		font-size: 1.2rem;
	}
</style>

