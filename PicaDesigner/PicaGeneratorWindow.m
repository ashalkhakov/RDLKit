#import "PicaGeneratorWindow.h"
#import "PicaSamples.h"
#import "PicaKit.h"

@interface PicaFlippedView : NSView
@end
@implementation PicaFlippedView
- (BOOL)isFlipped {
  return YES;
}
@end

@interface PicaGeneratorWindow () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *paramValues;
@property (nonatomic, strong) RDLView *preview;
@property (nonatomic, strong) NSScrollView *previewScroll;
@property (nonatomic, strong) NSScrollView *inputScroll;
@property (nonatomic, strong) PicaFlippedView *inputPane;
@property (nonatomic, strong) NSTextView *jsonView;
@property (nonatomic, copy) NSString *editingDataset;
@property (nonatomic, strong) NSPopUpButton *samplePopup;
@end

@implementation PicaGeneratorWindow

- (instancetype)init {
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(80, 40, 1100, 740)
                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                           NSResizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [win setTitle:@"Pica Generator"];
  self = [super initWithWindow:win];
  if (self) {
    _paramValues = @{};
    [self buildUI];
  }
  return self;
}

- (void)buildUI {
  NSView *content = [[self window] contentView];
  NSRect b = [content bounds];

  NSButton *open = [[NSButton alloc] initWithFrame:NSMakeRect(12, NSHeight(b) - 36, 90, 26)];
  [open setTitle:@"Open RDL"];
  [open setBezelStyle:NSRoundedBezelStyle];
  [open setTarget:self];
  [open setAction:@selector(openRdl:)];
  [open setAutoresizingMask:NSViewMinYMargin];
  [content addSubview:open];

  _samplePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(108, NSHeight(b) - 36, 200, 26)
                                            pullsDown:YES];
  [_samplePopup addItemWithTitle:@"Sample"];
  NSArray *cat = [PicaSamples catalog];
  for (NSDictionary *s in cat)
    [_samplePopup addItemWithTitle:s[@"title"]];
  [_samplePopup setTarget:self];
  [_samplePopup setAction:@selector(samplePicked:)];
  [_samplePopup setAutoresizingMask:NSViewMinYMargin];
  [content addSubview:_samplePopup];

  NSButton *json = [[NSButton alloc] initWithFrame:NSMakeRect(316, NSHeight(b) - 36, 100, 26)];
  [json setTitle:@"Bind JSON"];
  [json setBezelStyle:NSRoundedBezelStyle];
  [json setTarget:self];
  [json setAction:@selector(bindJSONFile:)];
  [json setAutoresizingMask:NSViewMinYMargin];
  [content addSubview:json];

  NSButton *html = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 180, NSHeight(b) - 36, 80, 26)];
  [html setTitle:@"HTML"];
  [html setBezelStyle:NSRoundedBezelStyle];
  [html setTarget:self];
  [html setAction:@selector(exportHTML:)];
  [html setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:html];

  NSButton *pdf = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 90, NSHeight(b) - 36, 80, 26)];
  [pdf setTitle:@"PDF"];
  [pdf setBezelStyle:NSRoundedBezelStyle];
  [pdf setTarget:self];
  [pdf setAction:@selector(exportPDF:)];
  [pdf setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:pdf];

  NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(b), NSHeight(b) - 44)];
  [split setVertical:YES];
  [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  _inputScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
  [_inputScroll setHasVerticalScroller:YES];
  [_inputScroll setBorderType:NSBezelBorder];
  [_inputScroll setAutoresizingMask:NSViewHeightSizable];
  _inputPane = [[PicaFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
  [_inputScroll setDocumentView:_inputPane];

  _previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 800, 400)];
  [_previewScroll setHasVerticalScroller:YES];
  [_previewScroll setHasHorizontalScroller:YES];
  [_previewScroll setBorderType:NSBezelBorder];
  [_previewScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _preview = [[RDLView alloc] initWithFrame:NSMakeRect(0, 0, 612, 792)];
  [_previewScroll setDocumentView:_preview];

  [split addSubview:_inputScroll];
  [split addSubview:_previewScroll];
  [content addSubview:split];
  [self rebuildInputs];
}

- (NSTextField *)label:(NSString *)t frame:(NSRect)f {
  NSTextField *l = [[NSTextField alloc] initWithFrame:f];
  [l setBezeled:NO];
  [l setDrawsBackground:NO];
  [l setEditable:NO];
  [l setSelectable:NO];
  [l setStringValue:t];
  [l setFont:[NSFont boldSystemFontOfSize:10]];
  return l;
}

- (void)rebuildInputs {
  NSArray *subs = [_inputPane.subviews copy];
  for (NSView *v in subs)
    [v removeFromSuperview];
  CGFloat y = 10;
  [_inputPane addSubview:[self label:@"Inputs" frame:NSMakeRect(10, y, 240, 16)]];
  y += 18;
  NSTextField *hint = [self label:@"RDL is loaded. Bind parameters and JSON datasets, then read the pages."
                            frame:NSMakeRect(10, y, 240, 36)];
  [hint setFont:[NSFont userFontOfSize:10]];
  [_inputPane addSubview:hint];
  y += 40;

  [_inputPane addSubview:[self label:@"Parameters" frame:NSMakeRect(10, y, 240, 16)]];
  y += 20;
  if (_report == nil || [_report.parameters count] == 0) {
    NSTextField *empty = [self label:@"No parameters on this report." frame:NSMakeRect(10, y, 240, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_inputPane addSubview:empty];
    y += 22;
  }
  NSInteger tag = 0;
  for (RDLParameter *p in _report.parameters) {
    NSTextField *l = [self label:p.name frame:NSMakeRect(10, y, 240, 14)];
    [l setFont:[NSFont userFontOfSize:10]];
    [_inputPane addSubview:l];
    y += 16;
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, 240, 22)];
    [f setStringValue:_paramValues[p.name] ?: (p.defaultValue ?: @"")];
    [f setTag:tag];
    [f setDelegate:self];
    [f setTarget:self];
    [f setAction:@selector(paramChanged:)];
    [_inputPane addSubview:f];
    y += 28;
    tag += 1;
  }

  y += 8;
  [_inputPane addSubview:[self label:@"Datasets" frame:NSMakeRect(10, y, 240, 16)]];
  y += 20;
  if (_report == nil || [_report.dataSets count] == 0) {
    NSTextField *empty =
        [self label:@"Bind JSON to create a dataset, or open an RDL that already has one."
              frame:NSMakeRect(10, y, 240, 32)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_inputPane addSubview:empty];
    y += 36;
  }
  NSInteger dsi = 0;
  for (RDLDataSet *ds in _report.dataSets) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(10, y, 240, 22)];
    [b setTitle:[NSString stringWithFormat:@"%@  ·  %lu rows", ds.name, (unsigned long)[ds.rows count]]];
    [b setBezelStyle:NSShadowlessSquareBezelStyle];
    [b setTarget:self];
    [b setAction:@selector(toggleDataset:)];
    [b setTag:dsi];
    [_inputPane addSubview:b];
    y += 24;
    NSString *fields = [ds.fields componentsJoinedByString:@"  "];
    NSTextField *fl = [self label:fields ?: @"" frame:NSMakeRect(10, y, 240, 16)];
    [fl setFont:[NSFont userFontOfSize:9]];
    [_inputPane addSubview:fl];
    y += 20;
    if ([_editingDataset isEqualToString:ds.name]) {
      NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, y, 240, 160)];
      [sv setHasVerticalScroller:YES];
      [sv setBorderType:NSBezelBorder];
      NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 220, 160)];
      [tv setFont:[NSFont userFixedPitchFontOfSize:10]];
      [tv setDelegate:self];
      NSData *json = [NSJSONSerialization dataWithJSONObject:(ds.rows ?: @[])
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
      NSString *s = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
      [tv setString:s];
      [sv setDocumentView:tv];
      [_inputPane addSubview:sv];
      _jsonView = tv;
      y += 168;
    }
    dsi += 1;
  }
  [_inputPane setFrame:NSMakeRect(0, 0, 260, MAX(y + 16, 400))];
}

