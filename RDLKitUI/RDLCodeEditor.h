/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// A report's code: Visual Basic functions, called from expressions as
// Code.Name, written in a text view that says as it goes what in it cannot be
// read. Modal, like the other panels here.
@interface RDLCodeEditor : NSObject

// The edited code, or nil if the user cancelled.
+ (NSString *)runForCode:(NSString *)code title:(NSString *)title;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForCode:(NSString *)code title:(NSString *)title;

// The code as written, and what cannot be read in it.
@property (nonatomic, copy) NSString *code;
@property (nonatomic, readonly, copy) NSArray<NSString *> *problems;
// The line under the text, as it reads.
@property (nonatomic, readonly, copy) NSString *status;
@end
