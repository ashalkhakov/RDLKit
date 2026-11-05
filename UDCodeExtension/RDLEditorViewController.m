/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "RDLReportDesigner.h"
#import "RDLChecker.h"
#import "RDLTabBadge.h"
#import "RDLTextDiff.h"

// The report's problems, among the document's diagnostics.
static UDDiagnosticSource const RDLIssueSource = @"rdl";
// The Document Outline's width when the tab opens, and its narrowest.
static const CGFloat RDLOutlineWidth = 220;
static const CGFloat RDLOutlineMinimum = 160;

// The tab's view (RDLEditor.xib): its controller after it in the chain,
// wherever UDCode puts it, so the Editor menu's items and Undo reach the tab.
// AppKit puts a view controller there by itself (since 10.10); gnustep-gui
// does not; and a view put in another is given its superview as the next
// responder again.
@interface RDLEditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

@implementation RDLEditorView

- (void)setNextResponder:(NSResponder *)responder {
  NSResponder *controller = self.controller;
  if (controller == nil || responder == controller) {
    [super setNextResponder:responder];
    return;
  }
  [controller setNextResponder:responder];
  [super setNextResponder:controller];
}

@end

// An inspector's tab's image, as Xcode's are: its SF Symbol on macOS; on
// GNUstep, which has none, drawn alike. Report: a ruler (the page, its
// margins); Attributes: sliders; Style: a brush.
static NSImage *RDLInspectorImage(NSString *title) {
  NSDictionary *symbols =
      @{@"Report" : @"ruler", @"Attributes" : @"slider.horizontal.3", @"Style" : @"paintbrush"};
  NSString *symbol = symbols[title];
  if (symbol == nil)
    return nil;
#ifndef GNUSTEP
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
    return [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
#endif
  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
  [image lockFocus];
  [[NSColor colorWithCalibratedWhite:0.25 alpha:1] set];
  if ([symbol isEqualToString:@"ruler"]) {
    NSBezierPath *body = [NSBezierPath bezierPathWithRect:NSMakeRect(1.5, 4.5, 13, 7)];
    [body setLineWidth:1.2];
    [body stroke];
    for (NSInteger tick = 0; tick < 5; tick++) {
      CGFloat x = 3.5 + 2.25 * tick;
      [NSBezierPath strokeLineFromPoint:NSMakePoint(x, 11.5)
                                toPoint:NSMakePoint(x, tick % 2 ? 9.5 : 8)];
    }
  } else if ([symbol isEqualToString:@"slider.horizontal.3"]) {
    CGFloat knobs[] = {10.5, 5.5, 8.5};
    for (NSInteger row = 0; row < 3; row++) {
      CGFloat y = 3.5 + 4.5 * row;
      NSBezierPath *track = [NSBezierPath bezierPath];
      [track moveToPoint:NSMakePoint(1.5, y)];
      [track lineToPoint:NSMakePoint(14.5, y)];
      [track setLineWidth:1.2];
      [track setLineCapStyle:NSLineCapStyleRound];
      [track stroke];
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(knobs[row] - 1.8, y - 1.8, 3.6, 3.6)] fill];
    }
  } else {
    NSBezierPath *handle = [NSBezierPath bezierPath];
    [handle moveToPoint:NSMakePoint(14, 14)];
    [handle lineToPoint:NSMakePoint(7.5, 7.5)];
    [handle setLineWidth:2];
    [handle setLineCapStyle:NSLineCapStyleRound];
    [handle stroke];
    NSBezierPath *bristles = [NSBezierPath bezierPath];
    [bristles moveToPoint:NSMakePoint(7.5, 8.5)];
    [bristles curveToPoint:NSMakePoint(1.5, 1.5)
             controlPoint1:NSMakePoint(4, 8)
             controlPoint2:NSMakePoint(4.5, 3)];
    [bristles curveToPoint:NSMakePoint(8.5, 7.5)
             controlPoint1:NSMakePoint(5, 2)
             controlPoint2:NSMakePoint(9, 4)];
    [bristles closePath];
    [bristles fill];
  }
  [image unlockFocus];
  return image;
}

