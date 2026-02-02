import { create } from "zustand";

export type ConnectionStatus =
  | "disconnected"
  | "connecting"
  | "connected"
  | "streaming"
  | "error";

export interface DisplayInfo {
  id: number;
  name: string;
  width: number;
  height: number;
  is_main: boolean;
}

export interface StreamConfig {
  width: number;
  height: number;
  fps: number;
  bitrate_mbps: number;
  hidpi: boolean;
}

export interface StreamStats {
  fps: number;
  bitrate_bps: number;
  frames_captured: number;
  frames_encoded: number;
  frames_sent: number;
  frames_dropped: number;
  elapsed_seconds: number;
}

export interface AppSettings {
  default_resolution: string;
  default_fps: number;
  default_bitrate_mbps: number;
  auto_connect: boolean;
  preview_enabled: boolean;
  preview_quality: number;
}

export interface UsbDeviceInfo {
  name: string;
  vendor_id: number;
  product_id: number;
}

export interface DebugInfo {
  connected_devices: UsbDeviceInfo[];
  supported_devices: UsbDeviceInfo[];
  last_error: string | null;
}

interface AppStore {
  // Connection state
  connectionStatus: ConnectionStatus;
  setConnectionStatus: (status: ConnectionStatus) => void;

  // Virtual display
  virtualDisplayId: number | null;
  setVirtualDisplayId: (id: number | null) => void;

  // Stream config
  streamConfig: StreamConfig;
  setStreamConfig: (config: Partial<StreamConfig>) => void;

  // Stats
  streamStats: StreamStats;
  setStreamStats: (stats: StreamStats) => void;

  // Preview frame
  previewFrame: string | null;
  setPreviewFrame: (frame: string | null) => void;

  // Settings
  settings: AppSettings;
  setSettings: (settings: AppSettings) => void;

  // UI state
  settingsOpen: boolean;
  setSettingsOpen: (open: boolean) => void;

  // Debug state
  debugOpen: boolean;
  setDebugOpen: (open: boolean) => void;
  lastError: string | null;
  setLastError: (error: string | null) => void;
  debugInfo: DebugInfo | null;
  setDebugInfo: (info: DebugInfo | null) => void;
}

export const useStore = create<AppStore>((set) => ({
  // Connection state
  connectionStatus: "disconnected",
  setConnectionStatus: (status) => set({ connectionStatus: status }),

  // Virtual display
  virtualDisplayId: null,
  setVirtualDisplayId: (id) => set({ virtualDisplayId: id }),

  // Stream config
  streamConfig: {
    width: 1920,
    height: 1080,
    fps: 60,
    bitrate_mbps: 20,
    hidpi: false,
  },
  setStreamConfig: (config) =>
    set((state) => ({
      streamConfig: { ...state.streamConfig, ...config },
    })),

  // Stats
  streamStats: {
    fps: 0,
    bitrate_bps: 0,
    frames_captured: 0,
    frames_encoded: 0,
    frames_sent: 0,
    frames_dropped: 0,
    elapsed_seconds: 0,
  },
  setStreamStats: (stats) => set({ streamStats: stats }),

  // Preview frame
  previewFrame: null,
  setPreviewFrame: (frame) => set({ previewFrame: frame }),

  // Settings
  settings: {
    default_resolution: "1920x1080",
    default_fps: 60,
    default_bitrate_mbps: 20,
    auto_connect: false,
    preview_enabled: true,
    preview_quality: 50,
  },
  setSettings: (settings) => set({ settings }),

  // UI state
  settingsOpen: false,
  setSettingsOpen: (open) => set({ settingsOpen: open }),

  // Debug state
  debugOpen: false,
  setDebugOpen: (open) => set({ debugOpen: open }),
  lastError: null,
  setLastError: (error) => set({ lastError: error }),
  debugInfo: null,
  setDebugInfo: (info) => set({ debugInfo: info }),
}));
