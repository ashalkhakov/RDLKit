#!/usr/bin/env python3
"""Compare two render runs of the RDLKit corpus (render.sh output dirs).

    compare.py A_DIR B_DIR OUT_DIR [--labels A B] [--expected FILE] [--pixels PCT]

Both sides' PDFs go through the same rasterizer and text extractor (poppler's
pdftoppm and pdftotext, ImageMagick's compare), wherever this runs. Writes
OUT_DIR/index.html (side by side), OUT_DIR/summary.tsv, OUT_DIR/results.json,
OUT_DIR/verdict.txt and the images.

Each report is held to five checks:

    status      PDF and HTML each rendered, or failed, the same way on both
    pages       the same number of pages, the same size and way up
    text        the same words in the PDF (ligatures spelled out, the run's
                own timestamp masked)
    pixels      no page differs in more than PCT% of its pixels (0.5)
    html        the same words in the HTML

A difference listed in the expected-differences file (id, check, reason:
usually the gnustep-patches fix it waits on) is reported and passed. One that
is not fails the run (exit 1). A listed difference that no longer shows is
reported as fixed, so the list can be tightened.
"""
import argparse, csv, difflib, fnmatch, html, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

DPI = 60
FUZZ = "20%"        # colour distance below which two pixels count as equal
FLAG = 0.10         # % of differing pixels above which a page is pictured

ap = argparse.ArgumentParser()
ap.add_argument("a_dir"); ap.add_argument("b_dir"); ap.add_argument("out")
ap.add_argument("--labels", nargs=2, default=["macOS", "Linux"])
ap.add_argument("--expected", default=None)
ap.add_argument("--pixels", type=float, default=0.5)
args = ap.parse_args()
a_dir, b_dir, out = args.a_dir, args.b_dir, args.out
a_label, b_label = args.labels
PIXELS = args.pixels
os.makedirs(os.path.join(out, "img"), exist_ok=True)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def results(d):
    r = {}
    with open(os.path.join(d, "results.tsv")) as f:
        for row in csv.DictReader(f, delimiter="\t"):
            r.setdefault(row["id"], {"path": row["path"]})[row["format"]] = row
    return r


A, B = results(a_dir), results(b_dir)


def status_word(row):
    s = row["status"]
    if s == "0":
        return "rendered"
    if s == "timeout":
        return "hung"
    if s.startswith("signal"):
        return "crashed(" + s + ")"
    return "failed(%s)" % s


