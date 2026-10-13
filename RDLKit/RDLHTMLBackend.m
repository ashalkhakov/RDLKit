#import "RDLBackend.h"
#import "RDLReport.h"
#import "RDLChartRenderer.h"
#import "RDLCompatibility.h"
#import <math.h>
#import "RDLTextAttributes.h"

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

// An RDL colour as CSS: #rrggbb, or rgba() when it is not opaque -- CSS reads
// #aarrggbb's alpha from the end, so the text cannot be passed through. Names
// resolve to their value. `fallback` stands in for what is not a colour.
static NSString *RDLCSSColor(NSString *color, NSString *fallback) {
  if (RDLColorIsTransparent(color))
    return fallback;
  CGFloat r = 0, g = 0, b = 0, a = 1;
  if (!RDLColorComponents(color, &r, &g, &b, &a))
    return fallback;
  int ri = (int)round(r * 255), gi = (int)round(g * 255), bi = (int)round(b * 255);
  if (a < 0.999)
    return [NSString stringWithFormat:@"rgba(%d,%d,%d,%.3g)", ri, gi, bi, a];
  return [NSString stringWithFormat:@"#%02x%02x%02x", ri, gi, bi];
}

static NSString *RDLCSSBorderStyle(RDLBorderStyle s) {
  if (s == RDLBorderStyleDashed)
    return @"dashed";
  if (s == RDLBorderStyleDotted)
    return @"dotted";
  if (s == RDLBorderStyleDouble)
    return @"double";
  if (s == RDLBorderStyleGroove)
    return @"groove";
  if (s == RDLBorderStyleRidge)
    return @"ridge";
  if (s == RDLBorderStyleInset || s == RDLBorderStyleWindowInset)
    return @"inset";
  if (s == RDLBorderStyleOutset)
    return @"outset";
  return @"solid";
}

static void RDLAppendCSSBorder(NSMutableString *st, NSString *side, RDLBorder *b, RDLBorder *fallback) {
  RDLBorder *use = (b && b.style != RDLBorderStyleUnspecified &&
                    b.style != RDLBorderStyleNone) ? b : fallback;
  if (use == nil || use.style == RDLBorderStyleUnspecified || use.style == RDLBorderStyleNone)
    return;
  [st appendFormat:@"border-%@:%@ %@ %@;", side, [use.width stringValue] ?: @"1pt",
                   RDLCSSBorderStyle(use.style), RDLCSSColor(use.color, @"#1a1916")];
}

// TextEffect and UnicodeBiDi as CSS. A shadow runs down and to the right by
// ShadowOffset in ShadowColor; Emboss and Embed a light and a dark edge, the
// other way round from each other; Frame an outline.
static void RDLAppendCSSTextEffect(NSMutableString *st, RDLStyle *s) {
  switch (s.textEffect) {
  case RDLTextEffectShadow: {
    NSString *offset = [s.shadowOffset stringValue] ?: @"2pt";
    [st appendFormat:@"text-shadow:%@ %@ 0 %@;", offset, offset,
                     RDLCSSColor(s.shadowColor, @"rgba(0,0,0,0.5)")];
    break;
  }
  case RDLTextEffectEmboss:
    [st appendString:@"text-shadow:-1px -1px 0 rgba(255,255,255,0.8),1px 1px 0 rgba(0,0,0,0.35);"];
    break;
  case RDLTextEffectEmbed:
    [st appendString:@"text-shadow:1px 1px 0 rgba(255,255,255,0.8),-1px -1px 0 rgba(0,0,0,0.35);"];
    break;
  case RDLTextEffectFrame:
    [st appendFormat:@"-webkit-text-stroke:1px %@;", RDLCSSColor(s.shadowColor, @"#000000")];
    break;
  default:
    break;
  }
  if (s.unicodeBiDi == RDLUnicodeBiDiNormal)
    [st appendString:@"unicode-bidi:normal;"];
  else if (s.unicodeBiDi == RDLUnicodeBiDiEmbed)
    [st appendString:@"unicode-bidi:embed;"];
  else if (s.unicodeBiDi == RDLUnicodeBiDiBiDiOverride)
    [st appendString:@"unicode-bidi:bidi-override;"];
}

