<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerStart } from '../../state/layers';
	import { btnStartSystem, writeControl } from '../../qrwc/controlsStore';
	import { powerOn } from '../../state/roomAutomation';
	import { goToLayer, kLayerWarming } from '../../state/layers';
	import { startLoadingBar } from '../../state/progress';
	import { roomState } from '../../state/divisibleSpace';

	let $activeLayer: number;
	let $roomState: string;

	activeLayer.subscribe((val) => { $activeLayer = val; });
	roomState.subscribe((val) => { $roomState = val; });

	function handleStartSystem(): void {
		writeControl('btnStartSystem', true);
		powerOn();
		startLoadingBar(true);
		goToLayer(kLayerWarming);
	}

	// Update button legend based on room state
	$: startButtonLabel = $roomState === 'separated' ? 'Start Room' : 'Start Rooms';
</script>

{#if $activeLayer === kLayerStart}
	<div class="start-panel" transition:fade>
		<div class="start-content">
			<h1>System Start</h1>
			<button class="start-button" on:click={handleStartSystem}>
				{startButtonLabel}
			</button>
		</div>
	</div>
{/if}

<style>
	.start-panel {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: rgba(0, 0, 0, 0.95);
		z-index: 100;
	}

	.start-content {
		text-align: center;
	}

	.start-content h1 {
		color: white;
		font-size: 3rem;
		margin-bottom: 2rem;
	}

	.start-button {
		padding: 1.5rem 3rem;
		font-size: 1.5rem;
		background: #0096ff;
		color: white;
		border: none;
		border-radius: 8px;
		cursor: pointer;
		transition: all 0.2s;
	}

	.start-button:hover {
		background: #007acc;
		transform: scale(1.05);
	}
</style>

