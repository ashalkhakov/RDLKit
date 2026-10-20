# One rasterizer and text extractor for both sides' PDFs, for running
# compare.py on a machine that has neither (the CI job installs the same
# packages on its runner instead).
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && sed -i 's|http://\([a-z.]*\)ubuntu.com|https://\1ubuntu.com|' /etc/apt/sources.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      poppler-utils imagemagick python3 python3-lxml \
 && rm -rf /var/lib/apt/lists/*
