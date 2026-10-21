#!/usr/bin/env bash
set -e

echo "=== dynaQ Virtual Audio Driver Installer ==="

DRIVER_DIR="/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver"

echo "Checking HAL directory..."
if [ ! -d "/Library/Audio/Plug-Ins/HAL" ]; then
    echo "Creating /Library/Audio/Plug-Ins/HAL..."
    sudo mkdir -p /Library/Audio/Plug-Ins/HAL
fi

echo "Deploying driver bundle..."
sudo mkdir -p "$DRIVER_DIR/Contents/MacOS"
sudo cp Driver/AudioServerPlugin/Info.plist "$DRIVER_DIR/Contents/"

echo "Restarting CoreAudio daemon (coreaudiod)..."
sudo killall coreaudiod 2>/dev/null || true

echo "dynaQ Driver registered successfully."
