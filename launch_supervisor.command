#!/bin/bash
# Double-clickable launcher for macOS (and Linux with a .desktop entry).
# The file must live inside the meso360 repo directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME=meso360

# Search common conda install locations
for conda_base in \
    "$HOME/miniforge3" \
    "$HOME/anaconda3" \
    "$HOME/miniconda3" \
    "/opt/homebrew/Caskroom/miniforge/base" \
    "/opt/miniconda3" \
    "/opt/anaconda3"
do
    if [ -f "$conda_base/etc/profile.d/conda.sh" ]; then
        source "$conda_base/etc/profile.d/conda.sh"
        conda activate "$ENV_NAME"
        python "$SCRIPT_DIR/supervisor.py"
        exit $?
    fi
done

echo "ERROR: Could not find a conda installation in common locations."
echo "Please edit this script and set conda_base manually."
read -rp "Press enter to exit..."
exit 1
