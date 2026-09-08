#import "RDLDataView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLDocument.h"
#import "RDLKit.h"

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

@interface RDLDataView () <NSTextFieldDelegate>
@property (nonatomic, strong) NSView *stack;
@end

@implementation RDLDataView {
  BOOL _reloading;
  // Set while this pane is writing a parameter value. The document publishes
  // that as a data change, and rebuilding the pane in response would tear down
  // the control the person is still using -- which is why a popup's choice
  // appeared not to take and a field needed Return to commit.
  BOOL _applyingParameter;
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
  if (_applyingParameter)
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
  NSArray *subs = [_stack.subviews copy];
  for (NSView *v in subs)
    [v removeFromSuperview];
  RDLDocument *doc = _document;
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
    // Prompt is what a parameter is called when it is being asked for; the
    // name is what expressions call it, and goes in the tooltip with the type.
    NSString *asked = [p.prompt length] ? p.prompt : (p.name ?: @"");
    NSTextField *l = [self label:asked frame:NSMakeRect(10, y, 220, 14)];
    [l setFont:[NSFont userFontOfSize:10]];
    [l setToolTip:[NSString stringWithFormat:@"Parameters!%@.Value — %@%@", p.name ?: @"",
                                             RDLStringFromParameterDataType(p.dataType)
                                                 ?: @"String",
                                             p.multiValue ? @", one of several" : @""]];
    [_stack addSubview:l];
    y += 16;
    NSString *current = doc.paramValues[p.name] ?: ([p.defaultValue source] ?: @"");
    if ([p.validValues count]) {
      // A parameter that lists what it accepts is chosen from, not typed into
      // -- which is what ValidValues is for, and what stops a typo rendering
      // an empty report.
      NSPopUpButton *pop =
          [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
      for (RDLValue *v in p.validValues)
        [pop addItemWithTitle:[v source] ?: @""];
      if ([pop itemWithTitle:current])
        [pop selectItemWithTitle:current];
      [pop setTag:tag];
      [pop setTarget:self];
      [pop setAction:@selector(paramChanged:)];
      [_stack addSubview:pop];
    } else {
      NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, 220, 22)];
      // The default as written: an expression shows its source, which is what
      // the user would have to type to restore it.
      [f setStringValue:current];
      [f setTag:tag];
      [f setDelegate:self];
      [f setTarget:self];
      [f setAction:@selector(paramChanged:)];
      [_stack addSubview:f];
    }
    y += 28;
    tag += 1;
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

// A parameter's value, from whichever control was offered for it: a popup
// when the report says what it accepts, a field when it does not.
- (void)paramChanged:(NSControl *)sender {
  if (_reloading)
    return;
  NSArray *params = _document.report.parameters;
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[params count])
    return;
  NSString *value = [sender isKindOfClass:[NSPopUpButton class]]
                        ? [(NSPopUpButton *)sender titleOfSelectedItem]
                        : [sender stringValue];
  _applyingParameter = YES;
  [_document setParamValue:value forName:[params[i] name]];
  _applyingParameter = NO;
}

// As it is typed, rather than only on Return: a parameter value is something
// to try, and the preview beside it is the answer. Nothing is rebuilt while
// this happens, so the field keeps the caret it had.
- (void)controlTextDidChange:(NSNotification *)note {
  id sender = [note object];
  if ([sender isKindOfClass:[NSControl class]])
    [self paramChanged:sender];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  id sender = [obj object];
  if ([sender isKindOfClass:[NSTextField class]])
    [self paramChanged:sender];
}

@end
