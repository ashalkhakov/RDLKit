/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What every RDLKit suite needs: the imports, the expectation helpers, and the
// fixtures more than one of them builds on.
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// Xcode builds RDLKit as a framework and GNUstep builds it as a library in the
// tree beside this one, so the umbrella header is reached differently. The
// guard was around these two imports before the suites were split into files;
// splitting kept the imports and dropped the guard, which GNUstep noticed.
#if __has_include(<RDLKit/RDLKit.h>)
#import <RDLKit/RDLKit.h>
#else
#import "RDLKit.h"
#endif

@interface XCTestCase (RDLExpect)
- (void)expectText:(NSString *)expr scope:(RDLEvalScope *)s equals:(NSString *)want;
- (void)expectNumber:(NSString *)expr scope:(RDLEvalScope *)s equals:(double)want;
- (void)expectTrue:(NSString *)expr scope:(RDLEvalScope *)s;
- (NSData *)fixtureNamed:(NSString *)name;
@end

// Fixtures and helpers more than one suite uses. The ones only a single suite
// needs live in that suite's file, where they can be read beside what they
// serve.
RDLReport *RDLMiniInvoice(void);
double RDLAsNum(id v);
NSString *RDLLaidText(RDLLaidOutItem *it);
RDLReport *RDLGroupedJobs(void);
NSString *RDLSourceDirectory(void);
NSString *RDLFixturesDirectory(void);

// The base every suite here inherits. It exists for one line, and that line is
// load-bearing on GNUstep: nothing that touches a font may run before the
// shared application exists. Inherited rather than copied into each suite --
// there were five copies of it, and splitting the files lost six more.
@interface RDLKitTestCase : XCTestCase
@end
