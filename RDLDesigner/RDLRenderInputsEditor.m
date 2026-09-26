/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLRenderInputsEditor.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLParameterPrompts.h"

// The panel's one column, and the space around it.
static const CGFloat kRowWidth = 420;
static const CGFloat kRowLeft = 14;
static const CGFloat kRowGap = 8;

// A stack that lays out downwards, as the panes do: without it the first thing
// added ends up at the bottom with the rest above it in reverse.
@interface RDLInputsStack : NSView
@end
@implementation RDLInputsStack
- (BOOL)isFlipped {
  return YES;
}
@end

@interface RDLRenderInputsEditor () <NSTextFieldDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSScrollView *scroll;
@property (nonatomic, strong) IBOutlet NSTextField *headingLabel;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@end

@implementation RDLRenderInputsEditor {
  RDLEditingContext *_context;
  RDLInputsStack *_stack;
  // The sources in the order their rows were built, and the file each one read
  // when the panel opened -- so OK writes only what was changed.
  NSArray<RDLDataSource *> *_sources;
  NSMutableArray<NSTextField *> *_documentFields;
  NSMutableArray<NSString *> *_documentsAsFound;
  NSMutableArray<NSPopUpButton *> *_readsPops;
  NSButton *_defaultsButton;
  // The values as they were when the panel opened. The prompts write straight
  // through to the document as they are used, which is what makes the preview
  // answer at once; Cancel is this going back.
  NSDictionary *_paramsAsFound;
  NSDictionary *_multiParamsAsFound;
}

+ (BOOL)runForContext:(RDLEditingContext *)context {
  RDLRenderInputsEditor *editor = [self editorForContext:context];
  if (editor == nil)
    return NO;
  [editor.window center];
  NSInteger code = [NSApp runModalForWindow:editor.window];
  [editor.window orderOut:nil];
  if (code == NSModalResponseOK)
    return [editor apply];
  [editor putValuesBack];
  return NO;
}

+ (instancetype)editorForContext:(RDLEditingContext *)context {
  if (context == nil)
    return nil;
  RDLRenderInputsEditor *editor = [[self alloc] init];
  if (![editor loadForContext:context])
    return nil;
  return editor;
}

- (BOOL)loadForContext:(RDLEditingContext *)context {
  _context = context;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLRenderInputsEditor"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  if (![nib instantiateWithOwner:self topLevelObjects:NULL])
    return NO;
  RDLOwnWindow(_window);
  RDLDocument *document = _context.document;
  _paramsAsFound = [document.paramValues copy] ?: @{};
  _multiParamsAsFound = [document.multiParamValues copy] ?: @{};
  [self build];
  return YES;
}

#pragma mark - What it asks for

