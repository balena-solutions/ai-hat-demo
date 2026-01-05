#!/bin/bash

set -e

# Extract OS version from environment
OS_VERSION=$(echo "$BALENA_HOST_OS_VERSION" | cut -d " " -f 2)
MOD_PATH="/opt/lib/modules/${OS_VERSION}"
MODULE_NAME="hailo_pci"
MODULE_FILE="${MOD_PATH}/${MODULE_NAME}.ko"
FIRMWARE_DIR="/run/mount/hailo"
FIRMWARE_FILE="${FIRMWARE_DIR}/hailo8_fw.bin"
FIRMWARE_PATH_PARAM="/sys/module/firmware_class/parameters/path"

echo "[LOAD] ========================================"
echo "[LOAD] Hailo PCIe Kernel Module Loader"
echo "[LOAD] ========================================"
echo "[LOAD] OS Version: ${OS_VERSION}"
echo "[LOAD] Module path: ${MOD_PATH}"
echo "[LOAD] Module file: ${MODULE_FILE}"
echo "[LOAD] Firmware file: ${FIRMWARE_FILE}"
echo "[LOAD] ========================================"

# Verify module exists
if [[ ! -f "${MODULE_FILE}" ]]; then
    echo "[LOAD] ERROR: Module file not found: ${MODULE_FILE}"
    echo "[LOAD] Available files in ${MOD_PATH}:"
    ls -la "${MOD_PATH}" || true
    exit 1
fi

# Wait for firmware file to be placed by detector service
# The detector service will copy firmware from its image to the shared volume
echo "[LOAD] Waiting for firmware file from detector service..."
RETRY_COUNT=0
MAX_RETRIES=60  # Wait up to 2 minutes

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if [[ -f "${FIRMWARE_FILE}" ]]; then
        echo "[LOAD] Firmware file found at ${FIRMWARE_FILE}"
        break
    else
        echo "[LOAD] Waiting for firmware... (attempt $((RETRY_COUNT + 1))/${MAX_RETRIES})"
        sleep 2
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [[ ! -f "${FIRMWARE_FILE}" ]]; then
    echo "[LOAD] ERROR: Firmware file not found after ${MAX_RETRIES} attempts"
    echo "[LOAD] Expected location: ${FIRMWARE_FILE}"
    echo "[LOAD] The detector service should copy firmware to this location"
    echo "[LOAD] Contents of /run/mount/:"
    ls -laR /run/mount/ || true
    exit 1
fi

# Set firmware_class.path to /run/mount so the kernel can find firmware
echo "[LOAD] Setting firmware_class.path to /run/mount"
echo "/run/mount" > "${FIRMWARE_PATH_PARAM}" || {
    echo "[LOAD] WARNING: Could not set firmware_class.path"
}

# Verify firmware_class.path is set correctly
echo "[LOAD] Checking firmware_class.path parameter..."
if [[ -f "${FIRMWARE_PATH_PARAM}" ]]; then
    FW_PATH=$(cat ${FIRMWARE_PATH_PARAM})
    echo "[LOAD] firmware_class.path is set to: ${FW_PATH}"
    if [[ "${FW_PATH}" != "/run/mount" ]]; then
        echo "[LOAD] WARNING: firmware_class.path is not set to /run/mount"
        echo "[LOAD] Expected: /run/mount"
        echo "[LOAD] Actual: ${FW_PATH}"
    fi
else
    echo "[LOAD] WARNING: firmware_class.path parameter not accessible"
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
