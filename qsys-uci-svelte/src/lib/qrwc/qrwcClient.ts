import { writable } from 'svelte/store';
import { Qrwc } from '@q-sys/qrwc';

export const qrwcReady = writable<boolean>(false);
export const qrwcError = writable<string | null>(null);

let qrwcInstance: any = null;
let socket: WebSocket | null = null;

export async function initQrwc(socketUrl: string): Promise<any> {
	try {
		// Close existing connection if any
		if (socket) {
			socket.close();
		}

		// Create WebSocket connection
		socket = new WebSocket(socketUrl);

		// Wait for connection to open
		await new Promise<void>((resolve, reject) => {
			const timeout = setTimeout(() => {
				reject(new Error('WebSocket connection timeout'));
			}, 10000);

			socket!.onopen = () => {
				clearTimeout(timeout);
				resolve();
			};

			socket!.onerror = (error) => {
				clearTimeout(timeout);
				reject(error);
			};
		});

		// Create QRWC instance
		qrwcInstance = await Qrwc.createQrwc({
			socket,
			pollingInterval: 250
		});

		qrwcReady.set(true);
		qrwcError.set(null);

		// Handle connection errors
		socket.onerror = (error) => {
			qrwcError.set('WebSocket error: ' + error);
			qrwcReady.set(false);
		};

		socket.onclose = () => {
			qrwcReady.set(false);
			qrwcError.set('WebSocket connection closed');
		};

		return qrwcInstance;
	} catch (error: any) {
		qrwcError.set(error.message || 'Failed to initialize QRWC');
		qrwcReady.set(false);
		throw error;
	}
}

export function getQrwc(): any {
	return qrwcInstance;
}

export function disconnectQrwc(): void {
	if (socket) {
		socket.close();
		socket = null;
	}
	qrwcInstance = null;
	qrwcReady.set(false);
}