- (NSTextField *)label:(NSString *)text at:(NSRect)frame bold:(BOOL)bold {
  NSTextField *l = [[NSTextField alloc] initWithFrame:frame];
  [l setBezeled:NO];
  [l setDrawsBackground:NO];
  [l setEditable:NO];
  [l setSelectable:NO];
  [l setStringValue:text ?: @""];
  [l setFont:bold ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:10]];
  [[l cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  return l;
}

- (void)build {
  RDLReport *report = _context.report;
  _stack = [[RDLInputsStack alloc] initWithFrame:NSMakeRect(0, 0, kRowWidth + 2 * kRowLeft, 10)];
  _documentFields = [NSMutableArray array];
  _documentsAsFound = [NSMutableArray array];
  _readsPops = [NSMutableArray array];
  CGFloat y = kRowGap;

  [_stack addSubview:[self label:@"Parameters"
                              at:NSMakeRect(kRowLeft, y, 180, 16)
                            bold:YES]];
  // Back to what the report itself says: handy when a value was typed to try
  // something and the question is now what the report does on its own.
  _defaultsButton = [[NSButton alloc] initWithFrame:NSMakeRect(kRowLeft + kRowWidth - 190, y - 4,
                                                               190, 22)];
  [_defaultsButton setTitle:@"Use the report's defaults"];
  [_defaultsButton setBezelStyle:NSRoundedBezelStyle];
  [_defaultsButton setFont:[NSFont systemFontOfSize:11]];
  [_defaultsButton setTarget:self];
  [_defaultsButton setAction:@selector(useReportDefaults:)];
  [_stack addSubview:_defaultsButton];
  y += 22;
  _prompts = [[RDLParameterPrompts alloc] initWithFrame:NSMakeRect(kRowLeft, y, kRowWidth, 0)
                                               document:_context.document];
  // One column however long it grows: the panel scrolls, so a report that asks
  // for eight parameters is eight rows rather than three columns of stubs.
  _prompts.columnHeight = 0;
  __weak RDLRenderInputsEditor *weakSelf = self;
  _prompts.whenValueGiven = ^{
    [weakSelf rebuildPrompts];
  };
  CGFloat asked = [_prompts reload];
  if ([_prompts askedCount] == 0) {
    [_stack addSubview:[self label:[report.parameters count]
                                       ? @"This report asks for no parameters."
                                       : @"This report has no parameters."
                                at:NSMakeRect(kRowLeft, y, kRowWidth, 16)
                              bold:NO]];
    y += 22;
  } else {
    [_prompts setFrameOrigin:NSMakePoint(kRowLeft, y)];
    [_stack addSubview:_prompts];
    y += asked + kRowGap;
  }

  y += kRowGap;
  [_stack addSubview:[self label:@"Data" at:NSMakeRect(kRowLeft, y, kRowWidth, 16) bold:YES]];
  y += 18;
  // Why the data is here at all: this kit reads documents on this machine, so
  // where a dataset reads from is as much the reader's to give as a parameter
  // value is. A report that arrives naming `invoices.json` is asking for a
  // file, and this is where it is handed over.
  [_stack addSubview:[self label:@"Each dataset reads a document on this machine."
                              at:NSMakeRect(kRowLeft, y, kRowWidth, 14)
                            bold:NO]];
  y += 20;
  if ([report.dataSources count] == 0) {
    [_stack addSubview:[self label:@"This report reads no data."
                                at:NSMakeRect(kRowLeft, y, kRowWidth, 16)
                              bold:NO]];
    y += 22;
  }
  NSMutableArray<RDLDataSource *> *sources = [NSMutableArray array];
  for (RDLDataSource *source in report.dataSources) {
    [sources addObject:source];
    y = [self addRowForSource:source atY:y];
  }
  _sources = sources;

  [_stack setFrameSize:NSMakeSize(kRowWidth + 2 * kRowLeft, y + kRowGap)];
  [_scroll setDocumentView:_stack];
  [_headingLabel setStringValue:@"What this report needs before it can be rendered."];
}

// One data source: what it is called and reads with, the file it reads, and a
// button to pick one. A provider this kit cannot read is shown as the file has
// it and left alone -- there is no document to choose for a SQL connection.
- (CGFloat)addRowForSource:(RDLDataSource *)source atY:(CGFloat)y {
  RDLDataProviderKind kind = RDLDataProviderKindFromString(source.dataProvider);
  NSDictionary *properties = RDLConnectionProperties(source.connectString);
  NSString *inlineText = kind == RDLDataProviderKindUnspecified
                             ? nil
                             : properties[RDLInlineKeyForProviderKind(kind)];
  NSString *document = kind == RDLDataProviderKindUnspecified
                           ? nil
                           : properties[RDLDocumentKeyForProviderKind(kind)];
  NSString *what = [NSString stringWithFormat:@"%@  ·  %@", source.name ?: @"",
                                              source.dataProvider ?: @"Unknown"];
  [_stack addSubview:[self label:what at:NSMakeRect(kRowLeft, y, kRowWidth, 14) bold:NO]];
  y += 16;

  // Which of the two it reads. A report worth testing keeps a few
  // representative rows for checking the layout and names the real document as
  // well; this is the say in which of them a render uses, and neither is lost
  // by choosing the other.
  NSPopUpButton *which = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kRowLeft, y, 220, 22)
                                                    pullsDown:NO];
  if ([inlineText length]) {
    [which addItemWithTitle:@"The data kept in the report"];
    [[which lastItem] setTag:RDLDocumentSourceEmbedded];
  }
  [which addItemWithTitle:@"A file"];
  [[which lastItem] setTag:RDLDocumentSourceFile];
  RDLDocumentSource reads = RDLDocumentSourceOfProperties(properties, kind);
  if ([which indexOfItemWithTag:reads] >= 0)
    [which selectItemAtIndex:[which indexOfItemWithTag:reads]];
  [which setEnabled:kind != RDLDataProviderKindUnspecified && [which numberOfItems] > 1];
  [which setTag:(NSInteger)[_documentFields count]];
  [_stack addSubview:which];
  [_readsPops addObject:which];
  y += 26;

  NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(kRowLeft, y, kRowWidth - 96, 22)];
  [field setStringValue:document ?: @""];
  [field setDelegate:self];
  [field setTag:(NSInteger)[_documentFields count]];
  if ([[field cell] respondsToSelector:@selector(setPlaceholderString:)])
    [[field cell] setPlaceholderString:[inlineText length] ? @"kept in the report"
                                                           : @"no document yet"];
  [field setToolTip:source.connectString ?: @""];
  NSButton *choose = [[NSButton alloc] initWithFrame:NSMakeRect(kRowLeft + kRowWidth - 88, y, 88, 22)];
  [choose setTitle:@"Choose…"];
  [choose setBezelStyle:NSRoundedBezelStyle];
  [choose setFont:[NSFont systemFontOfSize:11]];
  [choose setTarget:self];
  [choose setAction:@selector(chooseDocument:)];
  [choose setTag:(NSInteger)[_documentFields count]];
  if (kind == RDLDataProviderKindUnspecified) {
    // Nothing here can be given a file: it is a connection this kit does not
    // read, kept as the file has it.
    [field setEditable:NO];
    [field setStringValue:source.connectString ?: @""];
    [choose setEnabled:NO];
  }
  [_stack addSubview:field];
  [_stack addSubview:choose];
  [_documentFields addObject:field];
  [_documentsAsFound addObject:document ?: @""];
  return y + 28;
}

