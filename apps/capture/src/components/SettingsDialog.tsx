import { useState, useEffect } from "react";
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

  useEffect(() => {
    setLocalSettings(settings);
  }, [settings]);

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
