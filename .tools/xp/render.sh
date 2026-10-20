#!/bin/sh
# render.sh RDLGEN SRCROOT OUTDIR [TIMEOUT]
#
# Renders every report of the corpus -- the Majorsilence examples and the
# designer's samples -- to PDF and to HTML with RDLGEN, each from its own
# folder as a person would run it (documents beside it are found), and
# records how each run ended in OUTDIR/results.tsv: id, path, format, status
# (an exit code, "timeout" or "signalN") and seconds. The same on macOS and
# on GNUstep: TZ=UTC, --language en-US, and the parameters params.txt gives
# the reports that declare one with no usable default.
#
# The fonts are the caller's to set up (see xp.sh and the CI job): the same
# families on both sides, and the same fallback.
gen=$1; src=$2; out=$3; limit=${4:-120}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"; out=$(cd "$out" && pwd)
export TZ=UTC
printf 'id\tpath\tformat\tstatus\tseconds\n' > "$out/results.tsv"
(cd "$src" && find Examples RDLDesigner/Samples \( -iname '*.rdl' -o -iname '*.rdlc' \) | LC_ALL=C sort) > "$out/corpus.txt"
while IFS= read -r rel; do
  id=$(printf '%s' "$rel" | sed 's|^Examples/majorsilence/||; s|^RDLDesigner/|Designer/|; s|[/ ]|_|g; s|\.[Rr][Dd][Ll][Cc]*$||')
  for fmt in pdf html; do
    set -- "$gen" "$(basename "$rel")" -f "$fmt" -o "$out/$id.$fmt" --language en-US
    line=$(awk -F'\t' -v p="$rel" '$1==p' "$here/params.txt")
    if [ -n "$line" ]; then
      oldifs=$IFS; IFS='	'; set -f
      for kv in $(printf '%s' "$line" | cut -f2-); do set -- "$@" -p "$kv"; done
      IFS=$oldifs; set +f
    fi
    r=$(cd "$src/$(dirname "$rel")" && perl "$here/run1.pl" "$limit" "$out/$id.$fmt.out" "$out/$id.$fmt.err" "$@")
    printf '%s\t%s\t%s\t%s\n' "$id" "$rel" "$fmt" "$r" | sed 's/ \([0-9.]*\)$/\t\1/' >> "$out/results.tsv"
  done
done < "$out/corpus.txt"
awk -F'\t' 'NR>1 {n[$3" "$4]++} END {for (k in n) print n[k], k}' "$out/results.tsv" | sort -k2
