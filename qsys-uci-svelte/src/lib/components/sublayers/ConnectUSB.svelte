<script lang="ts">
	import { fade } from 'svelte/transition';

	export let sourceName: string;
</script>

<div class="connect-usb" transition:fade>
	<div class="usb-message">
		<h3>Connect USB</h3>
		<p>Please connect USB cable to {sourceName}</p>
	</div>
</div>

<style>
	.connect-usb {
		background: rgba(255, 193, 7, 0.2);
		padding: 2rem;
		border-radius: 8px;
		margin-top: 2rem;
		border: 2px solid rgba(255, 193, 7, 0.5);
	}

	.usb-message h3 {
		color: #ffc107;
		margin-bottom: 0.5rem;
	}

	.usb-message p {
		color: white;
	}
</style>

