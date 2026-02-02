import { useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useStore, ConnectionStatus, StreamStats, AppSettings } from "./hooks/useStore";
import { Button } from "./components/ui/button";
import { Select } from "./components/ui/select";
import { Card, CardContent } from "./components/ui/card";
import { Label } from "./components/ui/label";
import { formatDuration, formatBitrate, formatFps } from "./lib/utils";
import { SettingsDialog } from "./components/SettingsDialog";
import { PreviewCanvas } from "./components/PreviewCanvas";

const RESOLUTION_OPTIONS = [
  { value: "1920x1080", label: "1920x1080 (1080p)" },
  { value: "2560x1440", label: "2560x1440 (1440p)" },
  { value: "3840x2160", label: "3840x2160 (4K)" },
  { value: "1280x720", label: "1280x720 (720p)" },
];

const FPS_OPTIONS = [
  { value: "60", label: "60 fps" },
  { value: "30", label: "30 fps" },
  { value: "120", label: "120 fps" },
];

const BITRATE_OPTIONS = [
  { value: "10", label: "10 Mbps" },
  { value: "20", label: "20 Mbps" },
  { value: "30", label: "30 Mbps" },
  { value: "50", label: "50 Mbps" },
];

function App() {
  const {
    connectionStatus,
    setConnectionStatus,
    virtualDisplayId,
    setVirtualDisplayId,
    streamConfig,
    setStreamConfig,
    streamStats,
    setStreamStats,
    previewFrame,
    setPreviewFrame,
    settings,
    setSettings,
    settingsOpen,
    setSettingsOpen,
  } = useStore();

  const statsIntervalRef = useRef<number | null>(null);

  // Load settings on mount
  useEffect(() => {
    invoke<AppSettings>("get_settings")
      .then((s) => {
        setSettings(s);
        // Apply default config from settings
        const [w, h] = s.default_resolution.split("x").map(Number);
        setStreamConfig({
          width: w,
          height: h,
          fps: s.default_fps,
          bitrate_mbps: s.default_bitrate_mbps,
        });
      })
      .catch(console.error);
  }, []);

  // Listen for preview frames
  useEffect(() => {
    const unlisten = listen<string>("preview_frame", (event) => {
      setPreviewFrame(event.payload);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // Poll stats while streaming
  useEffect(() => {
    if (connectionStatus === "streaming") {
      statsIntervalRef.current = window.setInterval(async () => {
        try {
          const stats = await invoke<StreamStats>("get_stream_stats");
          setStreamStats(stats);
        } catch (e) {
          console.error("Failed to get stats:", e);
        }
      }, 500);
    } else {
      if (statsIntervalRef.current) {
        clearInterval(statsIntervalRef.current);
        statsIntervalRef.current = null;
      }
    }

    return () => {
      if (statsIntervalRef.current) {
        clearInterval(statsIntervalRef.current);
      }
    };
  }, [connectionStatus]);

  const handleResolutionChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      const [w, h] = e.target.value.split("x").map(Number);
      setStreamConfig({ width: w, height: h });
    },
    []
  );

  const handleFpsChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      setStreamConfig({ fps: parseInt(e.target.value, 10) });
    },
    []
  );

  const handleBitrateChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      setStreamConfig({ bitrate_mbps: parseInt(e.target.value, 10) });
    },
    []
  );

  const handleConnect = useCallback(async () => {
    try {
      setConnectionStatus("connecting");
      await invoke("connect_transport");
      setConnectionStatus("connected");
    } catch (e) {
      console.error("Connection failed:", e);
      setConnectionStatus("error");
    }
  }, []);

  const handleDisconnect = useCallback(async () => {
    try {
      await invoke("disconnect_transport");
      setConnectionStatus("disconnected");
    } catch (e) {
      console.error("Disconnect failed:", e);
    }
  }, []);

  const handleCreateVirtualDisplay = useCallback(async () => {
    try {
      const id = await invoke<number>("create_virtual_display", {
        config: streamConfig,
      });
      setVirtualDisplayId(id);
    } catch (e) {
      console.error("Failed to create virtual display:", e);
    }
  }, [streamConfig]);

  const handleStartStreaming = useCallback(async () => {
    try {
      // Create virtual display if not already created
      if (!virtualDisplayId) {
        const id = await invoke<number>("create_virtual_display", {
          config: streamConfig,
        });
        setVirtualDisplayId(id);
      }

      await invoke("start_streaming", { config: streamConfig });
      setConnectionStatus("streaming");
    } catch (e) {
      console.error("Failed to start streaming:", e);
      setConnectionStatus("error");
    }
  }, [streamConfig, virtualDisplayId]);

  const handleStopStreaming = useCallback(async () => {
    try {
      await invoke("stop_streaming");
      setConnectionStatus("connected");
      setPreviewFrame(null);
    } catch (e) {
      console.error("Failed to stop streaming:", e);
    }
  }, []);

  const handleSaveSettings = useCallback(async (newSettings: AppSettings) => {
    try {
      await invoke("save_settings", { settings: newSettings });
      setSettings(newSettings);
    } catch (e) {
      console.error("Failed to save settings:", e);
    }
  }, []);

  const getStatusText = () => {
    switch (connectionStatus) {
      case "disconnected":
        return "Disconnected";
      case "connecting":
        return "Connecting...";
      case "connected":
        return "Connected to PC";
      case "streaming":
        return "Streaming";
      case "error":
        return "Connection Error";
      default:
        return "Unknown";
    }
  };

  const getStatusClass = () => {
    switch (connectionStatus) {
      case "connected":
        return "connected";
      case "streaming":
        return "streaming";
      default:
        return "disconnected";
    }
  };

  const isStreaming = connectionStatus === "streaming";
  const isConnected =
    connectionStatus === "connected" || connectionStatus === "streaming";

  return (
    <div className="min-h-screen bg-background p-4 flex flex-col gap-4">
      {/* Preview Area */}
      <Card className="flex-1">
        <CardContent className="p-4 h-full">
          <PreviewCanvas
            frame={previewFrame}
            width={streamConfig.width}
            height={streamConfig.height}
            isStreaming={isStreaming}
          />
        </CardContent>
      </Card>

      {/* Status Bar */}
      <div className="flex items-center gap-2 text-sm">
        <span className={`status-dot ${getStatusClass()}`} />
        <span>Status: {getStatusText()}</span>
        {virtualDisplayId && (
          <span className="text-muted-foreground ml-4">
            Virtual Display ID: {virtualDisplayId}
          </span>
        )}
      </div>

      {/* Controls */}
      <div className="grid grid-cols-3 gap-4">
        <div className="space-y-2">
          <Label htmlFor="resolution">Resolution</Label>
          <Select
            id="resolution"
            options={RESOLUTION_OPTIONS}
            value={`${streamConfig.width}x${streamConfig.height}`}
            onChange={handleResolutionChange}
            disabled={isStreaming}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="fps">Frame Rate</Label>
          <Select
            id="fps"
            options={FPS_OPTIONS}
            value={streamConfig.fps.toString()}
            onChange={handleFpsChange}
            disabled={isStreaming}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="bitrate">Bitrate</Label>
          <Select
            id="bitrate"
            options={BITRATE_OPTIONS}
            value={streamConfig.bitrate_mbps.toString()}
            onChange={handleBitrateChange}
            disabled={isStreaming}
          />
        </div>
      </div>

      {/* Stats */}
      {isStreaming && (
        <div className="text-sm text-muted-foreground flex items-center gap-4 justify-center">
          <span>{formatFps(streamStats.fps)}</span>
          <span>|</span>
          <span>{formatBitrate(streamStats.bitrate_bps)}</span>
          <span>|</span>
          <span>{streamStats.frames_dropped} dropped</span>
          <span>|</span>
          <span>{formatDuration(streamStats.elapsed_seconds)}</span>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex items-center justify-center gap-4">
        {!isConnected ? (
          <Button onClick={handleConnect} disabled={connectionStatus === "connecting"}>
            Connect to PC
          </Button>
        ) : !isStreaming ? (
          <>
            <Button onClick={handleStartStreaming}>Start Streaming</Button>
            <Button variant="outline" onClick={handleDisconnect}>
              Disconnect
            </Button>
          </>
        ) : (
          <Button variant="destructive" onClick={handleStopStreaming}>
            Stop Streaming
          </Button>
        )}
        <Button variant="ghost" onClick={() => setSettingsOpen(true)}>
          Settings
        </Button>
      </div>

      {/* Settings Dialog */}
      <SettingsDialog
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        settings={settings}
        onSave={handleSaveSettings}
      />
    </div>
  );
}

export default App;
