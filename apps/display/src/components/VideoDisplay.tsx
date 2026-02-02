import { useEffect, useRef } from "react";
import { cn } from "../lib/utils";
import { NegotiatedParams } from "../hooks/useStore";

interface VideoDisplayProps {
  frame: string | null;
  params: NegotiatedParams | null;
  isReceiving: boolean;
}

export function VideoDisplay({
  frame,
  params,
  isReceiving,
}: VideoDisplayProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!frame || !canvasRef.current) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Decode base64 image and draw to canvas
    const img = new Image();
    img.onload = () => {
      // Clear canvas with black
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      // Calculate aspect-ratio preserving dimensions
      const canvasAspect = canvas.width / canvas.height;
      const imgAspect = img.width / img.height;

      let drawWidth: number;
      let drawHeight: number;
      let offsetX: number;
      let offsetY: number;

      if (imgAspect > canvasAspect) {
        // Image is wider - fit to width
        drawWidth = canvas.width;
        drawHeight = canvas.width / imgAspect;
        offsetX = 0;
        offsetY = (canvas.height - drawHeight) / 2;
      } else {
        // Image is taller - fit to height
        drawHeight = canvas.height;
        drawWidth = canvas.height * imgAspect;
        offsetX = (canvas.width - drawWidth) / 2;
        offsetY = 0;
      }

      ctx.drawImage(img, offsetX, offsetY, drawWidth, drawHeight);
    };
    img.src = `data:image/jpeg;base64,${frame}`;
  }, [frame]);

  // Resize canvas to fit container
  useEffect(() => {
    const resizeCanvas = () => {
      if (!canvasRef.current || !containerRef.current) return;

      const container = containerRef.current;
      const canvas = canvasRef.current;

      canvas.width = container.clientWidth;
      canvas.height = container.clientHeight;
    };

    resizeCanvas();
    window.addEventListener("resize", resizeCanvas);
    return () => window.removeEventListener("resize", resizeCanvas);
  }, []);

  return (
    <div
      ref={containerRef}
      className={cn(
        "display-container w-full h-full flex items-center justify-center",
        !isReceiving && "bg-muted"
      )}
    >
      {isReceiving ? (
        <canvas
          ref={canvasRef}
          className="w-full h-full"
          style={{ objectFit: "contain" }}
        />
      ) : (
        <div className="text-center text-muted-foreground">
          <div className="text-6xl mb-4">&#128421;</div>
          <p className="text-lg">Waiting for Mac...</p>
          {params ? (
            <p className="text-sm mt-2">
              {params.width}x{params.height} @ {params.fps}fps
            </p>
          ) : (
            <p className="text-sm mt-2">
              Connect your Mac via USB to begin
            </p>
          )}
        </div>
      )}
    </div>
  );
}
