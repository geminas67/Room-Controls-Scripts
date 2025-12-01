<script lang="ts">
	import { fade } from 'svelte/transition';

	export let sourceName: string;
</script>

<div class="conference-controls" transition:fade>
	<h3>Conference Controls - {sourceName}</h3>
	<div class="controls-grid">
		<!-- Conference control buttons will be implemented here -->
		<button class="control-btn">Mute</button>
		<button class="control-btn">Camera</button>
		<button class="control-btn">Share</button>
	</div>
</div>

<style>
	.conference-controls {
		background: rgba(255, 255, 255, 0.1);
		padding: 2rem;
		border-radius: 8px;
		margin-top: 2rem;
	}

	.conference-controls h3 {
		color: white;
		margin-bottom: 1rem;
	}

	.controls-grid {
		display: flex;
		gap: 1rem;
	}

	.control-btn {
		padding: 1rem 2rem;
		background: rgba(0, 150, 255, 0.8);
		color: white;
		border: none;
		border-radius: 4px;
		cursor: pointer;
		transition: all 0.2s;
	}

	.control-btn:hover {
		background: rgba(0, 150, 255, 1);
	}
</style>

