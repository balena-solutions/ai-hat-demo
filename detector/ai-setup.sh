#!/bin/bash

# This script prepares firmware for the Hailo AI HAT and waits for the device
# The hailo-kmod service handles loading the kernel module

FIRMWARE_SOURCE="/usr/lib/firmware/hailo/hailo8_fw.4.20.0.bin"
FIRMWARE_TARGET_DIR="/data/hailo"
FIRMWARE_TARGET="$FIRMWARE_TARGET_DIR/hailo8_fw.bin"
DEVICE_PATH="/dev/hailo0"

echo "[HAILO SETUP] Starting firmware preparation..."

# Step 1: Copy firmware to shared volume for hailo-kmod service
if [[ -f "$FIRMWARE_TARGET" ]]; then
    echo "[HAILO SETUP] Firmware already exists at $FIRMWARE_TARGET"
else
    echo "[HAILO SETUP] Preparing firmware for hailo-kmod service..."
    mkdir -p "$FIRMWARE_TARGET_DIR"

    if [[ -f "$FIRMWARE_SOURCE" ]]; then
        echo "[HAILO SETUP] Copying firmware from $FIRMWARE_SOURCE to $FIRMWARE_TARGET"
        cp "$FIRMWARE_SOURCE" "$FIRMWARE_TARGET"
        echo "[HAILO SETUP] Firmware ready for hailo-kmod service"
    else
        echo "[HAILO SETUP] ERROR: Firmware source not found at $FIRMWARE_SOURCE"
        exit 1
    fi
fi

# Step 2: Wait for hailo-kmod service to load the module and create device
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
