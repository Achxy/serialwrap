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

const QUALITY_OPTIONS = [
  { value: "30", label: "Low (30%)" },
  { value: "50", label: "Medium (50%)" },
  { value: "70", label: "High (70%)" },
  { value: "90", label: "Best (90%)" },
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="default_resolution">Default Resolution</Label>
            <Select
              id="default_resolution"
              options={RESOLUTION_OPTIONS}
              value={localSettings.default_resolution}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  default_resolution: e.target.value,
                })
              }
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="default_fps">Default Frame Rate</Label>
            <Select
              id="default_fps"
              options={FPS_OPTIONS}
              value={localSettings.default_fps.toString()}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  default_fps: parseInt(e.target.value, 10),
                })
              }
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="default_bitrate">Default Bitrate</Label>
            <Select
              id="default_bitrate"
              options={BITRATE_OPTIONS}
              value={localSettings.default_bitrate_mbps.toString()}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  default_bitrate_mbps: parseInt(e.target.value, 10),
                })
              }
            />
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="auto_connect"
              checked={localSettings.auto_connect}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  auto_connect: e.target.checked,
                })
              }
              className="h-4 w-4 rounded border-input"
            />
            <Label htmlFor="auto_connect">Auto-connect on startup</Label>
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="preview_enabled"
              checked={localSettings.preview_enabled}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  preview_enabled: e.target.checked,
                })
              }
              className="h-4 w-4 rounded border-input"
            />
            <Label htmlFor="preview_enabled">Enable live preview</Label>
          </div>

          <div className="space-y-2">
            <Label htmlFor="preview_quality">Preview Quality</Label>
            <Select
              id="preview_quality"
              options={QUALITY_OPTIONS}
              value={localSettings.preview_quality.toString()}
              onChange={(e) =>
                setLocalSettings({
                  ...localSettings,
                  preview_quality: parseInt(e.target.value, 10),
                })
              }
              disabled={!localSettings.preview_enabled}
            />
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
