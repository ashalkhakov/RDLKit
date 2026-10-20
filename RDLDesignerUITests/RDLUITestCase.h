/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The base of every designer UI test: the app as a person finds it, and what
// it looked like when a check failed.
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "RDLUIDriver.h"
#import <objc/runtime.h>
#import "RDLKit.h"
// The app's own headers, for what its objects answer; its classes are found
// by name (RDLUIClass), never linked against.
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLDesignerWindow.h"
#import "RDLCanvasView.h"
#import "RDLPageGeometry.h"
#import "RDLSelection.h"

@interface RDLUITestCase : XCTestCase

// The open designer documents, the frontmost first.
- (NSArray<RDLDocument *> *)documents;
// The designer window of `doc`, and the views a person works with in it.
- (RDLDesignerWindow *)designerOf:(RDLDocument *)doc;
- (RDLCanvasView *)canvasOf:(RDLDocument *)doc;
- (RDLEditingContext *)contextOf:(RDLDocument *)doc;
// A control of the designer window by its outlet name ("zoomPop").
- (id)outlet:(NSString *)name of:(RDLDocument *)doc;

// A new blank report, made the way a person makes one: File > New Report…,
// Blank, Create. Its document, in front.
- (RDLDocument *)newBlankReport;
// `name` (a sample's file name, "HarborDispatch") and what it reads, copied to
// a folder of its own; the copy's URL.
- (NSURL *)copyOfSample:(NSString *)name;
// The report at `url`, opened with File > Open….
- (RDLDocument *)openWithFileMenu:(NSURL *)url;

// Where `item` is on the canvas, in the canvas view's coordinates.
- (NSRect)rectOfItem:(RDLItem *)item inDocument:(RDLDocument *)doc;
// Clicks `item` on the canvas (with `flags`, shift to add to the selection).
- (void)clickItem:(RDLItem *)item inDocument:(RDLDocument *)doc flags:(NSEventModifierFlags)flags;
// Adds an element of the kind titled `kind` ("Textbox") with Edit > Add
// Element…, as the panel offers it; the item it added.
- (RDLItem *)addElement:(NSString *)kind toDocument:(RDLDocument *)doc;
// Clicks a field, selects what is in it, types `text` and presses Return.
- (void)typeInto:(NSTextField *)field text:(NSString *)text;
// Clicks the tab labelled `label` in the left or right tab bar.
- (BOOL)clickTab:(NSString *)label inBar:(NSString *)bar of:(RDLDocument *)doc;

// Closes everything a test opened, discarding what it changed.
- (void)closeEverything;

@end
