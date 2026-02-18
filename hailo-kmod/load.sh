#!/bin/bash

set -e

# Extract OS version from environment
OS_VERSION=$(echo "$BALENA_HOST_OS_VERSION" | cut -d " " -f 2)
MOD_PATH="/opt/lib/modules/${OS_VERSION}"
MODULE_NAME="hailo_pci"
MODULE_FILE="${MOD_PATH}/${MODULE_NAME}.ko"
FIRMWARE_SOURCE="/opt/firmware/hailo/hailo8_fw.bin"
FIRMWARE_DIR="/extra-firmware/hailo"
FIRMWARE_FILE="${FIRMWARE_DIR}/hailo8_fw.bin"

echo "[LOAD] ========================================"
echo "[LOAD] Hailo PCIe Kernel Module Loader"
echo "[LOAD] ========================================"
echo "[LOAD] OS Version: ${OS_VERSION}"
echo "[LOAD] Module path: ${MOD_PATH}"
echo "[LOAD] Module file: ${MODULE_FILE}"
echo "[LOAD] Firmware source: ${FIRMWARE_SOURCE}"
echo "[LOAD] Firmware destination: ${FIRMWARE_FILE}"
echo "[LOAD] ========================================"

# Verify module exists
if [[ ! -f "${MODULE_FILE}" ]]; then
    echo "[LOAD] ERROR: Module file not found: ${MODULE_FILE}"
    echo "[LOAD] Available files in ${MOD_PATH}:"
    ls -la "${MOD_PATH}" || true
    exit 1
fi

# Copy firmware version 4.20.0 to extra-firmware volume
echo "[LOAD] Copying firmware 4.20.0 to extra-firmware volume..."
mkdir -p "${FIRMWARE_DIR}"

if [[ -f "${FIRMWARE_SOURCE}" ]]; then
    cp "${FIRMWARE_SOURCE}" "${FIRMWARE_FILE}"
    echo "[LOAD] Firmware copied successfully"
else
    echo "[LOAD] ERROR: Firmware source not found at ${FIRMWARE_SOURCE}"
    exit 1
fi

# Check if module is already loaded
if lsmod | grep -q "^${MODULE_NAME}"; then
    echo "[LOAD] Module ${MODULE_NAME} is already loaded, removing it first..."
    if rmmod "${MODULE_NAME}"; then
        echo "[LOAD] Module unloaded successfully"
    else
        echo "[LOAD] WARNING: Failed to unload module, continuing..."
    fi
fi

# Load the module with RPi5-specific parameters
# These parameters are critical for Raspberry Pi 5:
# - no_power_mode=Y: Disables D0->D3 power transition (not supported on RPi5)
# - force_desc_page_size=4096: Sets descriptor page size for RPi5 PCIe limitations
echo "[LOAD] Loading module with parameters:"
echo "[LOAD]   - no_power_mode=Y (disable power state transitions)"
echo "[LOAD]   - force_desc_page_size=4096 (set descriptor page size)"

if insmod "${MODULE_FILE}" no_power_mode=Y force_desc_page_size=4096; then
    echo "[LOAD] Module loaded successfully"
else
    echo "[LOAD] ERROR: Failed to load module"
    echo "[LOAD] Kernel messages:"
    dmesg | tail -n 30
    exit 1
fi

# Verify module is loaded
if lsmod | grep -q "^${MODULE_NAME}"; then
    echo "[LOAD] ========================================"
    echo "[LOAD] SUCCESS: Module ${MODULE_NAME} is loaded"
    echo "[LOAD] ========================================"
    lsmod | grep "^${MODULE_NAME}"
else
    echo "[LOAD] ERROR: Module verification failed"
    exit 1
fi

# Check for Hailo device
echo "[LOAD] Checking for Hailo device..."
sleep 2  # Give device time to initialize

if [[ -e /dev/hailo0 ]]; then
    echo "[LOAD] Hailo device found at /dev/hailo0"
    ls -la /dev/hailo* || true
else
    echo "[LOAD] WARNING: Hailo device not found at /dev/hailo0"
    echo "[LOAD] This may indicate a hardware issue or device not connected"
    echo "[LOAD] Kernel messages:"
    dmesg | tail -n 20
fi

echo "[LOAD] Module loading complete. Keeping container running..."
# Keep container running so module stays loaded
sleep infinity
