/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What every RDLKit suite needs: the imports, the expectation helpers, and the
// fixtures more than one of them builds on.
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <RDLKit/RDLKit.h>
#import "RDLKit.h"

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
