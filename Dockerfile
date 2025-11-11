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
    hailo-all \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Python libraries
RUN pip install flask
RUN pip install opencv-python
RUN pip install numpy

# Make hailo_platform available to pip's Python environment
# Create a symlink from the system package to pip's site-packages
RUN SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])") && \
    if [ -d /usr/lib/python3/dist-packages/hailo_platform ]; then \
        ln -sf /usr/lib/python3/dist-packages/hailo_platform "$SITE_PACKAGES/hailo_platform"; \
        ln -sf /usr/lib/python3/dist-packages/hailo_platform.egg-info "$SITE_PACKAGES/hailo_platform.egg-info" || true; \
        echo "Hailo platform linked to $SITE_PACKAGES"; \
    else \
        echo "Warning: hailo_platform not found in expected location"; \
    fi

WORKDIR /app

# Copy our sh files to the device
COPY *.sh ./

# copy flask app
COPY main.py ./

# Set our ENTRYPOINT that ensures `/dev/hailo0` gets created
RUN chmod u+x entry.sh
# ENTRYPOINT ["/app/entry.sh"]

# launch our start script.
RUN chmod +x start.sh
CMD ["./start.sh"]
