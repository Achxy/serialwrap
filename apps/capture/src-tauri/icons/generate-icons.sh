#!/bin/bash
# Generate placeholder icons for SerialWarp Capture
# In production, replace these with actual icon files

# Create a simple placeholder using ImageMagick if available
if command -v convert &> /dev/null; then
    # 32x32
    convert -size 32x32 xc:'#3B82F6' -fill white -gravity center \
        -pointsize 20 -annotate 0 'S' 32x32.png

    # 128x128
    convert -size 128x128 xc:'#3B82F6' -fill white -gravity center \
        -pointsize 80 -annotate 0 'S' 128x128.png

    # 128x128@2x
    convert -size 256x256 xc:'#3B82F6' -fill white -gravity center \
        -pointsize 160 -annotate 0 'S' 128x128@2x.png

    # icon.icns (macOS app icon)
    mkdir -p icon.iconset
    for size in 16 32 64 128 256 512; do
        convert -size ${size}x${size} xc:'#3B82F6' -fill white -gravity center \
            -pointsize $((size/2)) -annotate 0 'S' icon.iconset/icon_${size}x${size}.png
        convert -size $((size*2))x$((size*2)) xc:'#3B82F6' -fill white -gravity center \
            -pointsize ${size} -annotate 0 'S' icon.iconset/icon_${size}x${size}@2x.png
    done
    iconutil -c icns icon.iconset -o icon.icns
    rm -rf icon.iconset

    echo "Icons generated successfully!"
else
    echo "ImageMagick not found. Creating minimal placeholder icons..."
    # Create minimal 1x1 placeholder PNGs (will show as blank)
    printf '\x89PNG\r\n\x1a\n' > 32x32.png
    printf '\x89PNG\r\n\x1a\n' > 128x128.png
    printf '\x89PNG\r\n\x1a\n' > 128x128@2x.png
    echo "Placeholder icons created. Replace with actual icons before release."
fi
