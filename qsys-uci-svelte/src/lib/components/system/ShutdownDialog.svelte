<script lang="ts">
	import { fade } from 'svelte/transition';
	import { btnNavShutdown, btnShutdownCancel, btnShutdownConfirm, writeControl } from '../../qrwc/controlsStore';
	import { powerOff } from '../../state/roomAutomation';
	import { goToLayer, kLayerCooling } from '../../state/layers';
	import { startLoadingBar } from '../../state/progress';

	let $showDialog = false;

	btnNavShutdown.subscribe((val) => {
		if (val) {
			$showDialog = true;
		}
	});

	btnShutdownCancel.subscribe((val) => {
		if (val) {
			$showDialog = false;
			writeControl('btnNavShutdown', false);
		}
	});

	function handleConfirm(): void {
		$showDialog = false;
		writeControl('btnShutdownConfirm', true);
		powerOff();
		startLoadingBar(false);
		goToLayer(kLayerCooling);
	}

	function handleCancel(): void {
		$showDialog = false;
		writeControl('btnShutdownCancel', true);
	}
</script>

{#if $showDialog}
	<div class="shutdown-overlay" transition:fade>
		<div class="shutdown-dialog" transition:fade>
			<h2>Confirm Shutdown</h2>
			<p>Are you sure you want to shut down the system?</p>
			<div class="dialog-buttons">
				<button class="btn-cancel" on:click={handleCancel}>Cancel</button>
				<button class="btn-confirm" on:click={handleConfirm}>Confirm</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.shutdown-overlay {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		background: rgba(0, 0, 0, 0.8);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 3000;
	}

	.shutdown-dialog {
		background: #1a1a1a;
		padding: 2rem;
		border-radius: 8px;
		min-width: 400px;
		border: 2px solid #333;
	}

	.shutdown-dialog h2 {
		color: white;
		margin: 0 0 1rem 0;
	}

	.shutdown-dialog p {
		color: #ccc;
		margin: 0 0 2rem 0;
	}

	.dialog-buttons {
		display: flex;
		gap: 1rem;
		justify-content: flex-end;
	}

	.btn-cancel,
	.btn-confirm {
		padding: 0.75rem 1.5rem;
		border: none;
		border-radius: 4px;
		cursor: pointer;
		font-size: 1rem;
		transition: all 0.2s;
	}

	.btn-cancel {
		background: rgba(255, 255, 255, 0.1);
		color: white;
	}

	.btn-cancel:hover {
		background: rgba(255, 255, 255, 0.2);
	}

	.btn-confirm {
		background: #d32f2f;
		color: white;
	}

	.btn-confirm:hover {
		background: #b71c1c;
	}
</style>

