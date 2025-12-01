import { derived } from 'svelte/store';
import { activeLayer, kLayerLaptopA, kLayerLaptopB, kLayerPCA, kLayerPCB } from './layers';
import {
	pinLEDHDMIConnectedLaptopA,
	pinLEDHDMIConnectedLaptopB,
	pinLEDHDMIConnectedPCA,
	pinLEDHDMIConnectedPCB,
	pinLEDUSBLaptopA,
	pinLEDUSBLaptopB,
	pinLEDUSBPCA,
	pinLEDUSBPCB,
	pinLEDACPRBypassSeparated,
	pinLEDACPRBypassCombined,
	pinCallActive,
	pinLEDPresetSaved,
	btnOpenHelpLaptopA,
	btnOpenHelpLaptopB,
	btnOpenHelpPCA,
	btnOpenHelpPCB,
	btnOpenHelpWirelessA,
	btnOpenHelpWirelessB,
	btnOpenHelpRouting,
	btnOpenHelpStreamMusic
} from '../qrwc/controlsStore';
import { roomState } from './divisibleSpace';

// Source readiness (HDMI + USB connected)
export const laptopAReady = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopA, pinLEDUSBLaptopA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopA && $hdmi && $usb
);

export const laptopBReady = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopB, pinLEDUSBLaptopB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopB && $hdmi && $usb
);

export const pcaReady = derived(
	[activeLayer, pinLEDHDMIConnectedPCA, pinLEDUSBPCA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCA && $hdmi && $usb
);

export const pcbReady = derived(
	[activeLayer, pinLEDHDMIConnectedPCB, pinLEDUSBPCB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCB && $hdmi && $usb
);

// Conference controls visibility (J21-J24)
export const showConferenceControlsLaptopA = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopA, pinLEDUSBLaptopA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopA && $hdmi && $usb
);

export const showConferenceControlsLaptopB = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopB, pinLEDUSBLaptopB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopB && $hdmi && $usb
);

export const showConferenceControlsPCA = derived(
	[activeLayer, pinLEDHDMIConnectedPCA, pinLEDUSBPCA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCA && $hdmi && $usb
);

export const showConferenceControlsPCB = derived(
	[activeLayer, pinLEDHDMIConnectedPCB, pinLEDUSBPCB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCB && $hdmi && $usb
);

// USB connection prompts (J01-J04)
export const showConnectUsbLaptopA = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopA, pinLEDUSBLaptopA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopA && $hdmi && !$usb
);

export const showConnectUsbLaptopB = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopB, pinLEDUSBLaptopB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerLaptopB && $hdmi && !$usb
);

export const showConnectUsbPCA = derived(
	[activeLayer, pinLEDHDMIConnectedPCA, pinLEDUSBPCA],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCA && $hdmi && !$usb
);

export const showConnectUsbPCB = derived(
	[activeLayer, pinLEDHDMIConnectedPCB, pinLEDUSBPCB],
	([$activeLayer, $hdmi, $usb]) => $activeLayer === kLayerPCB && $hdmi && !$usb
);

// ACPR Bypass visibility (J06-J07)
export const showACPRBypassCombined = derived(
	[activeLayer, pinLEDACPRBypassCombined, pinCallActive, roomState],
	([$activeLayer, $acprBypass, $callActive, $roomState]) => {
		if ($roomState !== 'separated' && ($activeLayer === kLayerPCA || $activeLayer === kLayerPCB)) {
			return !$acprBypass && $callActive;
		}
		return false;
	}
);

export const showACPRBypassSeparated = derived(
	[activeLayer, pinLEDACPRBypassSeparated, pinCallActive, roomState],
	([$activeLayer, $acprBypass, $callActive, $roomState]) => {
		if ($roomState === 'separated' && ($activeLayer === kLayerPCA || $activeLayer === kLayerPCB)) {
			return !$acprBypass && $callActive;
		}
		return false;
	}
);

