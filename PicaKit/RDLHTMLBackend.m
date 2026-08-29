#import "RDLBackend.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

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
      if (it.style.backgroundColor.length && ![it.style.backgroundColor isEqualToString:@"Transparent"])
        [st appendFormat:@"background:%@;", it.style.backgroundColor];
      if ([it.kind isEqualToString:@"Line"]) {
        [st appendFormat:@"border-top:1px solid %@;height:0;", color];
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Line\" style=\"%@\"></div>\n", st];
        continue;
      }
      if ([it.kind isEqualToString:@"Rectangle"]) {
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Rectangle\" style=\"%@\"></div>\n", st];
        continue;
      }
      if ([it.kind isEqualToString:@"Image"]) {
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Image\" style=\"%@\"></div>\n", st];
        continue;
      }
      if ([it.kind isEqualToString:@"Chart"]) {
        [html appendFormat:@"<div class=\"pica-item\" data-kind=\"Chart\" style=\"%@\">", st];
        NSUInteger n = [it.values count];
        double max = 1;
        for (NSNumber *v in it.values)
          if ([v doubleValue] > max)
            max = [v doubleValue];
        if (n) {
          CGFloat gap = 100.0 / n;
          for (NSUInteger b = 0; b < n; b++) {
            double h = ([it.values[b] doubleValue] / max) * 80.0;
            [html appendFormat:@"<span class=\"pica-bar\" style=\"left:%.2f%%;width:%.2f%%;height:%.2f%%;\"></span>",
                               b * gap + gap * 0.2, gap * 0.5, h];
          }
        }
        [html appendString:@"</div>\n"];
        continue;
      }
      [html appendFormat:@"<div class=\"pica-item\" data-kind=\"%@\" style=\"%@\">%@</div>\n",
                         PicaHTMLEsc(it.kind ?: @"Textbox"), st, PicaHTMLEsc(it.text ?: @"")];
    }
    [html appendString:@"</section>\n"];
  }
  [html appendString:@"</body>\n</html>\n"];
  return html;
}

@end
