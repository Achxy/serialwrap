import { create } from "zustand";

export type ConnectionStatus =
  | "disconnected"
  | "waiting"
  | "connecting"
  | "connected"
  | "receiving"
  | "error";

export interface NegotiatedParams {
  width: number;
  height: number;
  fps: number;
  bitrate_bps: number;
}

export interface DisplayStats {
  fps: number;
  frames_received: number;
  frames_decoded: number;
  frames_displayed: number;
  frames_dropped: number;
  decode_time_ms: number;
  latency_ms: number;
  elapsed_seconds: number;
}

export interface AppSettings {
  auto_fullscreen: boolean;
  vsync: boolean;
  max_width: number;
  max_height: number;
  max_credits: number;
}

interface AppStore {
  // Connection state
  connectionStatus: ConnectionStatus;
  setConnectionStatus: (status: ConnectionStatus) => void;

  // Negotiated parameters
  params: NegotiatedParams | null;
  setParams: (params: NegotiatedParams | null) => void;

  // Stats
  displayStats: DisplayStats;
  setDisplayStats: (stats: DisplayStats) => void;

  // Display frame (base64 encoded)
  displayFrame: string | null;
  setDisplayFrame: (frame: string | null) => void;

  // Fullscreen
  isFullscreen: boolean;
  setIsFullscreen: (fs: boolean) => void;

  // Settings
  settings: AppSettings;
  setSettings: (settings: AppSettings) => void;

  // UI state
  settingsOpen: boolean;
  setSettingsOpen: (open: boolean) => void;
}

export const useStore = create<AppStore>((set) => ({
  // Connection state
  connectionStatus: "disconnected",
  setConnectionStatus: (status) => set({ connectionStatus: status }),

  // Negotiated parameters
  params: null,
  setParams: (params) => set({ params }),

  // Stats
  displayStats: {
    fps: 0,
    frames_received: 0,
    frames_decoded: 0,
    frames_displayed: 0,
    frames_dropped: 0,
    decode_time_ms: 0,
    latency_ms: 0,
    elapsed_seconds: 0,
  },
  setDisplayStats: (stats) => set({ displayStats: stats }),

  // Display frame
  displayFrame: null,
  setDisplayFrame: (frame) => set({ displayFrame: frame }),

  // Fullscreen
  isFullscreen: false,
  setIsFullscreen: (fs) => set({ isFullscreen: fs }),

  // Settings
  settings: {
    auto_fullscreen: false,
    vsync: true,
    max_width: 1920,
    max_height: 1080,
    max_credits: 4,
  },
  setSettings: (settings) => set({ settings }),

  // UI state
  settingsOpen: false,
  setSettingsOpen: (open) => set({ settingsOpen: open }),
}));
