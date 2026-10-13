#!/bin/bash
# rdlgen on a sample report: --check, --contract, HTML and PDF, each under a
# timeout, so a stall reports as one (GNUstep renders PDF through its print
# machinery, which invents a default printer when none is configured, and
# that path was once reported to hang headless). make check runs it, on
# GNUstep and on the Mac, from the repository's root:
#
#   Scripts/rdlgen-smoke.sh <rdlgen>
#
# XVFB, when set (xvfb-run -a), runs it under a display of its own.
set -euo pipefail
tool=$1
sample=Examples/majorsilence/ReportTests/Reports/MatrixExample.rdl
out=$(mktemp -d)
run() {
  local limit=""
  command -v timeout > /dev/null && limit="timeout 120"
  $limit ${XVFB:-} "$@" || {
    status=$?
    [ "$status" != 124 ] || echo "rdlgen-smoke: timed out after 120s: $*"
    exit "$status"
  }
}
run "$tool" "$sample" --check
run "$tool" "$sample" --contract > /dev/null
run "$tool" "$sample" -f html -o "$out/out.html"
test -s "$out/out.html"
run "$tool" "$sample" -o "$out/out.pdf"
head -c 4 "$out/out.pdf" | grep -q '%PDF' || { echo "rdlgen-smoke: rdlgen wrote something that is not a PDF"; exit 1; }
echo "rdlgen-smoke: --check, --contract, HTML and PDF"
