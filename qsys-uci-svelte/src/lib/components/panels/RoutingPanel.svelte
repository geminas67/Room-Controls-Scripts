<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, kLayerRouting } from '../../state/layers';
	import { activeRoutingLayer, routingLayers } from '../../state/routing';
	import RoutingPage01 from '../routing/RoutingPage01.svelte';
	import RoutingPage02 from '../routing/RoutingPage02.svelte';
	import RoutingPage03 from '../routing/RoutingPage03.svelte';
	import RoutingPage04 from '../routing/RoutingPage04.svelte';
	import RoutingPage05 from '../routing/RoutingPage05.svelte';
	import CallActiveOverlay from '../sublayers/CallActiveOverlay.svelte';

	let $activeLayer: number;
	let $activeRoutingLayer: number;

	activeLayer.subscribe((val) => { $activeLayer = val; });
	activeRoutingLayer.subscribe((val) => { $activeRoutingLayer = val; });
</script>

{#if $activeLayer === kLayerRouting}
	<div class="routing-panel" transition:fade>
		<div class="routing-content">
			<h2>Routing</h2>
			
			{#if $activeRoutingLayer === 1}
				<RoutingPage01 />
			{:else if $activeRoutingLayer === 2}
				<RoutingPage02 />
			{:else if $activeRoutingLayer === 3}
				<RoutingPage03 />
			{:else if $activeRoutingLayer === 4}
				<RoutingPage04 />
			{:else if $activeRoutingLayer === 5}
				<RoutingPage05 />
			{/if}
		</div>
		
		<CallActiveOverlay />
	</div>
{/if}

<style>
	.routing-panel {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(20, 20, 30, 0.98);
		z-index: 100;
		padding: 2rem;
	}

	.routing-content h2 {
		color: white;
		font-size: 2rem;
		margin-bottom: 2rem;
	}
</style>

