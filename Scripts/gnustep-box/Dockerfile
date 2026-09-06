# The user's own target: Debian 13, clang, the gnustep-2.0 runtime. Built the
# way .github/scripts/dependencies.sh builds it, so what breaks here is what
# breaks there.
FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive
# Retries, because the mirror hands back a truncated file often enough through
# Docker's NAT to fail a build on its own, and the CDN rather than the
# round-robin because it is the difference between ten minutes and an hour
# here. Pipelining is deliberately left alone: turning it off fetches one
# package per connection and is a worse failure than the one it avoids.
RUN printf 'Acquire::Retries "8";\n' > /etc/apt/apt.conf.d/99retries \
    && sed -i 's|deb\.debian\.org|cdn-aws.deb.debian.org|g' \
         /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list 2>/dev/null; true
RUN apt-get -q -y update && apt-get -q -y --fix-missing install \
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
# Not piped to tail: a pipeline's status is the last command's, so piping a
# failed build into tail would leave a green layer holding half a stack. Kept
# in full, and the tail is printed only when it fails.
RUN sh /build/.github/scripts/dependencies.sh > /tmp/deps.log 2>&1 \
    || { tail -80 /tmp/deps.log; false; }

# What the stack has to have for any of this to mean anything.
RUN . /gnustep/System/Library/Makefiles/GNUstep.sh \
    && gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY \
    && find /gnustep -name 'libgnustep-base.so*' -o -name 'libgnustep-gui.so*' \
       -o -name 'libgnustep-back*.bundle' | head

WORKDIR /work
