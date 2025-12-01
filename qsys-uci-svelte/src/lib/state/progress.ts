import { writable } from 'svelte/store';
import { knbProgressBar, txtProgressBar } from '../qrwc/controlsStore';
import { getTiming } from './roomAutomation';

export const isAnimating = writable<boolean>(false);
export const progressValue = writable<number>(0);

let animationTimer: number | null = null;
let timeoutTimer: number | null = null;

export function startLoadingBar(isPoweringOn: boolean): void {
	let $isAnimating = false;
	isAnimating.subscribe((val) => { $isAnimating = val; })();
	if ($isAnimating) return;

	isAnimating.set(true);
	const duration = getTiming(isPoweringOn);
	const steps = 100;
	const interval = (duration * 1000) / steps; // Convert to milliseconds
	let currentStep = 0;

	// Cleanup existing timers
	if (animationTimer) {
		clearInterval(animationTimer);
		animationTimer = null;
	}
	if (timeoutTimer) {
		clearTimeout(timeoutTimer);
		timeoutTimer = null;
	}

	// Initialize progress display
	progressValue.set(isPoweringOn ? 0 : 100);
	knbProgressBar.set(isPoweringOn ? 0 : 100);
	txtProgressBar.set((isPoweringOn ? 0 : 100) + '%');

	// Timeout protection (5 minutes)
	timeoutTimer = window.setTimeout(() => {
		if (isAnimating) {
			isAnimating.set(false);
			if (animationTimer) {
				clearInterval(animationTimer);
				animationTimer = null;
			}
		}
	}, 300000);

	// Progress animation
	animationTimer = window.setInterval(() => {
		currentStep += 1;

		const progress = isPoweringOn ? currentStep : (100 - currentStep);
		progressValue.set(progress);
		knbProgressBar.set(progress);
		txtProgressBar.set(progress + '%');

		if (currentStep >= steps) {
			if (animationTimer) {
				clearInterval(animationTimer);
				animationTimer = null;
			}
			if (timeoutTimer) {
				clearTimeout(timeoutTimer);
				timeoutTimer = null;
			}
			isAnimating.set(false);
		}
	}, interval);
}

export function stopLoadingBar(): void {
	if (animationTimer) {
		clearInterval(animationTimer);
		animationTimer = null;
	}
	if (timeoutTimer) {
		clearTimeout(timeoutTimer);
		timeoutTimer = null;
	}
	isAnimating.set(false);
}

