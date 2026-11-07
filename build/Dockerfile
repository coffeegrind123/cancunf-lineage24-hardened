# LineageOS 24 build environment for cancunf. Package list follows the
# LineageOS "build for a device" guide for Ubuntu 23.10+.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs \
      gnupg gperf imagemagick protobuf-compiler python3-protobuf lib32readline-dev \
      lib32z1-dev libdw-dev libelf-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
      lzop pngcrush rsync schedtool squashfs-tools xsltproc zip unzip zlib1g-dev \
      python3 python-is-python3 openssh-client ca-certificates procps time xxd file \
    && rm -rf /var/lib/apt/lists/*
RUN curl -sSfL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 755 /usr/local/bin/repo
# ubuntu:24.04 ships user "ubuntu" as uid 1000; reuse it as the build user.
RUN usermod -l build -d /home/build -m ubuntu && groupmod -n build ubuntu
USER build
WORKDIR /lin
ENV USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/lin/ccache
