/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What every designer suite includes: the imports, and the helpers more than
// one of them uses. A helper only one suite calls lives in that suite's file,
// beside what it serves.
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "RDLKit.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLSelection.h"
#import "RDLItemFactory.h"
#import "RDLSamples.h"
#import "RDLRichTextFormatter.h"
#import "RDLRichTextCodec.h"
#import "RDLRichTextEditor.h"
#import "RDLInsertPalette.h"
#import "RDLCanvasView.h"
#import "RDLInspectorFields.h"
#import "RDLPageGeometry.h"
#import "RDLEditingContext.h"
#import "RDLExpressionHelper.h"
#import "RDLTablixEditor.h"
#import "RDLDatasetNavigator.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLInspectorView.h"
#import "RDLDesignerWindow.h"
#import "DMTabBar.h"
#import "RDLDatasetFieldsView.h"
#import "RDLNewReportPanel.h"

NSString *RDLColorMismatch(NSColor *actual, NSColor *expected, NSString *what);
NSButton *RDLFindButtonTitled(NSView *view, NSString *title);
NSString *RDLSourceDirectory(void);
NSString *RDLDesignerFixture(NSString *name);

// The base every suite here inherits. It exists for one line, and that line is
// load-bearing on GNUstep: nothing that touches a font may run before the
// shared application exists. Inherited rather than copied into each suite --
// there were five copies of it, and splitting the files lost six more.
@interface RDLDesignerTestCase : XCTestCase
@end