// Which of the two the row says it reads: what was chosen, or the file when a
// row offers no choice.
- (RDLDocumentSource)sourceReadsAtIndex:(NSUInteger)index {
  if (index >= [_readsPops count])
    return RDLDocumentSourceUnspecified;
  NSInteger tag = [[_readsPops[index] selectedItem] tag];
  return tag == RDLDocumentSourceEmbedded ? RDLDocumentSourceEmbedded : RDLDocumentSourceFile;
}

- (NSArray<NSPopUpButton *> *)readsPops {
  return [_readsPops copy] ?: @[];
}

- (NSArray<NSTextField *> *)documentFields {
  return [_documentFields copy] ?: @[];
}

// A value given may change what a later parameter accepts, and what is wrong
// with one: the prompts are built again, and the rows below them move with
// whatever height they come out.
- (void)rebuildPrompts {
  CGFloat was = NSHeight([_prompts frame]);
  CGFloat now = [_prompts reload];
  CGFloat moved = now - was;
  if (fabs(moved) < 0.5)
    return;
  CGFloat below = NSMaxY([_prompts frame]);
  for (NSView *v in [_stack subviews]) {
    if (v == _prompts || NSMinY([v frame]) < below - 0.5)
      continue;
    [v setFrameOrigin:NSMakePoint(NSMinX([v frame]), NSMinY([v frame]) + moved)];
  }
  [_stack setFrameSize:NSMakeSize(NSWidth([_stack frame]), NSHeight([_stack frame]) + moved)];
}

