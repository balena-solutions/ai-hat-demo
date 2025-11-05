# FROM balenalib/raspberrypi5-debian-python:bookworm-build
FROM python:3.11.9-slim-bookworm

WORKDIR /root

# Install generic requirements

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \ 
    software-properties-common \
    kmod \ 
    dirmngr \
    gnupg \
    udev 

# Need to create a sources.list file for apt-add-repository to work correctly:
# https://groups.google.com/g/linux.debian.bugs.dist/c/6gM_eBs4LgE
RUN echo "# See sources.lists.d directory" > /etc/apt/sources.list

# Add Raspberry Pi repository, as this is where we will get the Hailo deb packages
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E && \
    apt-add-repository -y -S deb http://archive.raspberrypi.com/debian/ bookworm main

# Fake systemd so hailoRT will install in container:
RUN echo '#!/bin/sh\nexec "$@"' > /usr/bin/sudo && chmod +x /usr/bin/sudo
RUN echo '#!/bin/bash\nexit 0' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl
RUN mkdir -p /run/systemd && echo 'docker' > /run/systemd/container

# Dependencies for hailo runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # hailo-tappas-core=3.30.0-1 \
    # hailort=4.19.0-3 \
    # hailo-dkms=4.19.0-1 \
    hailo-all \
    libcap-dev \
    # python3-hailort=4.19.0-2 \
    python3-picamera2 \
    # libcamera-apps \
    && rm -rf /var/lib/apt/lists/*



WORKDIR /usr/src


# Manually remove the system 'av' package to prevent conflict with pip
RUN rm -rf /usr/lib/python3/dist-packages/av*

WORKDIR /app
# create python virtual env and install pip dependencies.
RUN python3 -m venv venv --system-site-packages

# Force the venv (which uses /usr/local/bin/python3) to find the 
# system packages installed by apt (which are in /usr/lib/python3/dist-packages).
RUN echo "/usr/lib/python3/dist-packages" > /app/venv/lib/python3.11/site-packages/debian.pth

# Step 3: Install all Python packages with pip.
# We use the venv's pip and pin numpy<2.0 to maintain
# compatibility with the 'python3-hailort' apt package.
RUN ./venv/bin/pip3 install \
    "numpy<2.0" \
    opencv-python \
    vidgear[asyncio] \
    aiortc \
    uvicorn 

# Bring our source code into docker context, everything not in .dockerignore
COPY . . 


# Set our ENTRYPOINT that ensures `/dev/hailo0` gets created
RUN chmod u+x entry.sh
# ENTRYPOINT ["/app/entry.sh"]

# launch our app.
RUN chmod +x start.sh
CMD ["./start.sh"]