// Style/BackgroundImage as CSS: the image as a data URL or its own path or URL,
// tiled, placed once or stretched, at its position.
static void RDLAppendCSSBackgroundImage(NSMutableString *st, RDLLaidOutItem *it) {
  NSString *url = nil;
  if ([it.backgroundImageData length])
    url = [NSString stringWithFormat:@"url(data:%@;base64,%@)",
                                     [it.backgroundImageMIME length] ? it.backgroundImageMIME : @"image/png",
                                     [it.backgroundImageData base64EncodedStringWithOptions:0]];
  else if ([it.backgroundImageSrc length])
    url = [NSString stringWithFormat:@"url(\"%@\")", it.backgroundImageSrc];
  if (url == nil)
    return;
  [st appendFormat:@"background-image:%@;", url];
  RDLBackgroundRepeat repeat = it.backgroundRepeat;
  NSString *css = @"repeat";
  if (repeat == RDLBackgroundRepeatRepeatX)
    css = @"repeat-x";
  else if (repeat == RDLBackgroundRepeatRepeatY)
    css = @"repeat-y";
  else if (repeat == RDLBackgroundRepeatNoRepeat || repeat == RDLBackgroundRepeatFit ||
           repeat == RDLBackgroundRepeatClip)
    css = @"no-repeat";
  [st appendFormat:@"background-repeat:%@;", css];
  if (repeat == RDLBackgroundRepeatFit) {
    [st appendString:@"background-size:100% 100%;"];
    return;
  }
  NSString *position = @"left top";
  switch (repeat == RDLBackgroundRepeatClip ? RDLBackgroundPositionTopLeft : it.backgroundPosition) {
  case RDLBackgroundPositionTop:
    position = @"center top";
    break;
  case RDLBackgroundPositionTopRight:
    position = @"right top";
    break;
  case RDLBackgroundPositionLeft:
    position = @"left center";
    break;
  case RDLBackgroundPositionCenter:
    position = @"center";
    break;
  case RDLBackgroundPositionRight:
    position = @"right center";
    break;
  case RDLBackgroundPositionBottomRight:
    position = @"right bottom";
    break;
  case RDLBackgroundPositionBottom:
    position = @"center bottom";
    break;
  case RDLBackgroundPositionBottomLeft:
    position = @"left bottom";
    break;
  default:
    break;
  }
  [st appendFormat:@"background-position:%@;", position];
}

// BackgroundGradientType as CSS, running from the background colour to the end
// colour the same ways the PDF draws it. nil when there is no gradient.
static NSString *RDLCSSGradient(RDLStyle *s, NSString *background) {
  RDLGradientType type = s.backgroundGradientType;
  NSString *end = RDLCSSColor(s.backgroundGradientEndColor, nil);
  if (type == RDLGradientTypeUnspecified || type == RDLGradientTypeNone || end == nil)
    return nil;
  NSString *start = background ?: @"transparent";
  switch (type) {
  case RDLGradientTypeLeftRight:
    return [NSString stringWithFormat:@"linear-gradient(to right,%@,%@)", start, end];
  case RDLGradientTypeTopBottom:
    return [NSString stringWithFormat:@"linear-gradient(to bottom,%@,%@)", start, end];
  case RDLGradientTypeDiagonalLeft:
    return [NSString stringWithFormat:@"linear-gradient(to bottom right,%@,%@)", start, end];
  case RDLGradientTypeDiagonalRight:
    return [NSString stringWithFormat:@"linear-gradient(to bottom left,%@,%@)", start, end];
  case RDLGradientTypeHorizontalCenter:
    return [NSString stringWithFormat:@"linear-gradient(to bottom,%@,%@,%@)", start, end, start];
  case RDLGradientTypeVerticalCenter:
    return [NSString stringWithFormat:@"linear-gradient(to right,%@,%@,%@)", start, end, start];
  case RDLGradientTypeCenter:
  default:
    return [NSString stringWithFormat:@"radial-gradient(%@,%@)", end, start];
  }
}

