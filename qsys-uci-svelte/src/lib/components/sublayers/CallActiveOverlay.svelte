<script lang="ts">
	import { fade } from 'svelte/transition';
	import { pinCallActive } from '../../qrwc/controlsStore';

	let $callActive: boolean;
	pinCallActive.subscribe((val) => { $callActive = val; });
</script>

{#if $callActive}
	<div class="call-active-overlay" transition:fade>
		<div class="call-indicator">Call Active</div>
	</div>
{/if}

<style>
	.call-active-overlay {
		position: fixed;
		top: 20px;
		right: 20px;
		background: rgba(76, 175, 80, 0.9);
		padding: 1rem 2rem;
		border-radius: 8px;
		z-index: 1500;
	}

	.call-indicator {
		color: white;
		font-size: 1.2rem;
		font-weight: bold;
	}
</style>