@interface RDLEditorViewController () <RDLReportDesignerDelegate, NSSplitViewDelegate>
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *outlineHost;
@property (nonatomic, weak) IBOutlet NSView *designerHost;
@property (nonatomic, readwrite, strong) RDLReportDesigner *designer;
@property (nonatomic, readwrite, copy) NSString *problem;
@end

@implementation RDLEditorViewController {
  __weak id<UDWorkbench> _workbench;
  // The designer's undo, which records nothing: the text's is the undo.
  NSUndoManager *_designerUndo;
  // The text being read (what the designer reports then is no change of the
  // user's), or written (what the text model reports then is the designer's
  // own).
  BOOL _reading;
  BOOL _writing;
  // Each problem's item, by its diagnostic's line and message.
  NSMutableDictionary<NSString *, NSString *> *_issueItems;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench {
  if ((self = [super initWithNibName:@"RDLEditor"
                              bundle:[NSBundle bundleForClass:[RDLEditorViewController class]]])) {
    _document = document;
    _workbench = workbench;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textDidChange:)
                                                 name:UDTextModelDidChangeNotification
                                               object:document.textModel];
    [self read];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)loadView {
  [super loadView];
  [_split setPosition:RDLOutlineWidth ofDividerAtIndex:0];
  [self show];
}

#pragma mark Reading

// The folder the report's relative names (its data documents, subreports,
// images) resolve against: its file's.
- (NSURL *)baseURL {
  return [_document.fileURL URLByDeletingLastPathComponent];
}

// The designer, hosted, for the first text that is a report, recording no
// undo of its own.
- (RDLReportDesigner *)makeDesigner {
  _designerUndo = [[NSUndoManager alloc] init];
  [_designerUndo setGroupsByEvent:NO];
  [_designerUndo disableUndoRegistration];
  RDLReportDesigner *designer = [[RDLReportDesigner alloc] initWithReport:nil
                                                              undoManager:_designerUndo];
  designer.delegate = self;
  designer.hosted = YES;
  return designer;
}

// The text read into the designer; or, when it is no report, why.
- (void)read {
  NSData *data = [[_document.textModel getValue] dataUsingEncoding:NSUTF8StringEncoding];
  if (_designer == nil)
    self.designer = [self makeDesigner];
  NSError *error = nil;
  _reading = YES;
  BOOL read = [_designer loadData:data ?: [NSData data] baseURL:[self baseURL] error:&error];
  _reading = NO;
  self.problem =
      read ? nil
           : [NSString stringWithFormat:@"This is not a report that can be shown: %@",
                                        [error localizedDescription] ?: @"it cannot be read."];
  [self show];
  [self scheduleIssues];
}

// The text changed, not by the designer: read again, at once while the tab
// shows (an undo), a moment later while it does not (typed in a tab of its
// text, each key would be a read of the whole report).
- (void)textDidChange:(NSNotification *)notification {
  (void)notification;
  if (_writing)
    return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(readAgain) object:nil];
  if ([self isViewLoaded] && [[self view] window] != nil)
    [self readAgain];
  else
    [self performSelector:@selector(readAgain) withObject:nil afterDelay:0.3];
}

// Read again, the item that was selected selected again where it still is.
- (void)readAgain {
  NSString *selected = [_designer selectedItemName];
  [self read];
  if (selected != nil && self.problem == nil)
    [_designer selectItemNamed:selected];
}

#pragma mark Writing

// The report changed: written once the change is done (one user's action is
// several of the designer's), so one action is one edit of the text, one undo.
- (void)reportDesignerDidChange:(RDLReportDesigner *)designer {
  (void)designer;
  if (_reading)
    return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  [self performSelector:@selector(write) withObject:nil afterDelay:0];
  [_workbench closeLibrary];
}

