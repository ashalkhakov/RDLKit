#import "PicaGeneratorWindow.h"
#import "PicaDocument.h"
#import "PicaChange.h"
#import "PicaDataView.h"
#import "PicaSamples.h"
#import "PicaCompatibility.h"
#import "PicaKit.h"

@interface PicaGeneratorWindow ()
@property (nonatomic, strong, readwrite) PicaDocument *reportDocument;
@property (nonatomic, strong) RDLView *preview;
@property (nonatomic, strong) PicaDataView *dataView;
@property (nonatomic, strong) NSPopUpButton *samplePopup;
@end

@implementation PicaGeneratorWindow

- (instancetype)initWithDocument:(PicaDocument *)document {
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(80, 40, 1100, 740)
                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                           NSResizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [win setTitle:@"Pica Generator"];
  self = [super initWithWindow:win];
  if (self) {
    _reportDocument = document;
    // The window controller is the window's delegate, which puts it in the
    // responder chain: menu actions with a nil target reach whichever window
    // is in front, so the app delegate does not have to ask which that is.
    [win setDelegate:(id)self];
    [self buildUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:PicaDocumentDidChangeNotification
                                               object:document];
    [self updateForDocument];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)documentDidChange:(NSNotification *)note {
  PicaChange *change = [note userInfo][PicaChangeKey];
  // Anything that can alter the output re-lays out; a plain rename does not.
  if ([change affectsLayout])
    [self reloadPreview];
  [self updateWindowTitle];
}

#pragma mark - UI

- (NSButton *)buttonTitled:(NSString *)title
                    action:(SEL)action
                     frame:(NSRect)frame
                      mask:(NSUInteger)mask {
  NSButton *b = [[NSButton alloc] initWithFrame:frame];
  [b setTitle:title];
  [b setBezelStyle:NSRoundedBezelStyle];
  [b setTarget:self];
  [b setAction:action];
  [b setAutoresizingMask:mask];
  return b;
}

- (void)buildUI {
  NSView *content = [[self window] contentView];
  NSRect b = [content bounds];
  CGFloat top = NSHeight(b) - 36;

  [content addSubview:[self buttonTitled:@"Open RDL"
                                  action:@selector(openRdl:)
                                   frame:NSMakeRect(12, top, 90, 26)
                                    mask:NSViewMinYMargin]];

  _samplePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(108, top, 200, 26)
                                            pullsDown:YES];
  [_samplePopup addItemWithTitle:@"Sample"];
  for (NSDictionary *sample in [PicaSamples catalog])
    [_samplePopup addItemWithTitle:sample[@"title"]];
  [_samplePopup setTarget:self];
  [_samplePopup setAction:@selector(samplePicked:)];
  [_samplePopup setAutoresizingMask:NSViewMinYMargin];
  [content addSubview:_samplePopup];

  [content addSubview:[self buttonTitled:@"Bind JSON"
                                  action:@selector(bindJSONFile:)
                                   frame:NSMakeRect(316, top, 100, 26)
                                    mask:NSViewMinYMargin]];

  // One button per backend the kit offers, so a new backend appears here
  // without touching this method.
  CGFloat x = NSWidth(b) - 90;
  for (id<RDLBackend> backend in [_reportDocument exportBackends]) {
    NSButton *button = [self buttonTitled:[backend.pathExtension uppercaseString]
                                   action:@selector(exportFrontmost:)
                                    frame:NSMakeRect(x, top, 80, 26)
                                     mask:NSViewMinXMargin | NSViewMinYMargin];
    [button setTitle:[backend.pathExtension uppercaseString]];
    [content addSubview:button];
    x -= 90;
  }

  NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(b), NSHeight(b) - 44)];
  [split setVertical:YES];
  [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
  [inputScroll setHasVerticalScroller:YES];
  [inputScroll setBorderType:NSBezelBorder];
  [inputScroll setAutoresizingMask:NSViewHeightSizable];
  // The same pane the designer uses; this window used to carry its own copy.
  _dataView = [[PicaDataView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)
                                         document:_reportDocument];
  [inputScroll setDocumentView:_dataView];

  NSScrollView *previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 800, 400)];
  [previewScroll setHasVerticalScroller:YES];
  [previewScroll setHasHorizontalScroller:YES];
  [previewScroll setBorderType:NSBezelBorder];
  [previewScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _preview = [[RDLView alloc] initWithFrame:NSMakeRect(0, 0, 612, 792)];
  [previewScroll setDocumentView:_preview];

  [split addSubview:inputScroll];
  [split addSubview:previewScroll];
  [content addSubview:split];
}

