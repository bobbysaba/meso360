#!/bin/bash
# meso360 launch dialog — macOS double-click launcher.
# Opens the tkinter launch dialog using the meso360 conda environment.
# Make executable once:  chmod +x launch_meso360.command

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Search common conda install locations
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

# Fall back to whatever is on PATH
if [ -z "$CONDA" ] && command -v conda &>/dev/null; then
    CONDA="$(command -v conda)"
fi

if [ -z "$CONDA" ]; then
    osascript -e 'display alert "meso360" message "conda not found.\n\nInstall Miniforge and create the meso360 environment:\n  conda env create -f environment.yml"'
    exit 1
fi

"$CONDA" run --no-capture-output -n meso360 python "$REPO_DIR/launch_meso360.pyw"
