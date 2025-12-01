<script lang="ts">
	import { fade } from 'svelte/transition';
	import Navbar from './Navbar.svelte';
	import ProgramVolumeStrip from './ProgramVolumeStrip.svelte';

	// Base layers are always visible (X01, Y01, Z01)
	export let showBaseLayers = true;
</script>

<div class="base-layout">
	{#if showBaseLayers}
		<!-- Z01-Base layer -->
		<div class="base-layer" transition:fade>
			<!-- Y01-Navbar layer -->
			<Navbar />
			
			<!-- X01-ProgramVolume layer -->
			<ProgramVolumeStrip />
		</div>
	{/if}
	
	<slot />
</div>

<style>
	.base-layout {
		position: relative;
		width: 100%;
		height: 100%;
	}

	.base-layer {
		position: absolute;
		top: 0;
		left: 0;
		width: 100%;
		height: 100%;
		z-index: 1;
	}
</style>