- (void)reloadPreview {
  _preview.report = _report;
  _preview.paramValues = _paramValues ?: @{};
  [_preview reloadLayout];
}

- (void)loadReport:(RDLReport *)report {
  self.report = report;
  NSMutableDictionary *pv = [NSMutableDictionary dictionary];
  for (RDLParameter *p in report.parameters)
    pv[p.name] = p.defaultValue ?: @"";
  self.paramValues = pv;
  self.editingDataset = [report.dataSets count] ? report.dataSets[0].name : nil;
  [[self window] setTitle:[NSString stringWithFormat:@"Pica Generator — %@", report.name ?: @"Report"]];
  [self rebuildInputs];
  [self reloadPreview];
}

- (void)loadSample:(NSString *)sampleId {
  [self loadReport:[PicaSamples reportWithId:sampleId]];
}

- (BOOL)openURL:(NSURL *)url error:(NSError **)error {
  NSString *xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
  if (xml == nil)
    return NO;
  RDLReport *r = [RDLParser reportFromXMLString:xml error:error];
  if (r == nil)
    return NO;
  [self loadReport:r];
  return YES;
}

- (void)openRdl:(id)sender {
  (void)sender;
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"rdl", @"rdlc", @"xml" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] == NSOKButton) {
    NSError *err = nil;
    if (![self openURL:[p URL] error:&err]) {
      NSAlert *a = [[NSAlert alloc] init];
      [a setMessageText:@"Could not open RDL"];
      [a setInformativeText:err.localizedDescription ?: @""];
      [a runModal];
    }
  }
}

