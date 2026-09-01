#import "RDLBackend.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"
#import <math.h>

static NSString *PicaHTMLEsc(NSString *s) {
  if (s == nil)
    return @"";
  NSMutableString *o = [s mutableCopy];
  [o replaceOccurrencesOfString:@"&"
                     withString:[@"&" stringByAppendingString:@"amp;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  [o replaceOccurrencesOfString:@"<"
                     withString:[@"&" stringByAppendingString:@"lt;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  [o replaceOccurrencesOfString:@">"
                     withString:[@"&" stringByAppendingString:@"gt;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  [o replaceOccurrencesOfString:@"\""
                     withString:[@"&" stringByAppendingString:@"quot;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  return o;
}

static NSString *PicaCSSAlign(NSString *a) {
  if ([a isEqualToString:@"Center"])
    return @"center";
  if ([a isEqualToString:@"Right"])
    return @"right";
  return @"left";
}

static NSString *PicaCSSBorderStyle(NSString *s) {
  if ([s isEqualToString:@"Dashed"])
    return @"dashed";
  if ([s isEqualToString:@"Dotted"])
    return @"dotted";
  if ([s isEqualToString:@"Double"])
    return @"double";
  return @"solid";
}

static void PicaAppendCSSBorder(NSMutableString *st, NSString *side, RDLBorder *b, RDLBorder *fallback) {
  RDLBorder *use = (b && [b.style length] && ![b.style isEqualToString:@"None"]) ? b : fallback;
  if (use == nil || [use.style length] == 0 || [use.style isEqualToString:@"None"])
    return;
  [st appendFormat:@"border-%@:%@ %@ %@;", side, use.width.length ? use.width : @"1pt",
                   PicaCSSBorderStyle(use.style), use.color.length ? use.color : @"#1a1916"];
}

static void PicaAppendCSSBox(NSMutableString *st, RDLStyle *s) {
  if (s == nil)
    return;
  if (s.backgroundColor.length && ![s.backgroundColor isEqualToString:@"Transparent"])
    [st appendFormat:@"background:%@;", s.backgroundColor];
  RDLBorder *all = (s.border && [s.border.style length] && ![s.border.style isEqualToString:@"None"])
                       ? s.border
                       : nil;
  PicaAppendCSSBorder(st, @"top", s.borderTop, all);
  PicaAppendCSSBorder(st, @"bottom", s.borderBottom, all);
  PicaAppendCSSBorder(st, @"left", s.borderLeft, all);
  PicaAppendCSSBorder(st, @"right", s.borderRight, all);
}

static void PicaAppendCSSPadding(NSMutableString *st, RDLStyle *s) {
  if (s == nil)
    return;
  [st appendFormat:@"padding:%@ %@ %@ %@;", s.paddingTop.length ? s.paddingTop : @"0",
                   s.paddingRight.length ? s.paddingRight : @"0",
                   s.paddingBottom.length ? s.paddingBottom : @"0",
                   s.paddingLeft.length ? s.paddingLeft : @"0"];
}

static NSString *PicaCSSTextDecoration(NSString *d) {
  if ([d isEqualToString:@"Underline"])
    return @"underline";
  if ([d isEqualToString:@"LineThrough"])
    return @"line-through";
  if ([d isEqualToString:@"Overline"])
    return @"overline";
  return nil;
}

static NSString *PicaChartSVG(RDLLaidOutItem *it) {
  NSUInteger n = [it.values count];
  NSMutableString *svg = [NSMutableString string];
  CGFloat W = 400, H = 300;
  [svg appendFormat:@"<svg viewBox=\"0 0 %.0f %.0f\" width=\"100%%\" height=\"100%%\" "
                    @"preserveAspectRatio=\"none\" xmlns=\"http://www.w3.org/2000/svg\">",
                    W, H];
  double max = 1, total = 0;
  for (NSNumber *v in it.values) {
    if ([v doubleValue] > max)
      max = [v doubleValue];
    total += fabs([v doubleValue]);
  }
  NSString *type = [it.chartType lowercaseString] ?: @"column";
  NSString *ink = @"#1a1916";
  if (n && [type isEqualToString:@"pie"]) {
    double cx = W / 2, cy = H / 2, r = MIN(W, H) * 0.42;
    double angle = -M_PI_2;
    for (NSUInteger i = 0; i < n; i++) {
      double frac = total > 0 ? fabs([it.values[i] doubleValue]) / total : 1.0 / n;
      double a2 = angle + frac * 2 * M_PI;
      double x1 = cx + r * cos(angle), y1 = cy + r * sin(angle);
      double x2 = cx + r * cos(a2), y2 = cy + r * sin(a2);
      int large = (a2 - angle) > M_PI ? 1 : 0;
      double shade = 0.25 + 0.6 * ((double)i / MAX(n, 1));
      [svg appendFormat:@"<path d=\"M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 %d 1 %.1f %.1f Z\" "
                        @"fill=\"rgba(26,25,22,%.2f)\" stroke=\"#f6f1e8\"/>",
                        cx, cy, x1, y1, r, r, large, x2, y2, shade];
      angle = a2;
    }
  } else if (n && [type isEqualToString:@"line"]) {
    [svg appendString:@"<polyline fill=\"none\" stroke=\"#1a1916\" stroke-width=\"3\" points=\""];
    for (NSUInteger i = 0; i < n; i++) {
      double x = n > 1 ? (W - 20) * i / (n - 1) + 10 : W / 2;
      double y = H - 10 - ([it.values[i] doubleValue] / max) * (H - 20);
      [svg appendFormat:@"%.1f,%.1f ", x, y];
    }
    [svg appendString:@"\"/>"];
  } else if (n && [type isEqualToString:@"bar"]) {
    CGFloat gap = (H - 20) / n;
    for (NSUInteger i = 0; i < n; i++) {
      double w = ([it.values[i] doubleValue] / max) * (W - 20);
      [svg appendFormat:@"<rect x=\"10\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" fill=\"%@\"/>",
                        10 + i * gap + gap * 0.15, w, gap * 0.7, ink];
    }
  } else if (n) {
    CGFloat gap = (W - 20) / n;
    for (NSUInteger i = 0; i < n; i++) {
      double h = ([it.values[i] doubleValue] / max) * (H - 20);
      [svg appendFormat:@"<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" fill=\"%@\"/>",
                        10 + i * gap + gap * 0.2, H - 10 - h, gap * 0.6, h, ink];
    }
  }
  [svg appendString:@"</svg>"];
  return svg;
}

@implementation RDLHTMLBackend

- (NSString *)name {
  return @"HTML";
}

- (NSString *)pathExtension {
  return @"html";
}

- (NSData *)renderPages:(NSArray<RDLLaidOutPage *> *)pages title:(NSString *)title {
  NSString *html = [RDLHTMLBackend HTMLStringForPages:pages title:title];
  return [html dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)HTMLStringForPages:(NSArray<RDLLaidOutPage *> *)pages title:(NSString *)title {
  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!DOCTYPE html>\n"];
  [html appendString:@"<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"];
  [html appendFormat:@"<title>%@</title>\n", PicaHTMLEsc(title ?: @"Report")];
  [html appendString:@"<style>\n"];
  [html appendString:@"body{margin:0;background:#cfc6b6;color:#1a1916;"
                     @"font-family:Georgia,serif;}\n"];
  [html appendString:@".pica-page{position:relative;background:#f6f1e8;margin:24px auto;"
                     @"box-shadow:0 8px 24px rgba(0,0,0,.18);overflow:hidden;}\n"];
  [html appendString:@".pica-item{position:absolute;overflow:hidden;box-sizing:border-box;"
                     @"white-space:pre-wrap;}\n"];
  [html appendString:@".pica-bar{position:absolute;bottom:0;background:#1a1916;}\n"];
  [html appendString:@"@media print{body{background:#fff;}.pica-page{box-shadow:none;"
                     @"margin:0;page-break-after:always;}}\n"];
  [html appendString:@"</style>\n</head>\n"];
  [html appendString:@"<body data-pica-backend=\"html\">\n"];
  NSInteger i = 0;
  for (RDLLaidOutPage *page in pages) {
    i += 1;
    [html appendFormat:@"<section class=\"pica-page\" data-page=\"%ld\" "
                       @"style=\"width:%.4fin;height:%.4fin;\">\n",
                       (long)i, page.width, page.height];
    for (RDLLaidOutItem *it in page.items) {
      NSMutableString *st = [NSMutableString string];
      [st appendFormat:@"left:%.4fin;top:%.4fin;width:%.4fin;height:%.4fin;",
                       it.x, it.y, it.w, it.h];
      NSString *color = it.style.color.length ? it.style.color : @"#1a1916";
      NSString *ff = it.style.fontFamily.length ? it.style.fontFamily : @"Georgia";
      NSString *fs = it.style.fontSize.length ? it.style.fontSize : @"10pt";
      NSString *fw = [it.style.fontWeight isEqualToString:@"Bold"] ? @"700" : @"400";
      [st appendFormat:@"color:%@;font-family:%@;font-size:%@;font-weight:%@;text-align:%@;",
                       color, ff, fs, fw, PicaCSSAlign(it.style.textAlign)];
      if ([it.style.fontStyle isEqualToString:@"Italic"])
        [st appendString:@"font-style:italic;"];
      NSString *deco = PicaCSSTextDecoration(it.style.textDecoration);
      if (deco)
        [st appendFormat:@"text-decoration:%@;", deco];
      if ([it.kind isEqualToString:@"Line"]) {
        // General line: SVG so vertical and sloped lines work too.
        RDLBorder *b = it.style.border;
        NSString *lw = (b && b.width.length) ? b.width : @"1pt";
        NSString *dash = @"";
        if ([b.style isEqualToString:@"Dashed"])
          dash = @" stroke-dasharray=\"6,4\"";
        else if ([b.style isEqualToString:@"Dotted"])
          dash = @" stroke-dasharray=\"2,3\"";
        NSString *lc = (b && b.color.length) ? b.color : color;
        lc = PicaHTMLEsc(lc);
        lw = PicaHTMLEsc(lw);
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Line\" style=\"%@\">", PicaHTMLEsc(st)];
        if (it.h < 0.001) {
          [html appendFormat:@"<svg width=\"100%%\" height=\"2\" style=\"overflow:visible;\">"
                             @"<line x1=\"0\" y1=\"1\" x2=\"100%%\" y2=\"1\" stroke=\"%@\" "
                             @"stroke-width=\"%@\"%@/></svg>",
                             lc, lw, dash];
        } else if (it.w < 0.001) {
          [html appendFormat:@"<svg width=\"2\" height=\"100%%\" style=\"overflow:visible;\">"
                             @"<line x1=\"1\" y1=\"0\" x2=\"1\" y2=\"100%%\" stroke=\"%@\" "
                             @"stroke-width=\"%@\"%@/></svg>",
                             lc, lw, dash];
        } else {
          [html appendFormat:@"<svg width=\"100%%\" height=\"100%%\" preserveAspectRatio=\"none\" "
                             @"viewBox=\"0 0 100 100\"><line x1=\"0\" y1=\"0\" x2=\"100\" y2=\"100\" "
                             @"vector-effect=\"non-scaling-stroke\" stroke=\"%@\" stroke-width=\"%@\"%@/>"
                             @"</svg>",
                             lc, lw, dash];
        }
        [html appendString:@"</div>\n"];
        continue;
      }
      PicaAppendCSSBox(st, it.style);
      if ([it.kind isEqualToString:@"Rectangle"]) {
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Rectangle\" style=\"%@\"></div>\n", PicaHTMLEsc(st)];
        continue;
      }
      if ([it.kind isEqualToString:@"Image"]) {
        NSString *src = nil;
        if ([it.imageData length]) {
          src = [NSString stringWithFormat:@"data:%@;base64,%@",
                                           it.imageMIME.length ? it.imageMIME : @"image/png",
                                           [it.imageData base64EncodedStringWithOptions:0]];
        } else if ([it.imageSrc length]) {
          src = it.imageSrc;
        }
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Image\" style=\"%@\">", PicaHTMLEsc(st)];
        if (src) {
          NSString *fit = @"contain";
          NSString *sizing = it.sizing ?: @"Fit";
          if ([sizing isEqualToString:@"Fit"])
            fit = @"fill";
          else if ([sizing isEqualToString:@"Clip"])
            fit = @"none";
          else if ([sizing isEqualToString:@"AutoSize"])
            fit = @"none";
          NSString *img = [NSString
              stringWithFormat:@"<img src=\"%@\" alt=\"%@\" "
                               @"style=\"width:100%%;height:100%%;object-fit:%@;object-position:0 0;\">",
                               PicaHTMLEsc(src), PicaHTMLEsc(it.name ?: @""), fit];
          if ([it.hyperlink length])
            [html appendFormat:@"<a href=\"%@\">%@</a>", PicaHTMLEsc(it.hyperlink), img];
          else
            [html appendString:img];
        }
        [html appendString:@"</div>\n"];
        continue;
      }
      if ([it.kind isEqualToString:@"Chart"]) {
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Chart\" style=\"%@\">", PicaHTMLEsc(st)];
        [html appendString:PicaChartSVG(it)];
        [html appendString:@"</div>\n"];
        continue;
      }
      // Textbox
      PicaAppendCSSPadding(st, it.style);
      NSString *va = it.style.verticalAlign;
      if ([va isEqualToString:@"Middle"])
        [st appendString:@"display:flex;flex-direction:column;justify-content:center;"];
      else if ([va isEqualToString:@"Bottom"])
        [st appendString:@"display:flex;flex-direction:column;justify-content:flex-end;"];
      NSString *body;
      if ([it.spans count]) {
        // Rich text: one div per paragraph, one span per styled run.
        NSMutableString *rich = [NSMutableString string];
        for (RDLParagraph *para in it.spans) {
          if ([para.style.textAlign length])
            [rich appendFormat:@"<div style=\"text-align:%@;\">",
                               PicaCSSAlign(para.style.textAlign)];
          else
            [rich appendString:@"<div>"];
          for (RDLTextRun *run in para.runs) {
            NSMutableString *rs = [NSMutableString string];
            RDLStyle *s = run.style;
            if ([s.color length])
              [rs appendFormat:@"color:%@;", s.color];
            if ([s.fontFamily length])
              [rs appendFormat:@"font-family:%@;", s.fontFamily];
            if ([s.fontSize length])
              [rs appendFormat:@"font-size:%@;", s.fontSize];
            if ([s.fontWeight length])
              [rs appendFormat:@"font-weight:%@;",
                               [s.fontWeight isEqualToString:@"Bold"] ? @"700" : @"400"];
            if ([s.fontStyle isEqualToString:@"Italic"])
              [rs appendString:@"font-style:italic;"];
            NSString *rdeco = PicaCSSTextDecoration(s.textDecoration);
            if (rdeco)
              [rs appendFormat:@"text-decoration:%@;", rdeco];
            if ([rs length])
              [rich appendFormat:@"<span style=\"%@\">%@</span>", PicaHTMLEsc(rs),
                                 PicaHTMLEsc(run.value ?: @"")];
            else
              [rich appendString:PicaHTMLEsc(run.value ?: @"")];
          }
          [rich appendString:@"</div>"];
        }
        body = rich;
      } else {
        body = PicaHTMLEsc(it.text ?: @"");
      }
      if ([it.hyperlink length])
        body = [NSString stringWithFormat:@"<a href=\"%@\" style=\"color:inherit;\">%@</a>",
                                          PicaHTMLEsc(it.hyperlink), body];
      [html appendFormat:@"<div class=\"pica-item\" data-kind=\"%@\" style=\"%@\">%@</div>\n",
                         PicaHTMLEsc(it.kind ?: @"Textbox"), PicaHTMLEsc(st), body];
    }
    [html appendString:@"</section>\n"];
  }
  [html appendString:@"</body>\n</html>\n"];
  return html;
}

@end
