#import "RDLBackend.h"
#import "RDLReport.h"
#import "RDLChartRenderer.h"
#import "RDLCompatibility.h"
#import <math.h>

static NSString *RDLHTMLEsc(NSString *s) {
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

static NSString *RDLCSSAlign(RDLTextAlign a) {
  if (a == RDLTextAlignCenter)
    return @"center";
  if (a == RDLTextAlignRight)
    return @"right";
  if (a == RDLTextAlignJustify)
    return @"justify";
  return @"left";
}

static NSString *RDLCSSBorderStyle(RDLBorderStyle s) {
  if (s == RDLBorderStyleDashed)
    return @"dashed";
  if (s == RDLBorderStyleDotted)
    return @"dotted";
  if (s == RDLBorderStyleDouble)
    return @"double";
  return @"solid";
}

static void RDLAppendCSSBorder(NSMutableString *st, NSString *side, RDLBorder *b, RDLBorder *fallback) {
  RDLBorder *use = (b && b.style != RDLBorderStyleUnspecified &&
                    b.style != RDLBorderStyleNone) ? b : fallback;
  if (use == nil || use.style == RDLBorderStyleUnspecified || use.style == RDLBorderStyleNone)
    return;
  [st appendFormat:@"border-%@:%@ %@ %@;", side, [use.width stringValue] ?: @"1pt",
                   RDLCSSBorderStyle(use.style), use.color.length ? use.color : @"#1a1916"];
}

static void RDLAppendCSSBox(NSMutableString *st, RDLStyle *s) {
  if (s == nil)
    return;
  if (!RDLColorIsTransparent(s.backgroundColor))
    [st appendFormat:@"background:%@;", s.backgroundColor];
  RDLBorder *all = (s.border && s.border.style != RDLBorderStyleUnspecified && s.border.style != RDLBorderStyleNone)
                       ? s.border
                       : nil;
  RDLAppendCSSBorder(st, @"top", s.borderTop, all);
  RDLAppendCSSBorder(st, @"bottom", s.borderBottom, all);
  RDLAppendCSSBorder(st, @"left", s.borderLeft, all);
  RDLAppendCSSBorder(st, @"right", s.borderRight, all);
}

static void RDLAppendCSSPadding(NSMutableString *st, RDLStyle *s) {
  if (s == nil)
    return;
  [st appendFormat:@"padding:%@ %@ %@ %@;", [s.paddingTop stringValue] ?: @"0",
                   [s.paddingRight stringValue] ?: @"0",
                   [s.paddingBottom stringValue] ?: @"0",
                   [s.paddingLeft stringValue] ?: @"0"];
}

static NSString *RDLCSSTextDecoration(RDLTextDecoration d) {
  if (d == RDLTextDecorationUnderline)
    return @"underline";
  if (d == RDLTextDecorationLineThrough)
    return @"line-through";
  if (d == RDLTextDecorationOverline)
    return @"overline";
  return nil;
}

// The geometry comes from RDLChartRenderer, shared with the PDF backend and
// the designer canvas, so all three draw the same chart. This only has to turn
// shapes into SVG.
static NSString *RDLSVGEsc(NSString *s) {
  NSMutableString *o = [s mutableCopy] ?: [NSMutableString string];
  [o replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [o length])];
  [o replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [o length])];
  [o replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [o length])];
  return o;
}

// Degrees clockwise from twelve, to a point on the circle.
static NSPoint RDLWedgePoint(NSRect r, CGFloat degrees, CGFloat radius) {
  CGFloat a = degrees * (CGFloat)M_PI / 180.0f;
  return NSMakePoint(NSMidX(r) + sinf(a) * radius, NSMidY(r) - cosf(a) * radius);
}

