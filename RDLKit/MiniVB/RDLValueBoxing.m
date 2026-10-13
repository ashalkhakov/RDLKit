/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLValueBoxing.h"

// Nothing: nil, or NSNull where a collection holds it. The empty string is a
// string, as it is in VB: IsNothing("") is False, and Count counts it.
BOOL RDLIsNothing(id v) {
  return v == nil || v == [NSNull null];
}

// A value as a collection holds it, Nothing being NSNull there.
id RDLOutOfCollection(id v) {
  return v == [NSNull null] ? nil : v;
}

double RDLNum(id v) {
  if ([v isKindOfClass:[RDLNumber class]])
    return [(RDLNumber *)v doubleValue];
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSDate class]])
    return [(NSDate *)v timeIntervalSince1970] * 1000.0;
  if ([v isKindOfClass:[NSString class]]) {
    NSString *s = [(NSString *)v stringByReplacingOccurrencesOfString:@"," withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"$" withString:@""];
    return [s doubleValue];
  }
  return 0;
}

// A number, or a Foundation number -- True and False among them -- that came
// from outside the expression language.
BOOL RDLNumericLikeValue(id v) {
  return [v isKindOfClass:[RDLNumber class]] || [v isKindOfClass:[NSNumber class]];
}

BOOL RDLNumericLike(id v) {
  if (RDLNumericLikeValue(v))
    return YES;
  return [v isKindOfClass:[NSString class]] && [RDLNumber doubleWithText:v] != nil;
}

id RDLYes(BOOL b) {
  return b ? @YES : @NO;
}

// The numbers the expression language makes, by the VB type they are.
RDLNumber *RDLShort(int16_t v) {
  return [RDLNumber numberWithShort:v];
}

RDLNumber *RDLInt(int32_t v) {
  return [RDLNumber numberWithInteger:v];
}

RDLNumber *RDLLong(int64_t v) {
  return [RDLNumber numberWithLong:v];
}

RDLNumber *RDLDouble(double v) {
  return [RDLNumber numberWithDouble:v];
}
