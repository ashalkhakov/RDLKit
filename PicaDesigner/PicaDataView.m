#import "PicaDataView.h"
#import "PicaChange.h"
#import "PicaDocument.h"
#import "PicaDocument.h"
#import "PicaKit.h"

@interface PicaDataView () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) NSView *stack;
@property (nonatomic, strong) NSTextView *jsonView;
@property (nonatomic, copy) NSString *editingDataset;
@end

@implementation PicaDataView {
  BOOL _reloading;
}

- (instancetype)initWithFrame:(NSRect)frame document:(PicaDocument *)document {
  self = [super initWithFrame:frame];
  if (self)
    [self setDocument:document];
  return self;
}

- (void)setDocument:(PicaDocument *)document {
  if (_document == document)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _document = document;
  if (_stack == nil) {
    _stack = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
    [self addSubview:_stack];
  }
  if (document == nil)
    return;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(documentDidChange:)
                                               name:PicaDocumentDidChangeNotification
                                             object:document];
  [self reload];
}

// This pane shows parameters and datasets only, so an item or band edit is
// none of its business. Rebuilding on every change is what made the old
// design need re-entrancy guards everywhere.
- (void)documentDidChange:(NSNotification *)note {
  PicaChange *change = [note userInfo][PicaChangeKey];
  if (change.scope == RDLChangeScopeReport || change.scope == RDLChangeScopeData)
    [self reload];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
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

- (void)reload {
  // Not a notification guard: tearing down the subviews below can end an
  // active field edit, which calls back into -paramChanged: mid-rebuild.
  if (_reloading)
    return;
  _reloading = YES;
  NSArray *subs = [_stack.subviews copy];
  for (NSView *v in subs)
    [v removeFromSuperview];
  PicaDocument *doc = _document;
  RDLReport *report = _document.report;
  CGFloat y = 8;
  [_stack addSubview:[self label:@"Parameters" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  if ([report.parameters count] == 0) {
    NSTextField *empty = [self label:@"No parameters on this report." frame:NSMakeRect(10, y, 220, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 22;
  }
  NSInteger tag = 0;
  for (RDLParameter *p in report.parameters) {
    NSTextField *l = [self label:p.name frame:NSMakeRect(10, y, 220, 14)];
    [l setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:l];
    y += 16;
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, 220, 22)];
    // The default as written: an expression shows its source, which is what
    // the user would have to type to restore it.
    [f setStringValue:doc.paramValues[p.name] ?: ([p.defaultValue source] ?: @"")];
    [f setTag:tag];
    [f setDelegate:self];
    [f setTarget:self];
    [f setAction:@selector(paramChanged:)];
    [_stack addSubview:f];
    y += 28;
    tag += 1;
  }
  y += 8;
  [_stack addSubview:[self label:@"Datasets" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  if ([report.dataSets count] == 0) {
    NSTextField *empty =
        [self label:@"Add a tablix or bind JSON to create a dataset." frame:NSMakeRect(10, y, 220, 32)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 36;
  }
  NSInteger dsi = 0;
  for (RDLDataSet *ds in report.dataSets) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22)];
    [b setTitle:[NSString stringWithFormat:@"%@  ·  %lu rows", ds.name, (unsigned long)[ds.rows count]]];
    [b setBezelStyle:NSShadowlessSquareBezelStyle];
    [b setTarget:self];
    [b setAction:@selector(toggleDataset:)];
    [b setTag:dsi];
    [_stack addSubview:b];
    y += 24;
    NSTextField *fields = [self label:[ds.fields componentsJoinedByString:@"  "]
                                frame:NSMakeRect(10, y, 220, 16)];
    [fields setFont:[NSFont userFontOfSize:9]];
    [_stack addSubview:fields];
    y += 20;
    if ([_editingDataset isEqualToString:ds.name]) {
      NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, y, 220, 140)];
      [sv setHasVerticalScroller:YES];
      [sv setBorderType:NSBezelBorder];
      NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 140)];
      [tv setFont:[NSFont userFixedPitchFontOfSize:10]];
      [tv setDelegate:self];
      NSData *json = [NSJSONSerialization dataWithJSONObject:(ds.rows ?: @[])
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
      NSString *s = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
      [tv setString:s];
      [sv setDocumentView:tv];
      [_stack addSubview:sv];
      _jsonView = tv;
      y += 148;
    }
    dsi += 1;
  }
  [_stack setFrame:NSMakeRect(0, 0, NSWidth(self.bounds), MAX(y + 12, NSHeight(self.bounds)))];
  [self setFrameSize:_stack.frame.size];
  _reloading = NO;
}

- (void)toggleDataset:(NSButton *)sender {
  if (_reloading)
    return;
  NSArray *dataSets = _document.report.dataSets;
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[dataSets count])
    return;
  NSString *name = [dataSets[i] name];
  if ([_editingDataset isEqualToString:name])
    _editingDataset = nil;
  else
    _editingDataset = name;
  [self reload];
}

- (void)paramChanged:(NSTextField *)sender {
  if (_reloading)
    return;
  NSArray *params = _document.report.parameters;
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[params count])
    return;
  [_document setParamValue:[sender stringValue]
                           forName:[params[i] name]];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  id sender = [obj object];
  if ([sender isKindOfClass:[NSTextField class]])
    [self paramChanged:sender];
}

- (void)textDidEndEditing:(NSNotification *)notification {
  (void)notification;
  if (_reloading || _jsonView == nil || _editingDataset == nil)
    return;
  NSError *err = nil;
  if (![_document bindJSON:[_jsonView string]
                    toDataSetNamed:_editingDataset
                             error:&err]) {
    // Bad JSON while typing is expected; surface it without a modal.
    NSLog(@"Pica: dataset JSON not applied: %@", err.localizedDescription);
  }
}

@end
