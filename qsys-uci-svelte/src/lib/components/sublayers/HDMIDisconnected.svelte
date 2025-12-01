<script lang="ts">
	import { fade } from 'svelte/transition';

	export let sourceName: string;
</script>

<div class="hdmi-disconnected" transition:fade>
	<div class="disconnected-message">
		<h3>HDMI Disconnected</h3>
		<p>{sourceName} HDMI connection not detected</p>
	</div>
</div>

<style>
	.hdmi-disconnected {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: rgba(0, 0, 0, 0.95);
	}

	.disconnected-message {
		text-align: center;
		color: white;
	}

	.disconnected-message h3 {
		font-size: 2rem;
		margin-bottom: 1rem;
		color: #ff6b6b;
	}

	.disconnected-message p {
		font-size: 1.2rem;
		color: #ccc;
	}
</style>

