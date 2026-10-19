# A GNUstep box to reproduce the Linux build locally, so a portability bug can
# be found in a minute here instead of a round trip through CI.
#
#   docker build -f .tools/gnustep.Dockerfile -t rdlkit-gnustep .
#   .tools/gnustep.sh make check
#
# The stack is the one CI builds on: the gnustep-patches release
# .github/pins.env names, an archive unpacked at /, on the Ubuntu it is built
# for, with the packages it lists beside it.
#
# And the fonts the cross-platform comparison renders with (.tools/xp): the
# Microsoft core fonts, which Ubuntu's installer fetches from Microsoft's own
# archives as their licence asks, beside the stack's DejaVu and Liberation.
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
# Through caching proxies that answer with stale indexes: no pipelining, no
# proxy caches, retries; and over HTTPS once it can be, because some networks
# rewrite plain HTTP from Ubuntu's mirrors ("File has unexpected size").
RUN printf 'Acquire::http::No-Cache "true";\nAcquire::BrokenProxy "true";\nAcquire::http::Pipeline-Depth "0";\nAcquire::Retries "5";\n' \
      > /etc/apt/apt.conf.d/99-retries
COPY .github/pins.env /tmp/pins.env
RUN set -e; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    sed -i 's|http://\([a-z.]*\)ubuntu.com|https://\1ubuntu.com|' /etc/apt/sources.list; apt-get update; \
    v=$(sed -n 's/^GNUSTEP_PATCHES_VERSION=//p' /tmp/pins.env); \
    curl -fsSL "https://github.com/ashalkhakov/gnustep-patches/releases/download/v$v/gnustep-patches-$v-ubuntu22.04-$(uname -m).tar.xz" \
      | tar -C / -xJ; \
    grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt | xargs apt-get install -y --no-install-recommends; \
    update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10; \
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections; \
    apt-get install -y --no-install-recommends fontconfig ttf-mscorefonts-installer; fc-cache -f; \
    rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++ LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    LD_LIBRARY_PATH=/opt/gnustep/lib
WORKDIR /src
