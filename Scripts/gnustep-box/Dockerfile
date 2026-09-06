# The user's own target: Debian 13, clang, the gnustep-2.0 runtime. Built the
# way .github/scripts/dependencies.sh builds it, so what breaks here is what
# breaks there.
FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -q -y update && apt-get -q -y install \
      clang lld cmake make git pkg-config ca-certificates \
      libgnutls28-dev libffi-dev libicu-dev libxml2-dev libxslt1-dev \
      libssl-dev libavahi-client-dev zlib1g-dev gnutls-bin libcurl4-gnutls-dev \
      libgmp-dev libcairo2-dev libjpeg-dev libtiff-dev libpng-dev libicns-dev \
      libbsd-dev \
      libxt-dev libxmu-dev libxft-dev libxrandr-dev libxfixes-dev libxcursor-dev \
      xvfb gdb xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld 10

ENV CC=clang CXX=clang++ \
    LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    DEPS_PATH=/deps INSTALL_PATH=/gnustep \
    LD_LIBRARY_PATH=/gnustep/lib

# Only what the dependency build reads, so editing the app does not rebuild
# the whole stack.
WORKDIR /build
COPY .github/scripts/dependencies.sh /build/.github/scripts/dependencies.sh
COPY Patches /build/Patches
RUN sh /build/.github/scripts/dependencies.sh 2>&1 | tail -40

WORKDIR /work
