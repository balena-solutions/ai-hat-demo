# Hailo AI HAT on balena Raspberry Pi 5

This project is a demonstration of how to install and use the hailo8 firmware on a Raspberry Pi 5. The demo utilizes an attached Pi camera (V2 or V3) to display bounding boxes around objects detected by a neural network using the AI HAT/HAT+. 

## Usage:
Clone this project and then run the following from the root of the project, where `myFleet` is the name of you fleet on balenaCloud:
```
balena push myFleet
```

## Configuration

In order to make use of Gen 3 PCI, ensure that your device overlay setting on `https://dashboard.balena-cloud.com/devices/<DEVICE_UUID>/config` is set to the following:
```
"vc4-kms-v3d,cma-320","dwc2,dr_mode=host","dwc2,dr_mode=host,pciex1_gen=3"
```

Add the "Custom configuration" `BALENA_HOST_CONFIG_camera_auto_detect` with a value of `1`

You should also increase the "Define device GPU memory in megabytes." setting in the "Device configuration" to at least 64.

## Testing:
For all of the tests below open a terminal session to hailo-service.
1. Make sure the attached Pi camera is detected:
```
root@1933b87:/app# rpicam-hello --list-cameras -n -v
Available cameras
-----------------
0 : imx708 [4608x2592 10-bit RGGB] (/base/axi/pcie@1000120000/rp1/i2c@88000/imx708@1a)
    Modes: 'SRGGB10_CSI2P' : 1536x864 [120.13 fps - (768, 432)/3072x1728 crop]
                             2304x1296 [56.03 fps - (0, 0)/4608x2592 crop]
                             4608x2592 [14.35 fps - (0, 0)/4608x2592 crop]

    Available controls for 4608x2592 SRGGB10_CSI2P mode:
    ----------------------------------------------------
...
```

2. Check that the hailo device is correctly connected:
```
root@b432f02c44f7:~# hailortcli fw-control identify
Executing on device: 0001:01:00.0
Identifying board
Control Protocol Version: 2
Firmware Version: 4.20.0 (release,app,extended context switch buffer)
Logger Version: 0
Board Name: Hailo-8
Device Architecture: HAILO8L
Serial Number: HLDDLBB243201979
Part Number: HM21LB1C2LAE
Product Name: HAILO-8L AI ACC M.2 B+M KEY MODULE EXT TMP
```

If you see output similar to the above, you are all set to try out the demo steps below:

## Demo

In the same terminal session used above, we'll run a demo that utilizes the AI HAT/HAT+. The demo is part of the `rpi-cam` apps suite that is installed in the Dockerfile. (For details on how this works, see the section below.)

You can learn more about this demo and the AI HAT in the [Raspberry Pi documentation](https://www.raspberrypi.com/documentation/computers/ai.html)

This demo displays bounding boxes around objects detected by a neural network. By default the display will output over the HDMI out of the PI 5. To disable this, add the `-n` flag. Run the following command to try the demo: (In order to display textual output describing the objects detected, we have added the -v 2 option.)

```
rpicam-hello -t 0 -v 2 --post-process-file /usr/share/rpi-camera-assets/hailo_yolov6_inference.json
```

You should start seeing a lot of scrolling text output like the below, in addition to viewing the camera output on an attached HDMI monitor.

```
Camera started!
------
Object: clock[75] (0.53) @ 1502,750 134x147
------
Viewfinder frame 0
------
Object: clock[75] (0.57) @ 1499,753 136x150
------
Viewfinder frame 1
------
Object: person[1] (0.45) @ 1431,851 272x424
Object: person[1] (0.42) @ 1880,906 201x124
Object: scissors[77] (0.44) @ 1810,1005 474x290
```

Press CTRL + c to end the demo.

## How it works

### Dockerfile

Our Dockerfile adds apt repositories so we can download the Hailo deb packages as well as thge Raspberry Pi OS camera apps. The Hailo software expects a system service to be running, but systemd is not really recommended to run in a container, so we "fake" one instead. (We strongly advocate for a multi-container architecture where different components of your application are separated into individual containers. )

We also install the `hailo-all` package that includes the Hailo kernel device driver and firmware, HailoRT middleware software, Hailo Tappas core post-processing libraries and the rpicam-apps Hailo post-processing software demo stages.

Note that our base image is simply an official Python image. Though we don't specifically use any Python in our demo, if you copy this example you can easily run your own Python apps in the container.

### entry.sh

This script sets up a UDEV system to detect plugged hardware (necessary for the camera) and then calls the ai-setup script.

### ai-setup.sh

This script is the main point of interest for this demo because it installs the firmware for the Hailo AI HAT. Ask Shaun how this works!

### rpi-cam apps

The rpicam apps use the libcamera library under the hood so it can send output directly to hdmi using a dedicated subsystem in linux kernel (DRM/KMS).

