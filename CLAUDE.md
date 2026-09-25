# RDLKit

Report Definition Language Kit for GNUstep and Cocoa: a generator
(`RDLKit` + `RDLGen`) that turns an RDL file, data sources and parameters
into PDF or HTML, and a designer (`RDLDesigner`) that edits the definitions.

## GNUstep patches live elsewhere

Fixes to GNUstep itself are not kept here. They live in `../gnustep-patches`,
which this machine's GNUstep projects share, and `.github/scripts/dependencies.sh`
clones that repository at the commit pinned by `GNUSTEP_PATCHES_REF` and
applies what it carries for libs-base and libs-gui.

If a bug here turns out to be GNUstep's, work in that repository and read its
`CLAUDE.md` first: reproduce in the docker container, fix, turn the
reproduction into a test in GNUstep's own suite, and push it there — that is
where patches are kept and where they are sent upstream from.

## Testing

GNUstep builds and tests run in docker (`.tools/gnustep.Dockerfile` wraps
that), and anything that draws needs `xvfb-run -a`. `Patches/` still holds
this project's own bug notes and reproductions for faults that are not
GNUstep patches — PDF printing hanging headless, ibtool aborting silently,
NSXML dropping whitespace-only text.
