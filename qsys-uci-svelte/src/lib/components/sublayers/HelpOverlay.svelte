<script lang="ts">
	import { fade } from 'svelte/transition';

	export let helpType: string;
</script>

<div class="help-overlay" transition:fade>
	<div class="help-content">
		<h3>Help - {helpType}</h3>
		<p>Help information for {helpType} will be displayed here.</p>
		<!-- Help content will be populated from UCI variables -->
	</div>
</div>

<style>
	.help-overlay {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(0, 0, 0, 0.95);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 200;
	}

	.help-content {
		background: rgba(30, 30, 40, 0.98);
		padding: 3rem;
		border-radius: 8px;
		max-width: 800px;
		max-height: 90vh;
		overflow-y: auto;
	}

	.help-content h3 {
		color: white;
		font-size: 2rem;
		margin-bottom: 1rem;
	}

	.help-content p {
		color: #ccc;
		line-height: 1.6;
	}
</style>

