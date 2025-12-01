<script lang="ts">
	import { fade } from 'svelte/transition';
	import { progressValue, isAnimating } from '../../state/progress';
	import { systemWarming, systemCooling } from '../../state/roomAutomation';

	let $progressValue: number;
	let $isAnimating: boolean;
	let $systemWarming: boolean;
	let $systemCooling: boolean;

	progressValue.subscribe((val) => { $progressValue = val; });
	isAnimating.subscribe((val) => { $isAnimating = val; });
	systemWarming.subscribe((val) => { $systemWarming = val; });
	systemCooling.subscribe((val) => { $systemCooling = val; });

	const showProgress = $isAnimating || $systemWarming || $systemCooling;
	const progressText = $systemWarming ? 'Warming...' : $systemCooling ? 'Cooling...' : 'Loading...';
</script>

{#if showProgress}
	<div class="progress-container" transition:fade>
		<div class="progress-label">{progressText}</div>
		<div class="progress-bar">
			<div class="progress-fill" style="width: {$progressValue}%"></div>
		</div>
		<div class="progress-text">{$progressValue}%</div>
	</div>
{/if}

<style>
	.progress-container {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		background: rgba(0, 0, 0, 0.9);
		padding: 2rem;
		border-radius: 8px;
		min-width: 400px;
		z-index: 2000;
	}

	.progress-label {
		color: white;
		font-size: 1.5rem;
		margin-bottom: 1rem;
		text-align: center;
	}

	.progress-bar {
		width: 100%;
		height: 30px;
		background: rgba(255, 255, 255, 0.2);
		border-radius: 15px;
		overflow: hidden;
		margin-bottom: 0.5rem;
	}

	.progress-fill {
		height: 100%;
		background: linear-gradient(90deg, #0096ff, #00d4ff);
		transition: width 0.1s linear;
	}

	.progress-text {
		color: white;
		text-align: center;
		font-size: 1.2rem;
	}
</style>

