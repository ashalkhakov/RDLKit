# A GNUstep box to reproduce the Linux build locally, so a portability bug can
# be found in a minute here instead of a round trip through CI.
#
# Build it once -- this compiles libobjc2, libdispatch, gnustep-make, base, gui,
# back and tools-xctest from source, so it takes the better part of an hour:
#
#   docker build -f .tools/gnustep.Dockerfile -t rdlkit-gnustep .
#
# After that the image is cached and running the suites is quick:
#
#   .tools/gnustep.sh make -C PicaKitTests run-tests
#   .tools/gnustep.sh make -C PicaDesignerTests run-tests
#
# The stack is the same one the workflow builds, from the same script, so what
# fails here fails there.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -q -y update && apt-get -q -y install \
      clang lld cmake make git pkg-config xvfb \
      libgnutls28-dev libffi-dev libicu-dev libxml2-dev libxslt1-dev libssl-dev \
      libavahi-client-dev zlib1g-dev gnutls-bin libcurl4-gnutls-dev libgmp-dev \
      libcairo2-dev libjpeg-dev libtiff-dev libpng-dev libicns-dev \
      libpthread-workqueue-dev \
      libxt-dev libxmu-dev libxft-dev libxrandr-dev libxfixes-dev libxcursor-dev \
    && rm -rf /var/lib/apt/lists/*

# The gnustep-2.0 runtime wants ld.gold or lld; 24.04 ships lld.
RUN update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld 10

ENV CC=clang CXX=clang++ \
    LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    DEPS_PATH=/deps INSTALL_PATH=/gnustep

COPY .github/scripts/dependencies.sh /tmp/dependencies.sh
RUN sh /tmp/dependencies.sh && rm -rf /deps

ENV LD_LIBRARY_PATH=/gnustep/lib
WORKDIR /src
