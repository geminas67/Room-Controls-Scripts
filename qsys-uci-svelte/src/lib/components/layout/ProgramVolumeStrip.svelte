<script lang="ts">
	// Program volume controls (X01 layer)
	// This would connect to actual volume controls via QRWC
</script>

<div class="program-volume-strip">
	<!-- Program volume controls will be implemented here -->
	<div class="volume-label">Program Volume</div>
</div>

<style>
	.program-volume-strip {
		position: fixed;
		bottom: 0;
		left: 0;
		right: 0;
		height: 60px;
		background: rgba(0, 0, 0, 0.9);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 1000;
	}

	.volume-label {
		color: white;
		font-size: 1rem;
	}
</style>

