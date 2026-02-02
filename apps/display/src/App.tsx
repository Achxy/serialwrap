import { useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  useStore,
  DisplayStats,
  AppSettings,
  NegotiatedParams,
} from "./hooks/useStore";
import { Button } from "./components/ui/button";
import { Card, CardContent } from "./components/ui/card";
import { formatDuration, formatLatency, formatFps } from "./lib/utils";
import { SettingsDialog } from "./components/SettingsDialog";
import { VideoDisplay } from "./components/VideoDisplay";

function App() {
  const {
    connectionStatus,
    setConnectionStatus,
    params,
    setParams,
    displayStats,
    setDisplayStats,
    displayFrame,
    setDisplayFrame,
    isFullscreen,
    setIsFullscreen,
    settings,
    setSettings,
    settingsOpen,
    setSettingsOpen,
  } = useStore();

  const statsIntervalRef = useRef<number | null>(null);

  // Load settings on mount
  useEffect(() => {
    invoke<AppSettings>("get_settings")
      .then((s) => setSettings(s))
      .catch(console.error);
  }, []);

  // Listen for display frames
  useEffect(() => {
    const unlisten = listen<string>("display_frame", (event) => {
      setDisplayFrame(event.payload);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // Handle keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "F11" || (e.key === "f" && !e.ctrlKey && !e.metaKey)) {
        handleToggleFullscreen();
      } else if (e.key === "Escape" && isFullscreen) {
        handleToggleFullscreen();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isFullscreen]);

  // Poll stats while receiving
  useEffect(() => {
    if (connectionStatus === "receiving") {
      statsIntervalRef.current = window.setInterval(async () => {
        try {
          const stats = await invoke<DisplayStats>("get_display_stats");
          setDisplayStats(stats);
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

  const handleWaitForConnection = useCallback(async () => {
    try {
      setConnectionStatus("waiting");
      const negotiated = await invoke<NegotiatedParams>("wait_for_connection");
      setParams(negotiated);
      setConnectionStatus("connected");

      // Auto-start display
      await invoke("start_display");
      setConnectionStatus("receiving");

      // Auto-fullscreen if enabled
      if (settings.auto_fullscreen) {
        handleToggleFullscreen();
      }
    } catch (e) {
      console.error("Connection failed:", e);
      setConnectionStatus("error");
    }
  }, [settings.auto_fullscreen]);

  const handleDisconnect = useCallback(async () => {
    try {
      await invoke("stop_display");
      await invoke("disconnect");
      setConnectionStatus("disconnected");
      setParams(null);
      setDisplayFrame(null);
    } catch (e) {
      console.error("Disconnect failed:", e);
    }
  }, []);

  const handleToggleFullscreen = useCallback(async () => {
    try {
      const newState = await invoke<boolean>("toggle_fullscreen");
      setIsFullscreen(newState);
    } catch (e) {
      console.error("Fullscreen toggle failed:", e);
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
      case "waiting":
        return "Waiting for Mac...";
      case "connecting":
        return "Connecting...";
      case "connected":
        return "Connected";
      case "receiving":
        return "Receiving from Mac";
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
      case "receiving":
        return "receiving";
      case "waiting":
        return "waiting";
      default:
        return "disconnected";
    }
  };

  const isReceiving = connectionStatus === "receiving";
  const isConnected =
    connectionStatus === "connected" || connectionStatus === "receiving";
  const isWaiting = connectionStatus === "waiting";

  // Fullscreen mode - just show the video
  if (isFullscreen) {
    return (
      <div className="fullscreen-mode">
        <VideoDisplay
          frame={displayFrame}
          params={params}
          isReceiving={isReceiving}
        />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background p-4 flex flex-col gap-4">
      {/* Video Display Area */}
      <Card className="flex-1">
        <CardContent className="p-4 h-full">
          <VideoDisplay
            frame={displayFrame}
            params={params}
            isReceiving={isReceiving}
          />
        </CardContent>
      </Card>

      {/* Status Bar */}
      <div className="flex items-center gap-2 text-sm">
        <span className={`status-dot ${getStatusClass()}`} />
        <span>Status: {getStatusText()}</span>
        {params && (
          <span className="text-muted-foreground ml-4">
            Resolution: {params.width}x{params.height} @ {params.fps}fps
          </span>
        )}
      </div>

      {/* Stats */}
      {isReceiving && (
        <div className="text-sm text-muted-foreground flex items-center gap-4 justify-center">
          <span>{formatFps(displayStats.fps)}</span>
          <span>|</span>
          <span>Decode: {formatLatency(displayStats.decode_time_ms)}</span>
          <span>|</span>
          <span>Latency: {formatLatency(displayStats.latency_ms)}</span>
          <span>|</span>
          <span>{formatDuration(displayStats.elapsed_seconds)}</span>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex items-center justify-center gap-4">
        {!isConnected && !isWaiting ? (
          <Button onClick={handleWaitForConnection}>Wait for Connection</Button>
        ) : isWaiting ? (
          <Button variant="outline" disabled>
            Waiting...
          </Button>
        ) : (
          <>
            <Button onClick={handleToggleFullscreen}>
              Fullscreen (F11)
            </Button>
            <Button variant="destructive" onClick={handleDisconnect}>
              Disconnect
            </Button>
          </>
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
