// PicaCompatibility.h — Cocoa / GNUstep shims. Pure ObjC, ARC.
#ifndef PICA_COMPATIBILITY_H
#define PICA_COMPATIBILITY_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#ifndef PICA_COLOR
#define PICA_COLOR(r, g, b, a) \
  [NSColor colorWithCalibratedRed:(r) green:(g) blue:(b) alpha:(a)]
#endif

#ifndef PICA_UNUSED
#define PICA_UNUSED(x) (void)(x)
#endif

static inline NSColor *PicaColorFromHex(NSString *hex) {
  if (hex == nil || [hex length] == 0) {
    return PICA_COLOR(0.10, 0.10, 0.09, 1);
  }
  NSString *s = [hex stringByTrimmingCharactersInSet:
                          [NSCharacterSet characterSetWithCharactersInString:@"#"]];
  if ([s length] < 6) {
    return PICA_COLOR(0.10, 0.10, 0.09, 1);
  }
  unsigned int rgb = 0;
  [[NSScanner scannerWithString:[s substringToIndex:6]] scanHexInt:&rgb];
  CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
  CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
  CGFloat b = (rgb & 0xFF) / 255.0;
  return PICA_COLOR(r, g, b, 1);
}

static inline CGFloat PicaInchesFromString(NSString *raw) {
  if (raw == nil || [raw length] == 0) {
    return 0;
  }
  double n = [raw doubleValue];
  NSString *lower = [raw lowercaseString];
  if ([lower hasSuffix:@"cm"])
    return (CGFloat)(n / 2.54);
  if ([lower hasSuffix:@"mm"])
    return (CGFloat)(n / 25.4);
  if ([lower hasSuffix:@"pt"])
    return (CGFloat)(n / 72.0);
  if ([lower hasSuffix:@"pc"])
    return (CGFloat)((n * 12.0) / 72.0);
  if ([lower hasSuffix:@"px"])
    return (CGFloat)(n / 96.0);
  return (CGFloat)n;
}

#ifndef NSYearCalendarUnit
#define NSYearCalendarUnit NSCalendarUnitYear
#define NSMonthCalendarUnit NSCalendarUnitMonth
#define NSDayCalendarUnit NSCalendarUnitDay
#define NSHourCalendarUnit NSCalendarUnitHour
#define NSMinuteCalendarUnit NSCalendarUnitMinute
#define NSSecondCalendarUnit NSCalendarUnitSecond
#define NSWeekdayCalendarUnit NSCalendarUnitWeekday
#define NSWeekCalendarUnit NSCalendarUnitWeekOfYear
#endif

#ifdef GNUSTEP
// GNUstep Foundation has no CoreFoundation kCFBoolean constants; NSNumber
// booleans are singletons there too, so identity comparison still works.
#ifndef kCFBooleanTrue
#define kCFBooleanTrue ([NSNumber numberWithBool:YES])
#define kCFBooleanFalse ([NSNumber numberWithBool:NO])
#endif
#endif

#endif
