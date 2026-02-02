import { useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useStore, StreamStats, AppSettings, DebugInfo } from "./hooks/useStore";
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
    debugOpen,
    setDebugOpen,
    lastError,
    setLastError,
    debugInfo,
    setDebugInfo,
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
      setLastError(null);
      await invoke("connect_transport");
      setConnectionStatus("connected");
    } catch (e) {
      console.error("Connection failed:", e);
      const errorMsg = typeof e === "string" ? e : String(e);
      setLastError(errorMsg);
      setConnectionStatus("error");
      // Fetch debug info for troubleshooting
      try {
        const info = await invoke<DebugInfo>("get_debug_info");
        setDebugInfo(info);
        setDebugOpen(true);
      } catch {
        // Ignore debug info fetch errors
      }
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
        {connectionStatus === "error" && lastError && (
          <button
            className="text-destructive underline ml-2"
            onClick={() => setDebugOpen(true)}
          >
            (click for details)
          </button>
        )}
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
        <Button variant="ghost" onClick={async () => {
          try {
            const info = await invoke<DebugInfo>("get_debug_info");
            setDebugInfo(info);
          } catch {
            // Ignore errors
          }
          setDebugOpen(true);
        }}>
          Debug
        </Button>
      </div>

      {/* Settings Dialog */}
      <SettingsDialog
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        settings={settings}
        onSave={handleSaveSettings}
      />

      {/* Debug Panel */}
      {debugOpen && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-[600px] max-h-[80vh] overflow-auto">
            <CardContent className="p-6">
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-lg font-semibold">Debug Information</h2>
                <Button variant="ghost" size="sm" onClick={() => setDebugOpen(false)}>
                  ✕
                </Button>
              </div>

              {lastError && (
                <div className="mb-4 p-3 bg-destructive/10 border border-destructive/20 rounded-md">
                  <h3 className="font-medium text-destructive mb-2">Error Details</h3>
                  <pre className="text-sm whitespace-pre-wrap font-mono">{lastError}</pre>
                </div>
              )}

              {debugInfo && (
                <>
                  <div className="mb-4">
                    <h3 className="font-medium mb-2">Supported USB Devices</h3>
                    <div className="text-sm text-muted-foreground space-y-1">
                      {debugInfo.supported_devices.map((d, i) => (
                        <div key={i} className="font-mono">
                          {d.name} ({d.vendor_id.toString(16).padStart(4, "0").toUpperCase()}:
                          {d.product_id.toString(16).padStart(4, "0").toUpperCase()})
                        </div>
                      ))}
                    </div>
                  </div>

                  <div className="mb-4">
                    <h3 className="font-medium mb-2">Connected USB Devices</h3>
                    {debugInfo.connected_devices.length === 0 ? (
                      <p className="text-sm text-muted-foreground">No USB devices detected</p>
                    ) : (
                      <div className="text-sm text-muted-foreground space-y-1">
                        {debugInfo.connected_devices.map((d, i) => (
                          <div key={i} className="font-mono">
                            {d.name} ({d.vendor_id.toString(16).padStart(4, "0").toUpperCase()}:
                            {d.product_id.toString(16).padStart(4, "0").toUpperCase()})
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </>
              )}

              <div className="flex justify-end gap-2 mt-4">
                <Button variant="outline" onClick={() => setDebugOpen(false)}>
                  Close
                </Button>
                <Button onClick={handleConnect}>
                  Retry Connection
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}

export default App;