- (void)reloadPreview {
  _preview.report = _reportDocument.report;
  _preview.paramValues = _reportDocument.paramValues;
  [_preview reloadLayout];
}

- (void)updateWindowTitle {
  [[self window] setTitle:[NSString stringWithFormat:@"Pica Generator — %@",
                                                     _reportDocument.report.name ?: @"Report"]];
}

- (void)updateForDocument {
  [_dataView reload];
  [self reloadPreview];
  [self updateWindowTitle];
}

#pragma mark - Loading

- (void)samplePicked:(NSPopUpButton *)sender {
  NSInteger i = [sender indexOfSelectedItem] - 1;
  NSArray *catalog = [PicaSamples catalog];
  if (i >= 0 && i < (NSInteger)[catalog count]) {
    [_reportDocument loadReport:[PicaSamples reportWithId:catalog[(NSUInteger)i][@"id"]]];
    [self updateForDocument];
  }
  [sender selectItemAtIndex:0];
}

- (void)openRdl:(id)sender {
  PICA_UNUSED(sender);
  [self openDocument:sender];
}

// A menu action too: this window is in the responder chain.
- (void)openDocument:(id)sender {
  PICA_UNUSED(sender);
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"rdl", @"rdlc", @"xml" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] != NSOKButton)
    return;
  NSError *err = nil;
  if (![_reportDocument openURL:[p URL] error:&err]) {
    [self presentError:err title:@"Could not open RDL"];
    return;
  }
  [self updateForDocument];
}

- (void)bindJSONFile:(id)sender {
  PICA_UNUSED(sender);
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"json" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] != NSOKButton)
    return;
  NSError *err = nil;
  NSString *json = [NSString stringWithContentsOfURL:[p URL]
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
  if (json == nil) {
    [self presentError:err title:@"Could not read JSON"];
    return;
  }
  // Bind to the first dataset, creating one if the report has none.
  RDLDataSet *first = [_reportDocument.report.dataSets firstObject];
  NSString *name = first.name ?: @"Data";
  if (![_reportDocument bindJSON:json toDataSetNamed:name error:&err])
    [self presentError:err title:@"Could not bind JSON"];
}

#pragma mark - Export

- (void)exportFrontmost:(NSButton *)sender {
  // The button's title is the backend's extension, so one action serves all.
  [self exportUsingBackend:
            [_reportDocument exportBackendForPathExtension:[[sender title] lowercaseString]]];
}

- (void)exportPDF:(id)sender {
  PICA_UNUSED(sender);
  [self exportUsingBackend:[_reportDocument exportBackendForPathExtension:@"pdf"]];
}

- (void)exportHTML:(id)sender {
  PICA_UNUSED(sender);
  [self exportUsingBackend:[_reportDocument exportBackendForPathExtension:@"html"]];
}

- (void)exportUsingBackend:(id<RDLBackend>)backend {
  if (backend == nil)
    return;
  NSMutableArray *types = [NSMutableArray array];
  for (id<RDLBackend> b in [_reportDocument exportBackends])
    [types addObject:b.pathExtension];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:types];
  [p setNameFieldStringValue:[_reportDocument suggestedFileNameForBackend:backend]];
  if ([p runModal] != NSOKButton)
    return;
  NSURL *url = [p URL];
  id<RDLBackend> chosen =
      [_reportDocument exportBackendForPathExtension:[url pathExtension]] ?: backend;
  NSError *err = nil;
  if (![_reportDocument exportUsingBackend:chosen toURL:url error:&err])
    [self presentError:err title:@"Could not export"];
}

- (void)presentError:(NSError *)error title:(NSString *)title {
  NSAlert *a = [[NSAlert alloc] init];
  [a setMessageText:title];
  [a setInformativeText:error.localizedDescription ?: @""];
  [a runModal];
}

@end
