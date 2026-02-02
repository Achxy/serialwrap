import { useState, useEffect } from "react";
import { check } from "@tauri-apps/plugin-updater";
import { ask } from "@tauri-apps/plugin-dialog";
import { relaunch } from "@tauri-apps/plugin-process";
import { getVersion } from "@tauri-apps/api/app";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Select } from "./ui/select";
import { Label } from "./ui/label";
import { AppSettings } from "../hooks/useStore";

interface SettingsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  settings: AppSettings;
  onSave: (settings: AppSettings) => void;
}

const MAX_RESOLUTION_OPTIONS = [
  { value: "1920x1080", label: "1920x1080 (1080p)" },
  { value: "2560x1440", label: "2560x1440 (1440p)" },
  { value: "3840x2160", label: "3840x2160 (4K)" },
];

const CREDITS_OPTIONS = [
  { value: "2", label: "2 (Lower latency)" },
  { value: "4", label: "4 (Balanced)" },
  { value: "8", label: "8 (Higher throughput)" },
];

export function SettingsDialog({
  open,
  onOpenChange,
  settings,
  onSave,
}: SettingsDialogProps) {
  const [localSettings, setLocalSettings] = useState(settings);
  const [currentVersion, setCurrentVersion] = useState("");
  const [updateStatus, setUpdateStatus] = useState<"idle" | "checking" | "available" | "downloading" | "uptodate" | "error">("idle");
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);

  useEffect(() => {
    setLocalSettings(settings);
  }, [settings]);

  useEffect(() => {
    getVersion().then(setCurrentVersion).catch(console.error);
  }, []);

  const handleCheckForUpdates = async () => {
    setUpdateStatus("checking");
    setUpdateError(null);

    try {
      const update = await check();

      if (update) {
        setUpdateStatus("available");
        setUpdateVersion(update.version);

        const shouldUpdate = await ask(
          `A new version (${update.version}) is available. Would you like to download and install it?`,
          { title: "Update Available", kind: "info" }
        );

        if (shouldUpdate) {
          setUpdateStatus("downloading");

          await update.downloadAndInstall((progress) => {
            // Could show progress here
            console.log("Download progress:", progress);
          });

          const shouldRelaunch = await ask(
            "Update installed successfully. Would you like to restart the app now?",
            { title: "Update Complete", kind: "info" }
          );

          if (shouldRelaunch) {
            await relaunch();
          }
        } else {
          setUpdateStatus("idle");
        }
      } else {
        setUpdateStatus("uptodate");
      }
    } catch (error) {
      console.error("Update check failed:", error);
      setUpdateStatus("error");
      setUpdateError(error instanceof Error ? error.message : String(error));
    }
  };

  const handleSave = () => {
    onSave(localSettings);
    onOpenChange(false);
  };

  const handleCancel = () => {
    setLocalSettings(settings);
    onOpenChange(false);
  };

  const handleMaxResolutionChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const [w, h] = e.target.value.split("x").map(Number);
    setLocalSettings({
      ...localSettings,
      max_width: w,
      max_height: h,
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="max_resolution">Max Resolution</Label>
            <Select
              id="max_resolution"
              options={MAX_RESOLUTION_OPTIONS}
              value={`${localSettings.max_width}x${localSettings.max_height}`}
              onChange={handleMaxResolutionChange}
            />
            <p className="text-xs text-muted-foreground">
              Maximum resolution to accept from Mac
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="max_credits">Flow Control Credits</Label>
            <Select
              id="max_credits"
              options={CREDITS_OPTIONS}
              value={localSettings.max_credits.toString()}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  max_credits: parseInt(e.target.value, 10),
                })
              }
            />
            <p className="text-xs text-muted-foreground">
              Controls buffering vs latency tradeoff
            </p>
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="auto_fullscreen"
              checked={localSettings.auto_fullscreen}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  auto_fullscreen: e.target.checked,
                })
              }
              className="h-4 w-4 rounded border-input"
            />
            <Label htmlFor="auto_fullscreen">Auto-fullscreen on connect</Label>
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="vsync"
              checked={localSettings.vsync}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  vsync: e.target.checked,
                })
              }
              className="h-4 w-4 rounded border-input"
            />
            <Label htmlFor="vsync">Enable VSync</Label>
          </div>

          {/* Updates Section */}
          <div className="border-t pt-4 mt-4">
            <div className="flex items-center justify-between">
              <div>
                <Label>Software Updates</Label>
                <p className="text-xs text-muted-foreground">
                  Current version: {currentVersion || "..."}
                </p>
                {updateStatus === "uptodate" && (
                  <p className="text-xs text-green-600">You're up to date!</p>
                )}
                {updateStatus === "available" && updateVersion && (
                  <p className="text-xs text-blue-600">Version {updateVersion} available</p>
                )}
                {updateStatus === "error" && updateError && (
                  <p className="text-xs text-red-600">{updateError}</p>
                )}
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={handleCheckForUpdates}
                disabled={updateStatus === "checking" || updateStatus === "downloading"}
              >
                {updateStatus === "checking" ? "Checking..." :
                 updateStatus === "downloading" ? "Downloading..." :
                 "Check for Updates"}
              </Button>
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleCancel}>
            Cancel
          </Button>
          <Button onClick={handleSave}>Save</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
