#!/bin/bash
# create_shortcut.sh — creates meso360.app on the Desktop (macOS).
# Run once:  bash create_shortcut.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORM_DIR="$(dirname "$REPO_DIR")/storm"
APP="$HOME/Desktop/meso360.app"

echo "Creating $APP ..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# ── Icon ─────────────────────────────────────────────────────────────────────
if [ -f "$STORM_DIR/storm.icns" ]; then
    cp "$STORM_DIR/storm.icns" "$APP/Contents/Resources/meso360.icns"
    ICON_KEY='<key>CFBundleIconFile</key><string>meso360</string>'
    echo "  icon : $STORM_DIR/storm.icns"
else
    ICON_KEY=""
    echo "  note : storm.icns not found at $STORM_DIR — no custom icon"
fi

# ── Info.plist ────────────────────────────────────────────────────────────────
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key>   <string>meso360</string>
    <key>CFBundleIconFile</key>     <string>meso360</string>
    <key>CFBundleIdentifier</key>   <string>science.bliss.meso360</string>
    <key>CFBundleName</key>         <string>meso360</string>
    <key>CFBundlePackageType</key>  <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
</dict></plist>
PLIST

# ── App executable ────────────────────────────────────────────────────────────
# Write with a placeholder, then inject the repo path via sed.
cat > "$APP/Contents/MacOS/meso360" << 'EXEC'
#!/bin/bash
REPO="__REPO__"

CONDA=""
for dir in \
    "$HOME/miniforge3" \
    "$HOME/anaconda3" \
    "$HOME/miniconda3" \
    "$HOME/opt/miniconda3" \
    "/opt/homebrew/Caskroom/miniforge/base" \
    "/usr/local/Caskroom/miniforge/base" \
    "/opt/conda"
do
    if [ -f "$dir/bin/conda" ]; then
        CONDA="$dir/bin/conda"
        break
    fi
done

if [ -z "$CONDA" ] && command -v conda &>/dev/null; then
    CONDA="$(command -v conda)"
fi

if [ -z "$CONDA" ]; then
    osascript -e 'display alert "meso360" message "conda not found.\n\nInstall Miniforge and create the meso360 environment:\n  conda env create -f environment.yml"'
    exit 1
fi

"$CONDA" run --no-capture-output -n meso360 python "$REPO/launch_meso360.pyw"
EXEC

# Inject the actual repo path (sed -i '' is BSD/macOS sed)
sed -i '' "s|__REPO__|$REPO_DIR|g" "$APP/Contents/MacOS/meso360"
chmod +x "$APP/Contents/MacOS/meso360"

# Tell Launch Services to pick up the new bundle / icon
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "  repo : $REPO_DIR"
echo "Done  : $APP"
echo ""
echo "If the icon doesn't appear, log out and back in, or run:"
echo "  killall Finder"
