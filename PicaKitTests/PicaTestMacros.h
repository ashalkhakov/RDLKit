// XCTest on macOS today. Later: map these macros onto a GNUstep harness
// (Testing.h / a small main that calls PicaRunAllChecks).
#ifndef PICA_TEST_MACROS_H
#define PICA_TEST_MACROS_H

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <XCTest/XCTest.h>
#define PICA_TEST_CASE XCTestCase
#define PICA_ASSERT_NO_FAILURES(expr)                                                          \
  do {                                                                                         \
    NSArray *_picaFails = (expr);                                                              \
    XCTAssertTrue(_picaFails.count == 0, @"%@", [_picaFails componentsJoinedByString:@"\n"]); \
  } while (0)
#else
#import <Foundation/Foundation.h>
@interface PicaTestCase : NSObject
@end
#define PICA_TEST_CASE PicaTestCase
#define PICA_ASSERT_NO_FAILURES(expr)                                                          \
  do {                                                                                         \
    NSArray *_picaFails = (expr);                                                              \
    if ([_picaFails count])                                                                    \
      [NSException raise:@"PicaTestFailure" format:@"%@", [_picaFails componentsJoinedByString:@"\n"]]; \
  } while (0)
#endif

#endif