static NSString *RDLChartSVG(RDLLaidOutChart *it) {
  CGFloat W = MAX(it.w, 0.01) * 96.0, H = MAX(it.h, 0.01) * 96.0;
  NSArray<RDLChartShape *> *shapes =
      [RDLChartRenderer shapesForChart:it inRect:NSMakeRect(0, 0, W, H)];
  NSMutableString *svg = [NSMutableString string];
  [svg appendFormat:@"<svg viewBox=\"0 0 %.2f %.2f\" width=\"100%%\" height=\"100%%\" "
                    @"xmlns=\"http://www.w3.org/2000/svg\">",
                    W, H];
  for (RDLChartShape *sh in shapes) {
    NSString *fill = sh.fill ?: @"none";
    NSString *stroke = sh.stroke ?: @"none";
    NSString *op = sh.opacity < 1 ? [NSString stringWithFormat:@" opacity=\"%.2f\"", sh.opacity] : @"";
    switch (sh.kind) {
    case RDLChartShapeRect:
      [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" "
                        @"fill=\"%@\"%@/>",
                        sh.rect.origin.x, sh.rect.origin.y, sh.rect.size.width, sh.rect.size.height,
                        fill, op];
      break;
    case RDLChartShapeEllipse:
      [svg appendFormat:@"<ellipse cx=\"%.2f\" cy=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" "
                        @"fill=\"%@\"%@/>",
                        NSMidX(sh.rect), NSMidY(sh.rect), sh.rect.size.width / 2,
                        sh.rect.size.height / 2, fill, op];
      break;
    case RDLChartShapeLine: {
      NSPoint a = [sh.points[0] pointValue];
      NSPoint b = [sh.points[1] pointValue];
      [svg appendFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" "
                        @"stroke=\"%@\" stroke-width=\"%.2f\"/>",
                        a.x, a.y, b.x, b.y, stroke, sh.lineWidth];
      break;
    }
    case RDLChartShapePolyline:
    case RDLChartShapePolygon: {
      NSMutableString *pts = [NSMutableString string];
      for (NSValue *v in sh.points) {
        NSPoint p = [v pointValue];
        [pts appendFormat:@"%.2f,%.2f ", p.x, p.y];
      }
      [svg appendFormat:@"<%@ points=\"%@\" fill=\"%@\" stroke=\"%@\" stroke-width=\"%.2f\" "
                        @"stroke-linejoin=\"round\"%@/>",
                        sh.kind == RDLChartShapePolygon ? @"polygon" : @"polyline", pts,
                        sh.kind == RDLChartShapePolygon ? fill : @"none",
                        sh.kind == RDLChartShapePolygon ? @"none" : stroke, sh.lineWidth, op];
      break;
    }
    case RDLChartShapeWedge: {
      CGFloat outer = sh.rect.size.width / 2;
      NSPoint p1 = RDLWedgePoint(sh.rect, sh.startAngle, outer);
      NSPoint p2 = RDLWedgePoint(sh.rect, sh.endAngle, outer);
      int large = (sh.endAngle - sh.startAngle) > 180 ? 1 : 0;
      if (sh.innerRadius > 0) {
        NSPoint q1 = RDLWedgePoint(sh.rect, sh.endAngle, sh.innerRadius);
        NSPoint q2 = RDLWedgePoint(sh.rect, sh.startAngle, sh.innerRadius);
        [svg appendFormat:@"<path d=\"M%.2f %.2f A%.2f %.2f 0 %d 1 %.2f %.2f L%.2f %.2f "
                          @"A%.2f %.2f 0 %d 0 %.2f %.2f Z\" fill=\"%@\" stroke=\"%@\"/>",
                          p1.x, p1.y, outer, outer, large, p2.x, p2.y, q1.x, q1.y, sh.innerRadius,
                          sh.innerRadius, large, q2.x, q2.y, fill, stroke];
      } else {
        [svg appendFormat:@"<path d=\"M%.2f %.2f L%.2f %.2f A%.2f %.2f 0 %d 1 %.2f %.2f Z\" "
                          @"fill=\"%@\" stroke=\"%@\"/>",
                          NSMidX(sh.rect), NSMidY(sh.rect), p1.x, p1.y, outer, outer,
                          large, p2.x, p2.y, fill, stroke];
      }
      break;
    }
    case RDLChartShapeText: {
      NSString *anchor = sh.anchor == RDLChartTextAnchorMiddle
                             ? @"middle"
                             : (sh.anchor == RDLChartTextAnchorEnd ? @"end" : @"start");
      NSString *transform =
          sh.rotation != 0
              ? [NSString stringWithFormat:@" transform=\"rotate(%.1f %.2f %.2f)\"", -sh.rotation,
                                           sh.rect.origin.x, sh.rect.origin.y]
              : @"";
      [svg appendFormat:@"<text x=\"%.2f\" y=\"%.2f\" text-anchor=\"%@\" font-size=\"%.2f\" "
                        @"font-family=\"Helvetica,Arial,sans-serif\"%@ fill=\"%@\"%@>%@</text>",
                        sh.rect.origin.x, sh.rect.origin.y, anchor, sh.fontSize,
                        sh.bold ? @" font-weight=\"bold\"" : @"", fill, transform,
                        RDLSVGEsc(sh.text)];
      break;
    }
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
  [html appendFormat:@"<title>%@</title>\n", RDLHTMLEsc(title ?: @"Report")];
  [html appendString:@"<style>\n"];
  [html appendString:@"body{margin:0;background:#cfc6b6;color:#1a1916;"
                     @"font-family:Georgia,serif;}\n"];
  [html appendString:@".rdl-page{position:relative;background:#f6f1e8;margin:24px auto;"
                     @"box-shadow:0 8px 24px rgba(0,0,0,.18);overflow:hidden;}\n"];
  [html appendString:@".rdl-item{position:absolute;overflow:hidden;box-sizing:border-box;"
                     @"white-space:pre-wrap;}\n"];
  [html appendString:@".rdl-bar{position:absolute;bottom:0;background:#1a1916;}\n"];
  [html appendString:@"@media print{body{background:#fff;}.rdl-page{box-shadow:none;"
                     @"margin:0;page-break-after:always;}}\n"];
  [html appendString:@"</style>\n</head>\n"];
  [html appendString:@"<body data-rdl-backend=\"html\">\n"];
  NSInteger i = 0;
  for (RDLLaidOutPage *page in pages) {
    i += 1;
    [html appendFormat:@"<section class=\"rdl-page\" data-page=\"%ld\" "
                       @"style=\"width:%.4fin;height:%.4fin;\">\n",
                       (long)i, page.width, page.height];
    for (RDLLaidOutItem *it in page.items) {
      NSMutableString *st = [NSMutableString string];
      [st appendFormat:@"left:%.4fin;top:%.4fin;width:%.4fin;height:%.4fin;",
                       it.x, it.y, it.w, it.h];
      NSString *color = it.style.color.length ? it.style.color : @"#1a1916";
      NSString *ff = it.style.fontFamily.length ? it.style.fontFamily : @"Georgia";
      NSString *fs = [it.style.fontSize stringValue] ?: @"10pt";
      NSString *fw = RDLFontWeightIsBold(it.style.fontWeight) ? @"700" : @"400";
      [st appendFormat:@"color:%@;font-family:%@;font-size:%@;font-weight:%@;text-align:%@;",
                       color, ff, fs, fw, RDLCSSAlign(it.style.textAlign)];
      if (it.style.fontStyle == RDLFontStyleItalic)
        [st appendString:@"font-style:italic;"];
      NSString *deco = RDLCSSTextDecoration(it.style.textDecoration);
      if (deco)
        [st appendFormat:@"text-decoration:%@;", deco];
      if ([it isKindOfClass:[RDLLaidOutLine class]]) {
        // General line: SVG so vertical and sloped lines work too.
        RDLBorder *b = it.style.border;
        NSString *lw = [b.width stringValue] ?: @"1pt";
        NSString *dash = @"";
        if (b.style == RDLBorderStyleDashed)
          dash = @" stroke-dasharray=\"6,4\"";
        else if (b.style == RDLBorderStyleDotted)
          dash = @" stroke-dasharray=\"2,3\"";
        NSString *lc = (b && b.color.length) ? b.color : color;
        lc = RDLHTMLEsc(lc);
        lw = RDLHTMLEsc(lw);
        [html appendFormat:@"<div class=\"rdl-item\" data-kind=\"Line\" style=\"%@\">", RDLHTMLEsc(st)];
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
      RDLAppendCSSBox(st, it.style);
      if ([it isKindOfClass:[RDLLaidOutRectangle class]]) {
        [html appendFormat:@"<div class=\"rdl-item\" data-kind=\"Rectangle\" style=\"%@\"></div>\n", RDLHTMLEsc(st)];
        continue;
      }
      if ([it isKindOfClass:[RDLLaidOutImage class]]) {
        RDLLaidOutImage *img = (RDLLaidOutImage *)it;
        NSString *src = nil;
        if ([img.imageData length]) {
          src = [NSString stringWithFormat:@"data:%@;base64,%@",
                                           img.imageMIME.length ? img.imageMIME : @"image/png",
                                           [img.imageData base64EncodedStringWithOptions:0]];
        } else if ([img.imageSrc length]) {
          src = img.imageSrc;
        }
        [html appendFormat:@"<div class=\"rdl-item\" data-kind=\"Image\" style=\"%@\">", RDLHTMLEsc(st)];
        if (src) {
          NSString *fit = @"contain";
          RDLImageSizing sizing = img.sizing != RDLImageSizingUnspecified ? img.sizing : RDLImageSizingFit;
          if (sizing == RDLImageSizingFit)
            fit = @"fill";
          else if (sizing == RDLImageSizingClip)
            fit = @"none";
          else if (sizing == RDLImageSizingAutoSize)
            fit = @"none";
          NSString *img = [NSString
              stringWithFormat:@"<img src=\"%@\" alt=\"%@\" "
                               @"style=\"width:100%%;height:100%%;object-fit:%@;object-position:0 0;\">",
                               RDLHTMLEsc(src), RDLHTMLEsc(it.name ?: @""), fit];
          if ([it.hyperlink length])
            [html appendFormat:@"<a href=\"%@\">%@</a>", RDLHTMLEsc(it.hyperlink), img];
          else
            [html appendString:img];
        }
        [html appendString:@"</div>\n"];
        continue;
      }
      if ([it isKindOfClass:[RDLLaidOutChart class]]) {
        [html appendFormat:@"<div class=\"rdl-item\" data-kind=\"Chart\" style=\"%@\">", RDLHTMLEsc(st)];
        [html appendString:RDLChartSVG((RDLLaidOutChart *)it)];
        [html appendString:@"</div>\n"];
        continue;
      }
      // Textbox
      RDLLaidOutTextbox *tb = (RDLLaidOutTextbox *)it;
      RDLAppendCSSPadding(st, it.style);
      RDLVerticalAlign va = it.style.verticalAlign;
      if (va == RDLVerticalAlignMiddle)
        [st appendString:@"display:flex;flex-direction:column;justify-content:center;"];
      else if (va == RDLVerticalAlignBottom)
        [st appendString:@"display:flex;flex-direction:column;justify-content:flex-end;"];
      NSString *body;
      if ([tb.spans count]) {
        // Rich text: one div per paragraph, one span per styled run.
        NSMutableString *rich = [NSMutableString string];
        for (RDLParagraph *para in tb.spans) {
          if (para.style.textAlign != RDLTextAlignUnspecified)
            [rich appendFormat:@"<div style=\"text-align:%@;\">",
                               RDLCSSAlign(para.style.textAlign)];
          else
            [rich appendString:@"<div>"];
          for (RDLTextRun *run in para.runs) {
            NSMutableString *rs = [NSMutableString string];
            RDLStyle *s = run.style;
            if ([s.color length])
              [rs appendFormat:@"color:%@;", s.color];
            if ([s.fontFamily length])
              [rs appendFormat:@"font-family:%@;", s.fontFamily];
            if (s.fontSize)
              [rs appendFormat:@"font-size:%@;", [s.fontSize stringValue]];
            if (s.fontWeight != RDLFontWeightUnspecified)
              [rs appendFormat:@"font-weight:%@;",
                               s.fontWeight == RDLFontWeightBold ? @"700" : @"400"];
            if (s.fontStyle == RDLFontStyleItalic)
              [rs appendString:@"font-style:italic;"];
            NSString *rdeco = RDLCSSTextDecoration(s.textDecoration);
            if (rdeco)
              [rs appendFormat:@"text-decoration:%@;", rdeco];
            if ([rs length])
              [rich appendFormat:@"<span style=\"%@\">%@</span>", RDLHTMLEsc(rs),
                                 RDLHTMLEsc(run.value ?: @"")];
            else
              [rich appendString:RDLHTMLEsc(run.value ?: @"")];
          }
          [rich appendString:@"</div>"];
        }
        body = rich;
      } else {
        body = RDLHTMLEsc(tb.text ?: @"");
      }
      if ([it.hyperlink length])
        body = [NSString stringWithFormat:@"<a href=\"%@\" style=\"color:inherit;\">%@</a>",
                                          RDLHTMLEsc(it.hyperlink), body];
      [html appendFormat:@"<div class=\"rdl-item\" data-kind=\"%@\" style=\"%@\">%@</div>\n",
                         RDLHTMLEsc(it.rdlElementName ?: @"Textbox"), RDLHTMLEsc(st), body];
    }
    [html appendString:@"</section>\n"];
  }
  [html appendString:@"</body>\n</html>\n"];
  return html;
}

@end
