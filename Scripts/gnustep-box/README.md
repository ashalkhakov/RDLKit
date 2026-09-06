# A GNUstep box, for reproducing what only happens on Linux

Debian 13, clang, `ng-gnu-gnu`, the gnustep-2.0 runtime — the same stack
`.github/scripts/dependencies.sh` builds on CI and on the machine that builds
the AppImage, including the libs-gui PDF patch. It exists so a crash that only
happens on GNUstep can be reproduced, and debugged, without a Mac being in the
way.

## Build it

From the repository root:

    docker build -t rdlkit-gnustep -f Scripts/gnustep-box/Dockerfile .

Twenty minutes or so, most of it compiling libs-base and libs-gui, and about
3 GB. The image carries only the GNUstep stack: RDLKit itself is mounted at run
time, so editing the app never rebuilds any of this.

It builds for the machine's own architecture. To match the x86_64 the AppImage
ships as, add `--platform linux/amd64` — correct, but emulated and hours rather
than minutes, so it is worth doing only for a bug that turns out to be
architecture-specific.

If the build dies fetching packages ("File has unexpected size"), that is the
Debian mirror through Docker's NAT, not the recipe. Run it again; apt is
configured here to retry and not to pipeline, and the layers already built are
kept.

## Use it

    # both suites, under a virtual display, with AddressSanitizer
    docker run --rm -v "$PWD":/src:ro -v "$PWD/Scripts/gnustep-box":/box:ro \
        rdlkit-gnustep sh /box/run-tests.sh

    # the app itself, under gdb, when the suites pass and it still dies
    docker run --rm -v "$PWD":/src:ro -v "$PWD/Scripts/gnustep-box":/box:ro \
        rdlkit-gnustep sh /box/run-app.sh

The repository is mounted read-only and copied to `/work` inside, so the Mac's
object files and the Linux ones never meet.

## Without a container

A machine that already builds the AppImage has this stack already, and needs
none of the above:

    GNUSTEP_PREFIX=/opt/gnustep-prefix ./Scripts/gnustep-debug.sh app