static void RDLAppendCSSBox(NSMutableString *st, RDLStyle *s) {
  if (s == nil)
    return;
  NSString *background = RDLCSSColor(s.backgroundColor, nil);
  NSString *gradient = RDLCSSGradient(s, background);
  if (gradient)
    [st appendFormat:@"background:%@;", gradient];
  else if (background)
    [st appendFormat:@"background:%@;", background];
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
    NSString *fill = RDLCSSColor(sh.fill, @"none");
    NSString *stroke = RDLCSSColor(sh.stroke, @"none");
    NSString *op = sh.opacity < 1 ? [NSString stringWithFormat:@" opacity=\"%.2f\"", sh.opacity] : @"";
    switch (sh.kind) {
    case RDLChartShapeRect:
      [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" "
                        @"fill=\"%@\"%@%@/>",
                        sh.rect.origin.x, sh.rect.origin.y, sh.rect.size.width, sh.rect.size.height,
                        fill,
                        sh.stroke ? [NSString stringWithFormat:@" stroke=\"%@\" stroke-width=\"%.2f\"", stroke,
                                                               sh.lineWidth]
                                  : @"",
                        op];
      break;
    case RDLChartShapeEllipse:
      [svg appendFormat:@"<ellipse cx=\"%.2f\" cy=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" "
                        @"fill=\"%@\"%@%@/>",
                        NSMidX(sh.rect), NSMidY(sh.rect), sh.rect.size.width / 2,
                        sh.rect.size.height / 2, fill,
                        sh.stroke ? [NSString stringWithFormat:@" stroke=\"%@\" stroke-width=\"%.2f\"", stroke,
                                                               sh.lineWidth]
                                  : @"",
                        op];
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
      NSString *family = [sh.fontFamily length]
                             ? [NSString stringWithFormat:@"%@,Helvetica,Arial,sans-serif", RDLHTMLEsc(sh.fontFamily)]
                             : @"Helvetica,Arial,sans-serif";
      [svg appendFormat:@"<text x=\"%.2f\" y=\"%.2f\" text-anchor=\"%@\" font-size=\"%.2f\" "
                        @"font-family=\"%@\"%@%@ fill=\"%@\"%@>%@</text>",
                        sh.rect.origin.x, sh.rect.origin.y, anchor, sh.fontSize, family,
                        sh.bold ? @" font-weight=\"bold\"" : @"",
                        sh.italic ? @" font-style=\"italic\"" : @"", fill, transform,
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
      // A body item that runs past the body band is cut there, as on paper,
      // rather than drawn over the page footer or under the header.
      // Part of a row split across pages is cut to its piece instead.
      CGFloat cutTop = MAX((it.inPiece ? it.pieceTop : page.bodyTop) - it.y, 0);
      CGFloat cutBottom = MAX(it.y + it.h - (it.inPiece ? it.pieceBottom : page.bodyBottom), 0);
      if ((it.region == RDLLaidOutRegionBody || it.inPiece) && (cutTop > 0 || cutBottom > 0))
        [st appendFormat:@"clip-path:inset(%.4fin 0 %.4fin 0);", cutTop, cutBottom];
      NSString *color = RDLCSSColor(it.style.color, @"#1a1916");
      NSString *ff = it.style.fontFamily.length ? it.style.fontFamily : @"Georgia";
      NSString *fs = [it.style.fontSize stringValue] ?: @"10pt";
      NSString *fw = RDLFontWeightIsBold(it.style.fontWeight) ? @"700" : @"400";
      [st appendFormat:@"color:%@;font-family:%@;font-size:%@;font-weight:%@;text-align:%@;",
                       color, ff, fs, fw, RDLCSSAlign(it.style.textAlign)];
      if (it.style.fontStyle == RDLFontStyleItalic)
        [st appendString:@"font-style:italic;"];
      if (it.style.lineHeight)
        [st appendFormat:@"line-height:%@;", [it.style.lineHeight stringValue]];
      if (it.style.direction == RDLLayoutDirectionRTL)
        [st appendString:@"direction:rtl;"];
      if (it.style.writingMode == RDLWritingModeVertical)
        [st appendString:@"writing-mode:vertical-rl;"];
      else if (it.style.writingMode == RDLWritingModeRotate270)
        // Vertical writing turned half round, so it reads bottom to top.
        [st appendString:@"writing-mode:vertical-rl;transform:rotate(180deg);"];
      RDLAppendCSSTextEffect(st, it.style);
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
        NSString *lc = (b && b.color.length) ? RDLCSSColor(b.color, color) : color;
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
      RDLAppendCSSBackgroundImage(st, it);
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
          // AutoSize, the default, has laid the box out at the image's own size,
          // so the image fills it, as Fit does; Clip is the image at its own size
          // from the top left, cut off by the box; FitProportional as large as
          // fits unstretched.
          RDLImageSizing sizing =
              img.sizing != RDLImageSizingUnspecified ? img.sizing : RDLImageSizingAutoSize;
          NSString *size = @"width:100%;height:100%;object-fit:fill;";
          if (sizing == RDLImageSizingFitProportional)
            size = @"width:100%;height:100%;object-fit:contain;";
          else if (sizing == RDLImageSizingClip)
            size = img.naturalWidth > 0
                       ? [NSString stringWithFormat:@"width:%.4fin;height:%.4fin;", img.naturalWidth, img.naturalHeight]
                       : @"object-fit:none;";
          NSString *img = [NSString
              stringWithFormat:@"<img src=\"%@\" alt=\"%@\" style=\"%@object-position:0 0;\">",
                               RDLHTMLEsc(src), RDLHTMLEsc(it.name ?: @""), size];
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
        NSArray<NSString *> *markers = [RDLTextAttributes listMarkersForParagraphs:tb.spans];
        NSUInteger paraIndex = 0;
        for (RDLParagraph *para in tb.spans) {
          NSString *marker = markers[paraIndex++];
          NSMutableString *ps = [NSMutableString string];
          if (para.style.textAlign != RDLTextAlignUnspecified)
            [ps appendFormat:@"text-align:%@;", RDLCSSAlign(para.style.textAlign)];
          if (para.style.lineHeight)
            [ps appendFormat:@"line-height:%@;", [para.style.lineHeight stringValue]];
          // The paragraph's own layout: lines start at padding-left, the first
          // one text-indent further; right indent and the space around it.
          CGFloat firstLine = 0, otherLines = 0;
          [RDLTextAttributes indentsForParagraph:para firstLine:&firstLine otherLines:&otherLines];
          if (firstLine != 0 || otherLines != 0)
            [ps appendFormat:@"padding-left:%gpt;text-indent:%gpt;", otherLines, firstLine - otherLines];
          if (para.rightIndent)
            [ps appendFormat:@"padding-right:%@;", [para.rightIndent stringValue]];
          if (para.spaceBefore)
            [ps appendFormat:@"margin-top:%@;", [para.spaceBefore stringValue]];
          if (para.spaceAfter)
            [ps appendFormat:@"margin-bottom:%@;", [para.spaceAfter stringValue]];
          if ([ps length])
            [rich appendFormat:@"<div style=\"%@\">", RDLHTMLEsc(ps)];
          else
            [rich appendString:@"<div>"];
          if ([marker length])
            [rich appendFormat:@"<span class=\"rdl-list-marker\" style=\"display:inline-block;"
                               @"width:%gpt;text-indent:0;\">%@</span>",
                               otherLines - firstLine, RDLHTMLEsc(marker)];
          for (RDLTextRun *run in para.runs) {
            NSMutableString *rs = [NSMutableString string];
            RDLStyle *s = run.style;
            if ([s.color length])
              [rs appendFormat:@"color:%@;", RDLCSSColor(s.color, @"#1a1916")];
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
            NSString *runHTML =
                [rs length] ? [NSString stringWithFormat:@"<span style=\"%@\">%@</span>",
                                                         RDLHTMLEsc(rs), RDLHTMLEsc(run.value ?: @"")]
                            : RDLHTMLEsc(run.value ?: @"");
            // The run's tooltip, and its link -- unless the whole box is a
            // link already, since one link cannot hold another.
            if ([run.toolTip.literal length])
              runHTML = [NSString stringWithFormat:@"<span title=\"%@\">%@</span>",
                                                   RDLHTMLEsc(run.toolTip.literal), runHTML];
            if ([run.hyperlink.literal length] && ![it.hyperlink length])
              runHTML = [NSString stringWithFormat:@"<a href=\"%@\" style=\"color:inherit;\">%@</a>",
                                                   RDLHTMLEsc(run.hyperlink.literal), runHTML];
            [rich appendString:runHTML];
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
