#!/bin/bash
# Generate placeholder icons for SerialWarp Display
# In production, replace these with actual icon files

if command -v convert &> /dev/null; then
    # 32x32
    convert -size 32x32 xc:'#10B981' -fill white -gravity center \
        -pointsize 20 -annotate 0 'D' 32x32.png

    # 128x128
    convert -size 128x128 xc:'#10B981' -fill white -gravity center \
        -pointsize 80 -annotate 0 'D' 128x128.png

    # 128x128@2x
    convert -size 256x256 xc:'#10B981' -fill white -gravity center \
        -pointsize 160 -annotate 0 'D' 128x128@2x.png

    # icon.ico (Windows app icon) - create multi-resolution ICO
    for size in 16 32 48 64 128 256; do
        convert -size ${size}x${size} xc:'#10B981' -fill white -gravity center \
            -pointsize $((size/2)) -annotate 0 'D' icon_${size}.png
    done
    convert icon_16.png icon_32.png icon_48.png icon_64.png icon_128.png icon_256.png icon.ico
    rm icon_*.png

    echo "Icons generated successfully!"
else
    echo "ImageMagick not found. Creating minimal placeholder icons..."
    printf '\x89PNG\r\n\x1a\n' > 32x32.png
    printf '\x89PNG\r\n\x1a\n' > 128x128.png
    printf '\x89PNG\r\n\x1a\n' > 128x128@2x.png
    echo "Placeholder icons created. Replace with actual icons before release."
fi
