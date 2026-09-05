/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What every designer suite includes. Only imports so far: each suite's
// fixtures are used by that suite alone and live beside it. Anything two of
// them come to share belongs here, with its definition in a .m added then.
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
#import "RDLRichTextCodec.h"
#import "RDLInspectorFields.h"
#import "RDLEditingContext.h"
#import "RDLExpressionHelper.h"
#import "RDLInspectorFields.h"
#import "RDLTablixEditor.h"
#import "RDLDatasetNavigator.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLInspectorView.h"
#import "RDLPageGeometry.h"
#import "RDLDesignerWindow.h"
#import "DMTabBar.h"
#import "RDLDatasetFieldsView.h"
#import "RDLRichTextEditor.h"
#import "RDLNewReportPanel.h"



// Fixtures and helpers more than one suite uses. The ones only a single suite
// needs live in that suite's file, where they can be read beside what they
// serve.