// The report written as the text: an edit for each run of lines that differs
// (RDLLineChanges), made at once, so undone as one, and a diff of the file
// says what changed.
- (void)write {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  if (_designer == nil || self.problem != nil)
    return;
  NSString *text = [_designer RDLString];
  UDTextModel *model = _document.textModel;
  NSString *old = [model getValue];
  // A byte order mark the text as read did not show.
  if ([text hasPrefix:@"﻿"] && ![old hasPrefix:@"﻿"])
    text = [text substringFromIndex:1];
  if (text == nil || [text isEqualToString:old])
    return;
  NSMutableArray *edits = [NSMutableArray array];
  for (RDLTextChange *change in RDLLineChanges(old, text)) {
    UDPosition from = [model getPositionAt:(NSInteger)change.offset];
    UDPosition to = [model getPositionAt:(NSInteger)(change.offset + change.length)];
    UDRange range = {from.line, from.column, to.line, to.column};
    [edits addObject:[[UDTextModelEdit alloc] initWithRange:range text:change.text]];
  }
  _writing = YES;
  [model applyEdits:edits];
  _writing = NO;
  // The designer opens a group for each action even with nothing recorded:
  // kept empty, it never says it has something to undo. Emptying it turns
  // registration back on (AppKit's and GNUstep's -removeAllActions both do),
  // so it is turned off again: the designer goes on recording nothing.
  [_designerUndo removeAllActions];
  if ([_designerUndo isUndoRegistrationEnabled])
    [_designerUndo disableUndoRegistration];
  [self scheduleIssues];
}

#pragma mark Showing