#pragma mark - Choosing a file

- (void)chooseDocument:(id)sender {
  NSInteger which = [sender isKindOfClass:[NSControl class]] ? [(NSControl *)sender tag] : -1;
  if (which < 0 || which >= (NSInteger)[_documentFields count])
    return;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:NO];
  [panel setTitle:@"Choose the document this data source reads"];
  if ([panel runModal] != NSModalResponseOK)
    return;
  NSString *path = [[panel URL] path];
  if ([path length] == 0)
    return;
  [_documentFields[(NSUInteger)which] setStringValue:[self pathForField:path]];
  // A file chosen is a file to read: choosing one and then finding the render
  // still on the data kept in the report is the kind of thing nobody reports
  // as a bug, they just stop trusting the panel.
  NSPopUpButton *reads = which < (NSInteger)[_readsPops count] ? _readsPops[(NSUInteger)which] : nil;
  if ([reads indexOfItemWithTag:RDLDocumentSourceFile] >= 0)
    [reads selectItemAtIndex:[reads indexOfItemWithTag:RDLDocumentSourceFile]];
}

// A document beside the report is named as it is, so a report and its data
// move together; anything else keeps its full path.
- (NSString *)pathForField:(NSString *)path {
  NSString *beside = [[_context.document.fileURL path] stringByDeletingLastPathComponent];
  if ([beside length] && [path hasPrefix:[beside stringByAppendingString:@"/"]])
    return [path substringFromIndex:[beside length] + 1];
  return path;
}

// Every value given goes, so the report's own defaults are worked out again
// and the prompts show what a reader with no say would see.
- (void)useReportDefaults:(id)sender {
  RDL_UNUSED(sender);
  [_context.document clearGivenParameterValues];
  [self rebuildPrompts];
}

#pragma mark - Leaving

- (void)accept:(id)sender {
  RDL_UNUSED(sender);
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  RDL_UNUSED(sender);
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

// Cancel: every value back as it was found. The report itself has not been
// touched -- the documents are only written by -apply -- so this is all there
// is to undo.
- (void)putValuesBack {
  RDLDocument *document = _context.document;
  [document clearGivenParameterValues];
  for (NSString *name in _paramsAsFound)
    [document setParamValue:_paramsAsFound[name] forName:name];
  for (NSString *name in _multiParamsAsFound)
    [document setParamValues:_multiParamsAsFound[name] forName:name];
}

- (BOOL)apply {
  BOOL any = NO;
  [_context.editor beginGroup:@"Data Documents"];
  for (NSUInteger i = 0; i < [_sources count] && i < [_documentFields count]; i++) {
    RDLDataSource *source = _sources[i];
    RDLDataProviderKind kind = RDLDataProviderKindFromString(source.dataProvider);
    if (kind == RDLDataProviderKindUnspecified)
      continue;
    NSString *document = [[_documentFields[i] stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *asFound = RDLConnectionProperties(source.connectString);
    BOOL sameFile = [document isEqualToString:_documentsAsFound[i]];
    BOOL sameSay = RDLDocumentSourceOfProperties(asFound, kind) == [self sourceReadsAtIndex:i];
    if (sameFile && sameSay)
      continue;
    // The file and the data kept in the report both stay: what changes is
    // which of them this source reads, so a report can carry its test rows and
    // still be run against the real document.
    NSMutableDictionary *properties =
        [RDLConnectionProperties(source.connectString) mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([document length])
      properties[RDLDocumentKeyForProviderKind(kind)] = document;
    else
      [properties removeObjectForKey:RDLDocumentKeyForProviderKind(kind)];
    NSDictionary *said = RDLPropertiesReading(properties, kind, [self sourceReadsAtIndex:i]);
    [_context.editor setProvider:source.dataProvider
                   connectString:RDLConnectionString(said)
                    ofDataSource:source];
    any = YES;
  }
  [_context.editor endGroup];
  RDL_UNUSED(any);
  return YES;
}

@end
