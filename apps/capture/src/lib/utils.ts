import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDuration(seconds: number): string {
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  return `${hrs}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
}

export function formatBitrate(bps: number): string {
  if (bps >= 1_000_000) {
    return `${(bps / 1_000_000).toFixed(1)} Mbps`;
  } else if (bps >= 1000) {
    return `${(bps / 1000).toFixed(1)} Kbps`;
  }
  return `${bps} bps`;
}

export function formatFps(fps: number): string {
  return `${fps.toFixed(1)} fps`;
}