- (void)samplePicked:(NSPopUpButton *)sender {
  NSInteger i = [sender indexOfSelectedItem] - 1;
  NSArray *cat = [PicaSamples catalog];
  if (i < 0 || i >= (NSInteger)[cat count])
    return;
  [self loadSample:cat[i][@"id"]];
  [sender selectItemAtIndex:0];
}

- (void)bindJSONFile:(id)sender {
  (void)sender;
  if (_report == nil)
    return;
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"json" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] != NSOKButton)
    return;
  NSError *err = nil;
  NSString *json = [NSString stringWithContentsOfURL:[p URL] encoding:NSUTF8StringEncoding error:&err];
  if (json == nil) {
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:@"Could not read JSON"];
    [a setInformativeText:err.localizedDescription ?: @""];
    [a runModal];
    return;
  }
  NSString *name = _editingDataset;
  if (name == nil && [_report.dataSets count])
    name = _report.dataSets[0].name;
  if (name == nil)
    name = @"Data";
  [RDLGenerator bindJSONString:json toDataSet:name inReport:_report error:&err];
  self.editingDataset = name;
  [self rebuildInputs];
  [self reloadPreview];
}

- (void)toggleDataset:(NSButton *)sender {
  NSInteger i = [sender tag];
  if (_report == nil || i < 0 || i >= (NSInteger)[_report.dataSets count])
    return;
  NSString *name = _report.dataSets[i].name;
  if ([_editingDataset isEqualToString:name])
    _editingDataset = nil;
  else
    _editingDataset = name;
  [self rebuildInputs];
}

- (void)paramChanged:(NSTextField *)sender {
  if (_report == nil)
    return;
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[_report.parameters count])
    return;
  RDLParameter *p = _report.parameters[i];
  NSMutableDictionary *pv = [_paramValues mutableCopy] ?: [NSMutableDictionary dictionary];
  pv[p.name] = [sender stringValue] ?: @"";
  self.paramValues = pv;
  [self reloadPreview];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  id sender = [obj object];
  if ([sender isKindOfClass:[NSTextField class]])
    [self paramChanged:sender];
}

- (void)textDidEndEditing:(NSNotification *)notification {
  (void)notification;
  if (_jsonView == nil || _editingDataset == nil || _report == nil)
    return;
  NSError *err = nil;
  [RDLGenerator bindJSONString:[_jsonView string] toDataSet:_editingDataset inReport:_report error:&err];
  [self reloadPreview];
}

- (void)exportPDF:(id)sender {
  (void)sender;
  if (_report == nil)
    return;
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"pdf" ]];
  [p setNameFieldStringValue:[(_report.name ?: @"report") stringByAppendingPathExtension:@"pdf"]];
  if ([p runModal] == NSOKButton) {
    NSData *pdf = [RDLGenerator PDFForReport:_report parameters:_paramValues];
    [pdf writeToURL:[p URL] atomically:YES];
  }
}

- (void)exportHTML:(id)sender {
  (void)sender;
  if (_report == nil)
    return;
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"html" ]];
  [p setNameFieldStringValue:[(_report.name ?: @"report") stringByAppendingPathExtension:@"html"]];
  if ([p runModal] == NSOKButton) {
    NSData *html = [RDLGenerator HTMLForReport:_report parameters:_paramValues];
    [html writeToURL:[p URL] atomically:YES];
  }
}

@end