// ACPR Button visibility (J09-J10)
export const showACPRBtnCombined = derived(
	[showConferenceControlsLaptopA, showConferenceControlsLaptopB, showConferenceControlsPCA, showConferenceControlsPCB, roomState],
	([$laptopA, $laptopB, $pca, $pcb, $roomState]) => {
		if ($roomState === 'separated') return false;
		return $laptopA || $laptopB || $pca || $pcb;
	}
);

export const showACPRBtnSeparated = derived(
	[showConferenceControlsLaptopA, showConferenceControlsLaptopB, showConferenceControlsPCA, showConferenceControlsPCB, roomState],
	([$laptopA, $laptopB, $pca, $pcb, $roomState]) => {
		if ($roomState !== 'separated') return false;
		return $laptopA || $laptopB || $pca || $pcb;
	}
);

// Camera selection visibility (J11-J14)
export const showCameraSelectionLaptopA = derived(
	[activeLayer, roomState],
	([$activeLayer, $roomState]) => $activeLayer === kLayerLaptopA && $roomState !== 'separated'
);

export const showCameraSelectionLaptopB = derived(
	[activeLayer, roomState],
	([$activeLayer, $roomState]) => $activeLayer === kLayerLaptopB && $roomState !== 'separated'
);

export const showCameraSelectionPCA = derived(
	[activeLayer, roomState],
	([$activeLayer, $roomState]) => $activeLayer === kLayerPCA && $roomState !== 'separated'
);

export const showCameraSelectionPCB = derived(
	[activeLayer, roomState],
	([$activeLayer, $roomState]) => $activeLayer === kLayerPCB && $roomState !== 'separated'
);

// Video Privacy visibility (J17-J20)
export const showVideoPrivacySeparatedA = derived(
	[showConferenceControlsPCA, roomState],
	([$pca, $roomState]) => $roomState === 'separated' && $pca
);

export const showVideoPrivacySeparatedB = derived(
	[showConferenceControlsPCB, roomState],
	([$pcb, $roomState]) => $roomState === 'separated' && $pcb
);

export const showVideoPrivacyCombinedA = derived(
	[showConferenceControlsPCA, roomState],
	([$pca, $roomState]) => $roomState !== 'separated' && $pca
);

export const showVideoPrivacyCombinedB = derived(
	[showConferenceControlsPCB, roomState],
	([$pcb, $roomState]) => $roomState !== 'separated' && $pcb
);

// Preset saved visibility (J08)
export const showPresetSaved = derived(
	pinLEDPresetSaved,
	($presetSaved) => $presetSaved
);

// HDMI disconnected visibility
export const showHDMIDisconnectedLaptopA = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopA],
	([$activeLayer, $hdmi]) => $activeLayer === kLayerLaptopA && !$hdmi
);

export const showHDMIDisconnectedLaptopB = derived(
	[activeLayer, pinLEDHDMIConnectedLaptopB],
	([$activeLayer, $hdmi]) => $activeLayer === kLayerLaptopB && !$hdmi
);

export const showHDMIDisconnectedPCA = derived(
	[activeLayer, pinLEDHDMIConnectedPCA],
	([$activeLayer, $hdmi]) => $activeLayer === kLayerPCA && !$hdmi
);

export const showHDMIDisconnectedPCB = derived(
	[activeLayer, pinLEDHDMIConnectedPCB],
	([$activeLayer, $hdmi]) => $activeLayer === kLayerPCB && !$hdmi
);

// Help overlay visibility (I02-I10)
export const showHelpLaptopA = derived(btnOpenHelpLaptopA, ($open) => $open);
export const showHelpLaptopB = derived(btnOpenHelpLaptopB, ($open) => $open);
export const showHelpPCA = derived(btnOpenHelpPCA, ($open) => $open);
export const showHelpPCB = derived(btnOpenHelpPCB, ($open) => $open);
export const showHelpWirelessA = derived(btnOpenHelpWirelessA, ($open) => $open);
export const showHelpWirelessB = derived(btnOpenHelpWirelessB, ($open) => $open);
export const showHelpRouting = derived(btnOpenHelpRouting, ($open) => $open);
export const showHelpStreamMusic = derived(btnOpenHelpStreamMusic, ($open) => $open);

