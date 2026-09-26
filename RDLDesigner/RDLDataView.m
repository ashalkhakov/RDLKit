#import "RDLDataView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLKit.h"
#import "RDLParameterPrompts.h"

// The pane lays out downwards from the top, so the view it lays out into has
// to agree about which way is down. Without this the stack is an ordinary
// view, y grows upwards inside it, and the first thing added -- the
// Parameters heading -- ends up at the bottom with everything above it in
// reverse.
@interface RDLFlippedStack : NSView
@end

@implementation RDLFlippedStack
- (BOOL)isFlipped {
  return YES;
}
@end

@interface RDLDataView ()
@property (nonatomic, strong) NSView *stack;
@end

@implementation RDLDataView {
  BOOL _reloading;
  // The prompts, which are a view of their own because the preview's bar asks
  // the same question this pane does.
  RDLParameterPrompts *_prompts;
}

- (instancetype)initWithFrame:(NSRect)frame document:(RDLDocument *)document {
  self = [super initWithFrame:frame];
  if (self)
    [self setDocument:document];
  return self;
}

- (void)setDocument:(RDLDocument *)document {
  if (_document == document)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _document = document;
  if (_stack == nil) {
    _stack = [[RDLFlippedStack alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
    [self addSubview:_stack];
  }
  if (_prompts == nil) {
    __weak RDLDataView *weakSelf = self;
    _prompts = [[RDLParameterPrompts alloc] initWithFrame:NSMakeRect(0, 0, 240, 0) document:nil];
    _prompts.whenValueGiven = ^{
      // What a query read may have changed with the value, so the whole pane
      // is built again and not only the prompts.
      [weakSelf reload];
    };
  }
  _prompts.document = document;
  if (document == nil)
    return;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(documentDidChange:)
                                               name:RDLDocumentDidChangeNotification
                                             object:document];
  [self reload];
}

// This pane shows parameters and datasets only, so an item or band edit is
// none of its business. Rebuilding on every change is what made the old
// design need re-entrancy guards everywhere.
- (void)documentDidChange:(NSNotification *)note {
  // Our own edit: the controls already show what was just written, and the
  // one being used has to survive the writing.
  if (_prompts.applying)
    return;
  RDLChange *change = [note userInfo][RDLChangeKey];
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
  for (NSView *v in [_stack.subviews copy])
    [v removeFromSuperview];
  RDLReport *report = _document.report;
  CGFloat y = 8;
  [_stack addSubview:[self label:@"Parameters" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  CGFloat asked = [_prompts reload];
  if ([_prompts askedCount] == 0) {
    NSTextField *empty = [self label:[report.parameters count] ? @"This report asks for no parameters."
                                                               : @"No parameters on this report."
                               frame:NSMakeRect(10, y, 220, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 22;
  } else {
    [_prompts setFrameOrigin:NSMakePoint(0, y)];
    [_stack addSubview:_prompts];
    y += asked;
  }
  y += 8;
  // What the report will read, and what it has read: a summary, not an editor.
  // Datasets and the sources they come from are set up in the designer's own
  // panes; here they are the inputs a render is about to use, and the only
  // thing to say about them is whether they have any rows yet.
  [_stack addSubview:[self label:@"Data" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  if ([report.dataSets count] == 0) {
    NSTextField *empty = [self label:@"This report has no datasets."
                               frame:NSMakeRect(10, y, 220, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 22;
  }
  for (RDLDataSet *ds in report.dataSets) {
    NSTextField *line = [self label:[NSString stringWithFormat:@"%@  ·  %lu row%@", ds.name ?: @"",
                                                               (unsigned long)[ds.rows count],
                                                               [ds.rows count] == 1 ? @"" : @"s"]
                              frame:NSMakeRect(10, y, 220, 16)];
    [line setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:line];
    y += 18;
    RDLDataSource *source = [report dataSourceNamed:ds.dataSourceName];
    NSString *from = source == nil
                         ? ([ds.dataSourceName length]
                                ? [NSString stringWithFormat:@"no data source named '%@'",
                                                             ds.dataSourceName]
                                : @"rows supplied in code")
                         : [NSString stringWithFormat:@"%@ · %@", source.dataProvider ?: @"",
                                                      source.connectString ?: @""];
    NSTextField *detail = [self label:from frame:NSMakeRect(10, y, 220, 16)];
    [detail setFont:[NSFont userFontOfSize:9]];
    [detail setToolTip:from];
    [[detail cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [_stack addSubview:detail];
    y += 20;
  }
  [_stack setFrame:NSMakeRect(0, 0, NSWidth(self.bounds), MAX(y + 12, NSHeight(self.bounds)))];
  [self setFrameSize:_stack.frame.size];
  _reloading = NO;
}

#pragma mark - The prompts, driven from outside

- (void)paramChanged:(NSControl *)sender {
  [_prompts paramChanged:sender];
}

- (void)severalValuesChanged:(id)sender {
  [_prompts severalValuesChanged:sender];
}

- (void)controlTextDidChange:(NSNotification *)note {
  [_prompts controlTextDidChange:note];
}

@end
