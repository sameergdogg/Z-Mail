#!/bin/bash

# iOS App Icon Generator Script
# Usage: ./generate_app_icons.sh input_image.png

if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_image.png>"
    echo "Please provide the path to your source PNG image"
    exit 1
fi

INPUT_IMAGE="$1"
OUTPUT_DIR="AppIcons"

# Check if input file exists
if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: Input image '$INPUT_IMAGE' not found"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Generating iOS app icons from $INPUT_IMAGE..."

# Required iOS app icon sizes
declare -a sizes=(
    "20:Icon-App-20x20@1x.png"
    "40:Icon-App-20x20@2x.png" 
    "60:Icon-App-20x20@3x.png"
    "29:Icon-App-29x29@1x.png"
    "58:Icon-App-29x29@2x.png"
    "87:Icon-App-29x29@3x.png"
    "40:Icon-App-40x40@1x.png"
    "80:Icon-App-40x40@2x.png"
    "120:Icon-App-40x40@3x.png"
    "120:Icon-App-60x60@2x.png"
    "180:Icon-App-60x60@3x.png"
    "76:Icon-App-76x76@1x.png"
    "152:Icon-App-76x76@2x.png"
    "167:Icon-App-83.5x83.5@2x.png"
    "1024:Icon-App-1024x1024@1x.png"
)

# Generate icons using sips (built into macOS)
for size_info in "${sizes[@]}"; do
    IFS=':' read -r size filename <<< "$size_info"
    echo "Generating ${size}x${size} -> $filename"
    sips -z "$size" "$size" "$INPUT_IMAGE" --out "$OUTPUT_DIR/$filename" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Created $filename"
    else
        echo "❌ Failed to create $filename"
    fi
done

echo ""
echo "🎉 Icon generation complete!"
echo "📁 Icons saved to: $OUTPUT_DIR/"
echo ""
echo "Next steps:"
echo "1. Open Xcode and navigate to Assets.xcassets"
echo "2. Select AppIcon"  
echo "3. Drag the generated icons to their corresponding slots"
echo "4. The naming convention matches Xcode's requirements"