def read(p):
    try:
        with open(p, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def stderr_lines(d, rid, fmt):
    text = read(os.path.join(d, "%s.%s.err" % (rid, fmt)))
    # GNUstep's NSLog prefix: date, time, process
    text = re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+ \S+\[\d+:\d+\] ", "", text, flags=re.M)
    return [l for l in text.splitlines() if l.strip()]


def pdf_pages(p):
    r = run(["pdfinfo", p])
    m = re.search(r"^Pages:\s+(\d+)", r.stdout, re.M)
    size = re.search(r"^Page size:\s+(.*)$", r.stdout, re.M)
    return (int(m.group(1)) if m else None), (size.group(1).strip() if size else "")


def pdf_text(p):
    r = run(["pdftotext", "-raw", p, "-"])
    return r.stdout


DATETIME = re.compile(r"\b\d{1,2}/\d{1,2}/\d{4}( \d{1,2}:\d\d(:\d\d)? ?[AP]M)?")


def norm_text(t):
    """What is compared: ligature code points spelled out (NFKC), and the time
    of the run (Globals!ExecutionTime) masked."""
    import unicodedata
    return DATETIME.sub("<DATE>", unicodedata.normalize("NFKC", t))


def words(t):
    return norm_text(t).split()


def raster(p, prefix):
    run(["pdftoppm", "-r", str(DPI), "-png", p, prefix])
    d, base = os.path.split(prefix)
    return sorted(os.path.join(d, f) for f in os.listdir(d)
                  if f.startswith(base + "-") and f.endswith(".png"))


def img_size(p):
    r = run(["identify", "-format", "%w %h", p])
    w, h = r.stdout.split()
    return int(w), int(h)


def page_diff(pa, pb, dpath):
    wa, ha = img_size(pa)
    wb, hb = img_size(pb)
    rotated = False
    if (wa, ha) != (wb, hb) and abs(wa - hb) <= 2 and abs(ha - wb) <= 2 and wa != ha:
        # GNUstep prints landscape as a portrait sheet with the content turned
        # 90 degrees; turn it back so the content itself is compared.
        run(["convert", pb, "-rotate", "90", pb])
        wb, hb = img_size(pb)
        rotated = True
    w, h = max(wa, wb), max(ha, hb)
    args = []
    if (wa, ha) != (wb, hb):
        # pad both to the larger page, top-left anchored, so a size change shows
        for src in (pa, pb):
            run(["convert", src, "-background", "white", "-gravity", "NorthWest",
                 "-extent", "%dx%d" % (w, h), src])
    r = run(["compare", "-metric", "AE", "-fuzz", FUZZ, pa, pb, dpath])
    try:
        ae = float(r.stderr.split()[0])
    except (ValueError, IndexError):
        ae = float(w * h)
    return 100.0 * ae / (w * h), (wa, ha) != (wb, hb), rotated


def html_norm(p):
    """(visible text words, tag sequence, styles) of an HTML file."""
    try:
        import lxml.html
        doc = lxml.html.parse(p).getroot()
    except Exception:
        return None
    for bad in doc.xpath("//script|//style"):
        bad.getparent().remove(bad)
    text = " ".join(doc.text_content().split())
    tags = [e.tag for e in doc.iter() if isinstance(e.tag, str)]
    styles = [e.get("style", "") for e in doc.iter() if isinstance(e.tag, str)]
    return text, tags, styles


def numbers_in(style):
    return re.findall(r"-?\d+(?:\.\d+)?", style)


def compare_one(rid):
    ra, rb = A.get(rid, {}), B.get(rid, {})
    res = {"id": rid, "path": (ra or rb).get("path"), "a": {}, "b": {}}
    for side, r, d in (("a", ra, a_dir), ("b", rb, b_dir)):
        for fmt in ("pdf", "html"):
            row = r.get(fmt)
            if row:
                res[side][fmt] = {"status": status_word(row), "seconds": float(row["seconds"]),
                                  "stderr": stderr_lines(d, rid, fmt)}
    # PDF
    pa, pb = os.path.join(a_dir, rid + ".pdf"), os.path.join(b_dir, rid + ".pdf")
    ok_a = res["a"].get("pdf", {}).get("status") == "rendered" and os.path.exists(pa)
    ok_b = res["b"].get("pdf", {}).get("status") == "rendered" and os.path.exists(pb)
    res["pages_a"], res["size_a"] = pdf_pages(pa) if ok_a else (None, "")
    res["pages_b"], res["size_b"] = pdf_pages(pb) if ok_b else (None, "")
    res["pages"] = []
    if ok_a and ok_b:
        xa, xb = pdf_text(pa), pdf_text(pb)
        ta, tb = words(xa), words(xb)
        res["raw_text_differs"] = xa.split() != xb.split()
        res["text_differs"] = ta != tb
        if ta != tb and sorted(ta) == sorted(tb):
            res["text_differs"] = False
            res["text_order_only"] = True   # same words, other reading order (rotated pages)
        res["text_diff"] = list(difflib.unified_diff(
            norm_text(xa).split("\n"), norm_text(xb).split("\n"), a_label, b_label, n=1, lineterm=""))[:80] if ta != tb else []
        res["text_ratio"] = round(difflib.SequenceMatcher(None, ta, tb, autojunk=False).ratio(), 4) if ta != tb else 1.0
        tmp = os.path.join(out, "tmp", rid)
        os.makedirs(tmp, exist_ok=True)
        ia, ib = raster(pa, os.path.join(tmp, "a")), raster(pb, os.path.join(tmp, "b"))
        for i in range(max(len(ia), len(ib))):
            pg = {"n": i + 1}
            if i < len(ia) and i < len(ib):
                dpath = os.path.join(tmp, "d-%d.png" % (i + 1))
                pct, resized, rotated = page_diff(ia[i], ib[i], dpath)
                pg.update(diff=round(pct, 3), size_differs=resized, rotated=rotated)
                if rotated:
                    res["rotated"] = True
            else:
                pg.update(diff=100.0, missing=a_label if i >= len(ia) else b_label)
            if pg["diff"] > FLAG or res["text_differs"] and i < 3:
                img = "img/%s-p%d.png" % (rid, i + 1)
                parts = []
                blank = os.path.join(tmp, "blank.png")
                for p in (ia[i] if i < len(ia) else None, ib[i] if i < len(ib) else None,
                          dpath if "missing" not in pg else None):
                    if p is None:
                        ref = ia[i] if i < len(ia) else ib[i]
                        run(["convert", ref, "-fill", "#ddd", "-colorize", "100", blank])
                        p = blank
                    parts.append(p)
                run(["montage", "-label", "", *parts, "-tile", "3x1", "-geometry", "+6+0",
                     "-background", "#888", os.path.join(out, img)])
                pg["img"] = img
            res["pages"].append(pg)
        res["max_diff"] = max((p["diff"] for p in res["pages"]), default=0.0)
    # HTML
    ha, hb = os.path.join(a_dir, rid + ".html"), os.path.join(b_dir, rid + ".html")
    if res["a"].get("html", {}).get("status") == "rendered" and \
       res["b"].get("html", {}).get("status") == "rendered":
        na, nb = html_norm(ha), html_norm(hb)
        if na and nb:
            res["html_text_differs"] = norm_text(na[0]) != norm_text(nb[0])
            res["html_tags_differ"] = na[1] != nb[1]
            sa, sb = [numbers_in(s) for s in na[2]], [numbers_in(s) for s in nb[2]]
            res["html_styles_differ"] = na[2] != nb[2]
            res["html_style_geometry_only"] = (na[2] != nb[2] and len(sa) == len(sb) and
                [re.sub(r"-?\d+(?:\.\d+)?", "#", s) for s in na[2]] ==
                [re.sub(r"-?\d+(?:\.\d+)?", "#", s) for s in nb[2]])
            if res["html_text_differs"]:
                res["html_text_diff"] = list(difflib.unified_diff(
                    na[0].replace(". ", ".\n").split("\n"), nb[0].replace(". ", ".\n").split("\n"),
                    a_label, b_label, n=0, lineterm=""))[:40]
            if res["html_styles_differ"]:
                ex = [(x, y) for x, y in zip(na[2], nb[2]) if x != y][:3]
                res["html_style_examples"] = ex
    return res


ids = sorted(set(A) | set(B))
with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
    R = list(pool.map(compare_one, ids))
subprocess.run(["rm", "-rf", os.path.join(out, "tmp")])

with open(os.path.join(out, "results.json"), "w") as f:
    json.dump(R, f, indent=1)


# ---- the verdict -------------------------------------------------------------
def failed_checks(r):
    """The checks this report fails, each with what was seen."""
    out_ = []
    for fmt in ("pdf", "html"):
        sa, sb = r["a"].get(fmt, {}).get("status", "-"), r["b"].get(fmt, {}).get("status", "-")
        if sa != sb:
            out_.append(("status", "%s %s on %s, %s on %s" % (fmt.upper(), sa, a_label, sb, b_label)))
    if r.get("pages_a") is not None and r.get("pages_b") is not None:
        if r["pages_a"] != r["pages_b"]:
            out_.append(("pages", "%s pages on %s, %s on %s" % (r["pages_a"], a_label, r["pages_b"], b_label)))
        elif r.get("rotated") or r.get("size_a") != r.get("size_b"):
            out_.append(("pages", "page %s on %s, %s on %s%s" % (r.get("size_a"), a_label, r.get("size_b"), b_label,
                                                                 " (turned)" if r.get("rotated") else "")))
    if r.get("text_differs"):
        out_.append(("text", "PDF words differ (similarity %.3f)" % r.get("text_ratio", 0)))
    if r.get("max_diff", 0) > PIXELS:
        out_.append(("pixels", "%.2f%% of a page's pixels differ" % r["max_diff"]))
    if r.get("html_text_differs"):
        out_.append(("html", "HTML words differ"))
    return out_


expected = []   # (id pattern, check, reason)
if args.expected:
    with open(args.expected) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                sys.exit("expected-differences: want id<TAB>check<TAB>reason: %r" % line)
            expected.append((parts[0], parts[1], parts[2]))


def expectation(rid, check):
    for pattern, chk, reason in expected:
        if fnmatch.fnmatchcase(rid, pattern) and (chk == check or chk == "*"):
            return (pattern, chk, reason)
    return None


unexpected, waiting, used = [], [], set()
for r in R:
    r["failed"] = []
    for check, seen in failed_checks(r):
        e = expectation(r["id"], check)
        r["failed"].append({"check": check, "seen": seen, "expected": e[2] if e else None})
        if e:
            used.add(e)
            waiting.append((r["id"], check, seen, e[2]))
        else:
            unexpected.append((r["id"], check, seen))
stale = [e for e in expected if e not in used]
with open(os.path.join(out, "verdict.txt"), "w") as f:
    f.write("%d reports; %d unexpected differences; %d expected (waiting); %d expectations no longer needed\n"
            % (len(R), len(unexpected), len(waiting), len(stale)))
    for rid, check, seen in unexpected:
        f.write("UNEXPECTED\t%s\t%s\t%s\n" % (rid, check, seen))
    for rid, check, seen, reason in waiting:
        f.write("EXPECTED\t%s\t%s\t%s\t%s\n" % (rid, check, seen, reason))
    for pattern, check, reason in stale:
        f.write("FIXED?\t%s\t%s\t%s\n" % (pattern, check, reason))


def st(r, side, fmt):
    return r[side].get(fmt, {}).get("status", "-")


def differs(r):
    return any([st(r, "a", "pdf") != st(r, "b", "pdf"), st(r, "a", "html") != st(r, "b", "html"),
                r.get("pages_a") != r.get("pages_b"), r.get("text_differs"), r.get("rotated"),
                r.get("max_diff", 0) > FLAG, r.get("html_text_differs"), r.get("html_tags_differ")])


with open(os.path.join(out, "summary.tsv"), "w") as f:
    f.write("id\tpdf_%s\tpdf_%s\thtml_%s\thtml_%s\tpages_%s\tpages_%s\ttext_diff\tmax_pixel_diff_pct\thtml_text_diff\thtml_tags_diff\thtml_styles_diff\tsecs_%s\tsecs_%s\n"
            % (a_label, b_label, a_label, b_label, a_label, b_label, a_label, b_label))
    for r in R:
        f.write("\t".join(map(str, [r["id"], st(r, "a", "pdf"), st(r, "b", "pdf"), st(r, "a", "html"),
                st(r, "b", "html"), r.get("pages_a"), r.get("pages_b"), r.get("text_differs", "-"),
                r.get("max_diff", "-"), r.get("html_text_differs", "-"), r.get("html_tags_differ", "-"),
                r.get("html_styles_differ", "-"), r["a"].get("pdf", {}).get("seconds", "-"),
                r["b"].get("pdf", {}).get("seconds", "-")])) + "\n")

# ---- HTML index ------------------------------------------------------------
E = html.escape
n = len(R)
both = sum(1 for r in R if st(r, "a", "pdf") == "rendered" and st(r, "b", "pdf") == "rendered")
ndiff = sum(1 for r in R if differs(r))


def cls(s):
    return "ok" if s == "rendered" else ("bad" if s.startswith(("crash", "hung")) else "warn")


rows = []
for r in R:
    d = differs(r)
    md = r.get("max_diff")
    rows.append(
        "<tr class='%s' data-diff='%d'><td><a href='#%s'>%s</a></td>" % ("diff" if d else "same", d, E(r["id"]), E(r["id"])) +
        "".join("<td class='%s'>%s</td>" % (cls(st(r, s, fm)), E(st(r, s, fm)))
                for fm in ("pdf", "html") for s in ("a", "b")) +
        "<td class='%s'>%s / %s%s</td>" % ("bad" if r.get("pages_a") != r.get("pages_b") or r.get("rotated") else "", r.get("pages_a"), r.get("pages_b"), " rotated" if r.get("rotated") else "") +
        "<td class='%s'>%s</td>" % ("warn" if r.get("text_differs") else "", {True: "yes", False: "no"}.get(r.get("text_differs"), "-")) +
        "<td class='num %s'>%s</td>" % ("warn" if (md or 0) > FLAG else "", "-" if md is None else "%.2f" % md) +
        "<td class='%s'>%s</td>" % ("warn" if r.get("html_text_differs") else "", {True: "yes", False: "no"}.get(r.get("html_text_differs"), "-")) +
        "<td>%s</td>" % ({True: "geometry" if r.get("html_style_geometry_only") else "yes", False: "no"}.get(r.get("html_styles_differ"), "-")) +
        "<td class='num'>%s / %s</td></tr>" % (r["a"].get("pdf", {}).get("seconds", "-"), r["b"].get("pdf", {}).get("seconds", "-")))

details = []
for r in R:
    if not differs(r):
        continue
    parts = ["<section id='%s'><h3>%s</h3><p class='path'>%s</p>" % (E(r["id"]), E(r["id"]), E(r["path"] or ""))]
    for side, lab in (("a", a_label), ("b", b_label)):
        errs = sorted(set(r[side].get("pdf", {}).get("stderr", []) + r[side].get("html", {}).get("stderr", [])))
        if errs:
            parts.append("<details><summary>%s stderr (%d lines)</summary><pre>%s</pre></details>"
                         % (E(lab), len(errs), E("\n".join(errs[:60]))))
    if r.get("text_diff"):
        parts.append("<details open><summary>PDF text diff (word similarity %.3f)</summary><pre>%s</pre></details>"
                     % (r.get("text_ratio", 0), E("\n".join(r["text_diff"]))))
    if r.get("html_text_diff"):
        parts.append("<details><summary>HTML text diff</summary><pre>%s</pre></details>" % E("\n".join(r["html_text_diff"])))
    if r.get("html_style_examples"):
        parts.append("<details><summary>HTML style differences (first 3)</summary><pre>%s</pre></details>"
                     % E("\n".join("%s\n%s\n" % (x, y) for x, y in r["html_style_examples"])))
    for pg in r.get("pages", []):
        if pg.get("img"):
            parts.append("<figure><figcaption>page %d: %.2f%% pixels differ%s%s</figcaption><img loading='lazy' src='%s'></figure>"
                         % (pg["n"], pg["diff"], (" (page size differs)" if pg.get("size_differs") else "") + (" (%s page was rotated 90 degrees: turned back for this comparison)" % b_label if pg.get("rotated") else ""),
                            " (missing on %s)" % pg["missing"] if pg.get("missing") else "", E(pg["img"])))
    parts.append("</section>")
    details.append("".join(parts))

designer = read(os.path.join(out, "designer.html"))
top = read(os.path.join(out, "top.html"))   # optional hand-written summary and triage
top += "<h2>Verdict</h2><p>%d unexpected differences, %d expected (waiting on a fix), %d expectations no longer needed.</p>" % (
    len(unexpected), len(waiting), len(stale))
if unexpected:
    top += "<h3>Unexpected</h3><table><tr><th>report</th><th>check</th><th>seen</th></tr>%s</table>" % "".join(
        "<tr class='bad'><td><a href='#%s'>%s</a></td><td>%s</td><td>%s</td></tr>" % (E(i), E(i), E(c), E(w)) for i, c, w in unexpected)
if waiting:
    top += "<h3>Expected, and why</h3><table><tr><th>report</th><th>check</th><th>seen</th><th>waiting on</th></tr>%s</table>" % "".join(
        "<tr class='warn'><td><a href='#%s'>%s</a></td><td>%s</td><td>%s</td><td>%s</td></tr>" % (E(i), E(i), E(c), E(w), E(why))
        for i, c, w, why in waiting)
if stale:
    top += "<h3>Listed, but no longer different</h3><table><tr><th>report</th><th>check</th><th>was waiting on</th></tr>%s</table>" % "".join(
        "<tr class='ok'><td>%s</td><td>%s</td><td>%s</td></tr>" % (E(i), E(c), E(why)) for i, c, why in stale)

page = """<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>RDLKit cross-platform</title><style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#d2d2d7;--ok:#e8f5e9;--warn:#fff4d6;--bad:#fde2e1;--head:#f5f5f7}
@media (prefers-color-scheme: dark){:root:not([data-theme=light]){--bg:#1c1c1e;--fg:#f2f2f7;--mut:#a1a1a6;--line:#3a3a3c;--ok:#1f3a24;--warn:#4a3b12;--bad:#4d1f1f;--head:#2c2c2e}}
body{background:var(--bg);color:var(--fg);font:14px/1.4 -apple-system,system-ui,sans-serif;margin:0;padding:16px}
table{border-collapse:collapse;font-size:12px}td,th{border:1px solid var(--line);padding:2px 6px;white-space:nowrap}
th{background:var(--head);position:sticky;top:0}.num{text-align:right}
.ok{background:var(--ok)}.warn{background:var(--warn)}.bad{background:var(--bad)}
.path{color:var(--mut);font-size:12px}pre{font-size:11px;overflow:auto;max-height:24em;background:var(--head);padding:6px}
figure{margin:8px 0}figure img{max-width:100%%;border:1px solid var(--line)}figcaption{font-size:12px;color:var(--mut)}
section{border-top:2px solid var(--line);margin-top:16px}.wrap{overflow-x:auto}
</style></head><body>
<h1>RDLKit: %s vs %s</h1>
%s
<p>%d reports; %d rendered PDF on both; %d differ in some way. Images: %s | %s | difference (red), %d dpi, fuzz %s, flagged above %.2f%% of pixels.</p>
<p><label><input type=checkbox id=only onchange="document.querySelectorAll('tr.same').forEach(t=>t.hidden=this.checked)"> only differing reports</label></p>
<div class=wrap id=summary><table><tr><th>report</th><th>PDF %s</th><th>PDF %s</th><th>HTML %s</th><th>HTML %s</th><th>pages</th><th>PDF text differs</th><th>max pixel diff %%</th><th>HTML text differs</th><th>HTML styles differ</th><th>PDF secs</th></tr>
%s</table></div>
<h2 id='reports'>Differences, report by report</h2>%s
%s
</body></html>""" % (E(a_label), E(b_label), top, n, both, ndiff, E(a_label), E(b_label), DPI, FUZZ, FLAG,
                     E(a_label), E(b_label), E(a_label), E(b_label), "\n".join(rows), "\n".join(details), designer)
with open(os.path.join(out, "index.html"), "w") as f:
    f.write(page)
print("%d reports, %d rendered PDF on both, %d differ" % (n, both, ndiff))
print(read(os.path.join(out, "verdict.txt")))
sys.exit(1 if unexpected else 0)
