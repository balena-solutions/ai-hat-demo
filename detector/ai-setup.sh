#!/bin/bash

# This script waits for the Hailo device to be ready
# The hailo-kmod service handles firmware setup and kernel module loading

DEVICE_PATH="/dev/hailo0"

echo "[HAILO SETUP] Waiting for Hailo AI HAT+ device..."

# Wait for hailo-kmod service to load the module and create device
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
