#!/bin/bash

# Run a script to set up and start UDEV
# The script will then start the Hailo setup script
./entry.sh

sleep 5

udevadm control --reload

# If you want to start your own app, you can start it here!

python main.py

sleep infinity