// The designer's parts in the tab, and the tab after the designer's view in
// the chain; or why there is none.
- (void)show {
  if (![self isViewLoaded])
    return;
  NSView *editor = [_designer view];
  NSView *outline = _designer.navigatorPane;
  if (self.problem == nil && editor != nil) {
    if ([editor superview] != _designerHost) {
      [editor setFrame:[_designerHost bounds]];
      [editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [_designerHost addSubview:editor];
      if ([editor nextResponder] != _designer) {
        [_designer setNextResponder:[editor nextResponder]];
        [editor setNextResponder:_designer];
      }
    }
    if (outline != nil && [outline superview] != _outlineHost) {
      [outline setFrame:[_outlineHost bounds]];
      [outline setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [_outlineHost addSubview:outline];
    }
    [_split setHidden:NO];
    [self.problemView setHidden:YES];
  } else {
    [_split setHidden:YES];
    [self.problemLabel setStringValue:self.problem ?: @""];
    [self.problemView setHidden:NO];
  }
}

// The Document Outline keeps its width as the tab is resized, the editor
// taking the difference.
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview {
  (void)splitView;
  return subview != _outlineHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
  (void)splitView;
  (void)index;
  return MAX(proposed, RDLOutlineMinimum);
}

#pragma mark Issues

// The report's problems found again a moment after it changes (a burst of
// changes finds them once), as the designer's Problems pane does.
- (void)scheduleIssues {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(findIssues) object:nil];
  [self performSelector:@selector(findIssues) withObject:nil afterDelay:0.5];
}

// The problems as the document's diagnostics: each at the line its item is
// written on (its Name's), the report's first line when it is about no item;
// none while the text is no report.
- (void)findIssues {
  NSMutableArray *items = [NSMutableArray array];
  _issueItems = [NSMutableDictionary dictionary];
  if (_designer != nil && self.problem == nil) {
    NSString *text = [_document.textModel getValue];
    for (RDLDiagnostic *problem in [RDLChecker checkReport:_designer.report]) {
      NSInteger line = 1;
      if (problem.itemName != nil) {
        NSRange at = [text rangeOfString:[NSString stringWithFormat:@"Name=\"%@\"", problem.itemName]];
        if (at.location != NSNotFound)
          line = [_document.textModel getPositionAt:(NSInteger)at.location].line;
      }
      UDDiagnosticSeverity severity = problem.severity == RDLDiagnosticSeverityError
                                          ? UDDiagnosticSeverityError
                                          : UDDiagnosticSeverityWarning;
      NSString *message = [problem.path length] > 0
                              ? [NSString stringWithFormat:@"%@: %@", problem.path, problem.message]
                              : problem.message;
      [items addObject:[[UDDiagnosticItem alloc] initWithLine:line
                                                       column:0
                                                      message:message
                                                     severity:severity
                                                       source:RDLIssueSource]];
      if (problem.itemName != nil)
        _issueItems[[NSString stringWithFormat:@"%ld %@", (long)line, message]] = problem.itemName;
    }
  }
  [_document.diagnosticStore setDiagnostics:items forSource:RDLIssueSource];
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers {
  return _designer.inspectorControllers ?: @[];
}

- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController {
  return RDLInspectorImage(viewController.title);
}

- (NSArray<NSViewController *> *)bottomAreaViewControllers {
  NSViewController *groups = _designer.groupsController;
  return groups != nil ? @[ groups ] : @[];
}

// Its badge, as the designer's tab bars have them.
- (NSImage *)imageForBottomAreaViewController:(NSViewController *)viewController {
  if (viewController != _designer.groupsController)
    return nil;
  NSImage *image = RDLTabBadge(@"G", 0.36, 0.49, 0.72);
  [image setSize:NSMakeSize(16, 16)];
  return image;
}

- (NSViewController *)libraryViewController {
  return _designer.insertController;
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
  NSString *item = _issueItems[[NSString stringWithFormat:@"%ld %@", (long)diagnostic.line,
                                                          diagnostic.message]];
  if (item != nil)
    [_designer selectItemNamed:item];
}

- (id)fieldEditorForClient:(id)client {
  return [_designer fieldEditorForClient:client];
}

#pragma mark The designer (RDLReportDesignerDelegate)

// A part brought forward in its pane: the Attributes inspector, unless Style
// (which shows the selection too) is the one in front; the groups.
- (void)reportDesigner:(RDLReportDesigner *)designer showPart:(NSViewController *)part {
  NSArray *inspectors = designer.inspectorControllers;
  if ([inspectors indexOfObjectIdenticalTo:part] != NSNotFound) {
    if ([inspectors count] > 2 && [[inspectors[2] view] window] != nil)
      return;
    [_workbench showEditorInspector:part];
  } else {
    [_workbench showEditorBottomPane:part];
  }
}

// A subreport opened as UDCode opens a file: in a tab of its own.
- (BOOL)reportDesigner:(RDLReportDesigner *)designer openSubreportAtURL:(NSURL *)url {
  (void)designer;
  [_workbench showURL:url];
  return YES;
}

#pragma mark Actions

// The designer's commands reach it from anywhere in the tab: from the
// Document Outline, which is outside its view, too.
- (BOOL)isDesignerCommand:(SEL)action {
  for (RDLReportDesignerCommand *command in [RDLReportDesigner commands])
    if (sel_isEqual(command.action, action))
      return YES;
  return NO;
}

- (BOOL)respondsToSelector:(SEL)selector {
  if ([super respondsToSelector:selector])
    return YES;
  return [self isDesignerCommand:selector] && [[_designer view] respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
  if ([self isDesignerCommand:selector] && [[_designer view] respondsToSelector:selector])
    return [_designer view];
  return [super forwardingTargetForSelector:selector];
}

- (IBAction)undo:(id)sender {
  (void)sender;
  [self write];
  [_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender {
  (void)sender;
  [_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender {
  (void)sender;
  [_workbench showDocumentAsText:_document];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  SEL action = [item action];
  if (sel_isEqual(action, @selector(undo:)))
    return _document.textModel.undoManager.canUndo;
  if (sel_isEqual(action, @selector(redo:)))
    return _document.textModel.undoManager.canRedo;
  if ([self isDesignerCommand:action])
    return [_designer validateUserInterfaceItem:item];
  return YES;
}

@end
