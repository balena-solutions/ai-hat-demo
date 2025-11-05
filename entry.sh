#!/bin/bash
set -euo pipefail

# # setup container to dynamically load /dev devices.
# This command only works in privileged container
tmp_mount='/tmp/_balena'
mkdir -p "$tmp_mount"
if mount -t devtmpfs none "$tmp_mount" &> /dev/null; then
	PRIVILEGED=true
	umount "$tmp_mount"
else
	PRIVILEGED=false
fi
rm -rf "$tmp_mount"

function mount_dev()
{
	tmp_dir='/tmp/tmpmount'
	mkdir -p "$tmp_dir"
	mount -t devtmpfs none "$tmp_dir"
	mkdir -p "$tmp_dir/shm"
	mount --move /dev/shm "$tmp_dir/shm"
	mkdir -p "$tmp_dir/mqueue"
	mount --move /dev/mqueue "$tmp_dir/mqueue"
	mkdir -p "$tmp_dir/pts"
	mount --move /dev/pts "$tmp_dir/pts"
	touch "$tmp_dir/console"
	mount --move /dev/console "$tmp_dir/console"
	umount /dev || true
	mount --move "$tmp_dir" /dev

	# Since the devpts is mounted with -o newinstance by Docker, we need to make
	# /dev/ptmx point to its ptmx.
	# ref: https://www.kernel.org/doc/Documentation/filesystems/devpts.txt
	ln -sf /dev/pts/ptmx /dev/ptmx

	# When using io.balena.features.sysfs the mount point will already exist
	# we need to check the mountpoint first.
	sysfs_dir='/sys/kernel/debug'

	if ! mountpoint -q "$sysfs_dir"; then
		mount -t debugfs nodev "$sysfs_dir"
	fi

}

function start_udev()
{
	if [ "$UDEV" == "on" ]; then
		if $PRIVILEGED; then
			mount_dev
			if command -v udevd &>/dev/null; then
				unshare --net udevd --daemon &> /dev/null
			else
				unshare --net /lib/systemd/systemd-udevd --daemon &> /dev/null
			fi
			udevadm trigger &> /dev/null
		else
			echo "Unable to start udev, container must be run in privileged mode to start udev!"
		fi
	fi
}

UDEV='on'

echo "Starting UDEV..."
start_udev

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

# Step 3: write hailo.conf file
echo "options hailo_pci force_desc_page_size=4096" | sudo tee /etc/modprobe.d/hailo_pci.conf > /dev/null

# Step 4: Load hailo_pci module
echo "[HAILO SETUP] Reloading kernel module: $MODULE_NAME"

if lsmod | grep -q "^${MODULE_NAME//-/_}"; then
    echo "[HAILO SETUP] Module $MODULE_NAME is already loaded — unloading first..."
    if modprobe -r "$MODULE_NAME"; then
        echo "[HAILO SETUP] Module $MODULE_NAME unloaded successfully"
    else
        echo "[HAILO SETUP] WARNING: Failed to unload $MODULE_NAME. Continuing anyway..."
    fi
else
    echo "[HAILO SETUP] Module $MODULE_NAME not currently loaded — continuing..."
fi

echo "[HAILO SETUP] Loading module $MODULE_NAME..."
if modprobe "$MODULE_NAME"; then
    echo "[HAILO SETUP] Module loaded successfully"
else
    echo "[HAILO SETUP] ERROR: Failed to load $MODULE_NAME"
    dmesg | tail -n 20
    exit 1
fi

# Step 5: Verify device node
if [[ -e "$DEVICE_PATH" ]]; then
    echo "[HAILO SETUP] Hailo device available at $DEVICE_PATH"
else
    echo "[HAILO SETUP] Hailo device NOT found at $DEVICE_PATH"
    dmesg | tail -n 20
    exit 1
fi

exec "$@"

