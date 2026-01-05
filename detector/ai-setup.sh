#!/bin/bash

# This script installs the firmware (if necessary) for the Hailo AI HAT
# See the readme for more details about how this works!

FIRMWARE_SOURCE="/usr/lib/firmware/hailo/hailo8_fw.4.20.0.bin"
FIRMWARE_TARGET_DIR="/data/hailo"
FIRMWARE_TARGET="$FIRMWARE_TARGET_DIR/hailo8_fw.bin"
FIRMWARE_PATH_OVERRIDE="/run/mount"
MODULE_NAME="hailo_pci"
DEVICE_PATH="/dev/hailo0"

echo "[HAILO SETUP] Starting firmware preparation..."

# Step 1: Check if firmware already exists in /data/hailo
if [[ -f "$FIRMWARE_TARGET" ]]; then
    echo "[HAILO SETUP] Firmware already exists at $FIRMWARE_TARGET"
else
    echo "[HAILO SETUP] Firmware not found in /data, preparing directory..."
    mkdir -p "$FIRMWARE_TARGET_DIR"

    if [[ -f "$FIRMWARE_SOURCE" ]]; then
        echo "[HAILO SETUP] Copying firmware from $FIRMWARE_SOURCE to $FIRMWARE_TARGET"
        cp "$FIRMWARE_SOURCE" "$FIRMWARE_TARGET"
    else
        echo "[HAILO SETUP] ERROR: Firmware source not found at $FIRMWARE_SOURCE"
        exit 1
    fi
fi

# Step 2: Set firmware_class.path to /run/mount
echo "[HAILO SETUP] Setting firmware_class.path to $FIRMWARE_PATH_OVERRIDE"
echo "$FIRMWARE_PATH_OVERRIDE" > /sys/module/firmware_class/parameters/path

# Step 3: Wait for hailo-kmod service to load the module and create device
echo "[HAILO SETUP] Waiting for hailo-kmod service to load kernel module..."
RETRY_COUNT=0
MAX_RETRIES=30

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if [[ -e "$DEVICE_PATH" ]]; then
        echo "[HAILO SETUP] Hailo device available at $DEVICE_PATH"
        break
    else
        echo "[HAILO SETUP] Waiting for device... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        sleep 2
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [[ ! -e "$DEVICE_PATH" ]]; then
    echo "[HAILO SETUP] ERROR: Hailo device NOT found at $DEVICE_PATH after ${MAX_RETRIES} attempts"
    echo "[HAILO SETUP] Check hailo-kmod service logs for module loading issues"
    dmesg | tail -n 20
    exit 1
fi

exec "$@"
