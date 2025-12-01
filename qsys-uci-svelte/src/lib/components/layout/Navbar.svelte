<script lang="ts">
	import { fade } from 'svelte/transition';
	import { activeLayer, layerToButtonMap, goToLayer } from '../../state/layers';
	import { navButtonStores, writeControl } from '../../qrwc/controlsStore';
	import { roomState, roomIdentity, shouldShowLayer } from '../../state/divisibleSpace';
	import { switchToInput } from '../../state/videoSwitcher';
	import { videoSwitcherEnabled } from '../../state/videoSwitcher';

	let $activeLayer: number = 3;
	let $roomState: string = 'separated';
	let $roomIdentity: string | null = null;
	let $videoSwitcherEnabled: boolean = false;

	activeLayer.subscribe((val) => { $activeLayer = val; });
	roomState.subscribe((val) => { $roomState = val; });
	roomIdentity.subscribe((val) => { $roomIdentity = val; });
	videoSwitcherEnabled.subscribe((val) => { $videoSwitcherEnabled = val; });

	// Centralized navigation handler (mirrors btnNavEventHandler from Lua)
	function handleNavClick(buttonIndex: number): void {
		const layerId = Object.keys(layerToButtonMap).find(
			(key) => layerToButtonMap[Number(key)] === buttonIndex
		);

		if (!layerId) return;

		const targetLayer = Number(layerId);

		// Check if layer should be shown (divisible space conditional visibility)
		if (!shouldShowLayer(targetLayer, $roomState as any, $roomIdentity as any)) {
			return;
		}

		// Update active layer
		goToLayer(targetLayer);

		// Trigger video switcher if enabled
		if ($videoSwitcherEnabled) {
			switchToInput(targetLayer);
		}

		// Update button interlock state
		updateButtonInterlock();
	}

	// Update button interlock state
	function updateButtonInterlock(): void {
		const activeButtonIndex = layerToButtonMap[$activeLayer];
		if (!activeButtonIndex) return;

		navButtonStores.forEach((store, index) => {
			const shouldBeActive = index + 1 === activeButtonIndex;
			store.set(shouldBeActive);
			
			// Write to QRWC control
			const btnName = `btnNav${String(index + 1).padStart(2, '0')}`;
			writeControl(btnName, shouldBeActive);
		});
	}

	// Update interlock when active layer changes
	activeLayer.subscribe(() => {
		updateButtonInterlock();
	});

	// Navigation button labels (will be populated from UCI variables)
	const navLabels = [
		'Alarm', 'Incoming Call', 'Start', 'Warming', 'Cooling',
		'Room Controls', 'PC A', 'PC B', 'Laptop A', 'Laptop B',
		'Wireless', 'Routing', 'Dialer', 'Stream Music', 'Room Combining'
	];
</script>

<nav class="navbar">
	{#each navButtonStores as store, index}
		{@const buttonIndex = index + 1}
		{@const layerId = Object.keys(layerToButtonMap).find(key => layerToButtonMap[Number(key)] === buttonIndex)}
		{@const isActive = $activeLayer && layerToButtonMap[$activeLayer] === buttonIndex}
		{@const shouldShow = layerId ? shouldShowLayer(Number(layerId), $roomState as any, $roomIdentity as any) : true}
		
		{#if shouldShow}
			<button
				class="nav-button"
				class:active={isActive}
				on:click={() => handleNavClick(buttonIndex)}
				transition:fade
			>
				{navLabels[index] || `Nav ${buttonIndex}`}
			</button>
		{/if}
	{/each}
</nav>

<style>
	.navbar {
		display: flex;
		gap: 0.5rem;
		padding: 1rem;
		background: rgba(0, 0, 0, 0.8);
	}

	.nav-button {
		padding: 0.75rem 1.5rem;
		background: rgba(255, 255, 255, 0.1);
		border: 2px solid rgba(255, 255, 255, 0.2);
		border-radius: 4px;
		color: white;
		cursor: pointer;
		transition: all 0.2s;
	}

	.nav-button:hover {
		background: rgba(255, 255, 255, 0.2);
	}

	.nav-button.active {
		background: rgba(0, 150, 255, 0.8);
		border-color: rgba(0, 150, 255, 1);
	}
</style>

