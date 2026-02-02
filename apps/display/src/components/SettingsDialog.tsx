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
