#import "PicaInspectorView.h"
#import "PicaEditingContext.h"
#import "PicaKit.h"
#import "PicaTablixEditor.h"
#import "PicaExpressionHelper.h"
#import "PicaInspectorFields.h"

// Model-Builder-style inspector: one compact section per selection kind,
// filled from the model on selection change and applied back field by field.
@interface PicaInspectorView () <NSTextFieldDelegate>
@property (nonatomic, strong) PicaEditingContext *context;
// One declaration per field drives both directions; see PicaInspectorFields.
@property (nonatomic, strong) PicaFieldBindings *bindings;
@property (nonatomic, strong) NSTextField *kindLabel;
// Report section
@property (nonatomic, strong) NSView *docBox;
@property (nonatomic, strong) NSTextField *docNameField, *authorField, *descField;
@property (nonatomic, strong) NSPopUpButton *pagePop;
@property (nonatomic, strong) NSTextField *headerHField, *bodyHField, *footerHField, *marginField;
// Band section
@property (nonatomic, strong) NSView *bandBox;
@property (nonatomic, strong) NSTextField *bandHField, *bandBGField;
// Common item geometry section
@property (nonatomic, strong) NSView *geoBox;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *leftField, *topField, *widthField, *heightField;
// Textbox section
@property (nonatomic, strong) NSView *textBox;
@property (nonatomic, strong) NSTextField *valueField, *fontField, *sizeField, *colorField, *formatField;
@property (nonatomic, strong) NSPopUpButton *weightPop, *alignPop;
// Line section
@property (nonatomic, strong) NSView *lineBox;
@property (nonatomic, strong) NSTextField *lineColorField;
// Rectangle section
@property (nonatomic, strong) NSView *rectBox;
@property (nonatomic, strong) NSTextField *rectBGField;
// Image section
@property (nonatomic, strong) NSView *imageBox;
@property (nonatomic, strong) NSTextField *imageValueField;
@property (nonatomic, strong) NSPopUpButton *imageSourcePop, *imageSizingPop;
// Chart section
@property (nonatomic, strong) NSView *chartBox;
@property (nonatomic, strong) NSPopUpButton *chartDatasetPop, *chartKindPop;
@property (nonatomic, strong) NSTextField *titleField, *catField, *valField;
// Tablix section
@property (nonatomic, strong) NSView *tablixBox;
@property (nonatomic, strong) NSPopUpButton *tablixDatasetPop;
@property (nonatomic, strong) NSTextField *tablixHeaderHField, *tablixRowHField;
@end

static const CGFloat kInspectorWidth = 260;
static const CGFloat kFieldX = 10;
static const CGFloat kFieldW = 240;
static const CGFloat kHalfW = 114;
static const CGFloat kHalf2X = 136;

@implementation PicaInspectorView {
  BOOL _reloading;
  BOOL _completing; // Cocoa re-posts controlTextDidChange: during complete:
}

- (NSTextField *)label:(NSString *)t frame:(NSRect)f inView:(NSView *)v {
  NSTextField *l = [[NSTextField alloc] initWithFrame:f];
  [l setBezeled:NO];
  [l setDrawsBackground:NO];
  [l setEditable:NO];
  [l setSelectable:NO];
  [l setStringValue:t];
  [l setFont:[NSFont userFontOfSize:10]];
  [v addSubview:l];
  return l;
}

- (NSTextField *)fieldIn:(NSView *)v frame:(NSRect)f {
  NSTextField *t = [[NSTextField alloc] initWithFrame:f];
  [t setDelegate:self];
  [t setTarget:self];
  [t setAction:@selector(changed:)];
  [t setFont:[NSFont userFontOfSize:11]];
  [v addSubview:t];
  return t;
}

- (NSPopUpButton *)popIn:(NSView *)v frame:(NSRect)f titles:(NSArray *)titles {
  NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:f pullsDown:NO];
  if (titles)
    [p addItemsWithTitles:titles];
  [p setTarget:self];
  [p setAction:@selector(changed:)];
  [v addSubview:p];
  return p;
}

// Adds a labeled full-width field at *y, advancing it.
- (NSTextField *)row:(NSString *)title y:(CGFloat *)y inView:(NSView *)v height:(CGFloat)h {
  [self label:title frame:NSMakeRect(kFieldX, *y, kFieldW, 14) inView:v];
  *y += 16;
  NSTextField *f = [self fieldIn:v frame:NSMakeRect(kFieldX, *y, kFieldW, h)];
  *y += h + 6;
  return f;
}

- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self) {
    _context = context;
    _kindLabel = [self label:@"Report" frame:NSMakeRect(10, 8, kFieldW, 16) inView:self];
    [_kindLabel setFont:[NSFont boldSystemFontOfSize:11]];

    [self buildDocBox];
    [self buildBandBox];
    [self buildGeoBox];
    [self buildTextBox];
    [self buildLineBox];
    [self buildRectBox];
    [self buildImageBox];
    [self buildChartBox];
    [self buildTablixBox];

    [self declareBindings];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:RDLDocumentDidChangeNotification
                                               object:context.document];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:RDLSelectionDidChangeNotification
                                               object:context.selection];
    [self reload];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

// An edit the inspector itself just made comes back as a notification. Filling
// the fields again from the model would fight the user's cursor, so only
// reload when the change was not a property edit of what is already shown.
- (void)documentDidChange:(NSNotification *)note {
  RDLChange *change = [note userInfo][RDLChangeKey];
  if (change.scope == RDLChangeScopeItem && change.item == [_context selectedItem] &&
      [change.keys count] > 0)
    return;
  [self reload];
}

#pragma mark - Section construction

- (NSView *)boxWithHeight:(CGFloat)h {
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 28, kInspectorWidth, h)];
  [self addSubview:v];
  return v;
}

- (void)buildDocBox {
  CGFloat y = 4;
  _docBox = [self boxWithHeight:320];
  _docNameField = [self row:@"Name" y:&y inView:_docBox height:22];
  _authorField = [self row:@"Author" y:&y inView:_docBox height:22];
  _descField = [self row:@"Description" y:&y inView:_docBox height:44];
  [self label:@"Page" frame:NSMakeRect(kFieldX, y, kFieldW, 14) inView:_docBox];
  y += 16;
  NSMutableArray *pageNames = [NSMutableArray array];
  for (NSDictionary *size in [RDLPage standardSizes])
    [pageNames addObject:size[@"name"]];
  _pagePop = [self popIn:_docBox frame:NSMakeRect(kFieldX, y, kFieldW, 22) titles:pageNames];
  y += 28;
  [self label:@"Header in" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_docBox];
  [self label:@"Body in" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_docBox];
  y += 16;
  _headerHField = [self fieldIn:_docBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _bodyHField = [self fieldIn:_docBox frame:NSMakeRect(kHalf2X, y, kHalfW, 22)];
  y += 28;
  [self label:@"Footer in" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_docBox];
  [self label:@"Margin in" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_docBox];
  y += 16;
  _footerHField = [self fieldIn:_docBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _marginField = [self fieldIn:_docBox frame:NSMakeRect(kHalf2X, y, kHalfW, 22)];
  y += 28;
  [_docBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildBandBox {
  CGFloat y = 4;
  _bandBox = [self boxWithHeight:100];
  _bandHField = [self row:@"Height in" y:&y inView:_bandBox height:22];
  _bandBGField = [self row:@"Background" y:&y inView:_bandBox height:22];
  [_bandBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildGeoBox {
  CGFloat y = 4;
  _geoBox = [self boxWithHeight:140];
  _nameField = [self row:@"Name" y:&y inView:_geoBox height:22];
  [_nameField setEditable:NO];
  NSArray *geo = @[ @"Left", @"Top", @"Width", @"Height" ];
  NSMutableArray *gfs = [NSMutableArray array];
  CGFloat gy0 = y;
  for (NSInteger i = 0; i < 4; i++) {
    CGFloat x = (i % 2) == 0 ? kFieldX : kHalf2X;
    CGFloat gy = gy0 + (i / 2) * 44;
    [self label:geo[i] frame:NSMakeRect(x, gy, kHalfW, 14) inView:_geoBox];
    [gfs addObject:[self fieldIn:_geoBox frame:NSMakeRect(x, gy + 16, kHalfW, 22)]];
  }
  _leftField = gfs[0];
  _topField = gfs[1];
  _widthField = gfs[2];
  _heightField = gfs[3];
  y = gy0 + 2 * 44 + 4;
  [_geoBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildTextBox {
  CGFloat y = 4;
  _textBox = [self boxWithHeight:260];
  _valueField = [self row:@"Value" y:&y inView:_textBox height:44];
  _fontField = [self row:@"Typeface" y:&y inView:_textBox height:22];
  [self label:@"Size" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_textBox];
  [self label:@"Weight" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_textBox];
  y += 16;
  _sizeField = [self fieldIn:_textBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _weightPop = [self popIn:_textBox
                     frame:NSMakeRect(kHalf2X, y, kHalfW, 22)
                    titles:@[ @"Roman", @"Bold" ]];
  y += 28;
  [self label:@"Align" frame:NSMakeRect(kFieldX, y, kFieldW, 14) inView:_textBox];
  y += 16;
  _alignPop = [self popIn:_textBox
                    frame:NSMakeRect(kFieldX, y, kFieldW, 22)
                   titles:@[ @"Left", @"Center", @"Right" ]];
  y += 28;
  [self label:@"Ink" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_textBox];
  [self label:@"Format" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_textBox];
  y += 16;
  _colorField = [self fieldIn:_textBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _formatField = [self fieldIn:_textBox frame:NSMakeRect(kHalf2X, y, kHalfW, 22)];
  y += 28;
  [_textBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildLineBox {
  CGFloat y = 4;
  _lineBox = [self boxWithHeight:52];
  _lineColorField = [self row:@"Ink" y:&y inView:_lineBox height:22];
  [_lineBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildRectBox {
  CGFloat y = 4;
  _rectBox = [self boxWithHeight:52];
  _rectBGField = [self row:@"Background" y:&y inView:_rectBox height:22];
  [_rectBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildImageBox {
  CGFloat y = 4;
  _imageBox = [self boxWithHeight:150];
  _imageValueField = [self row:@"Image (name or =expr)" y:&y inView:_imageBox height:22];
  [self label:@"Source" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_imageBox];
  [self label:@"Sizing" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_imageBox];
  y += 16;
  _imageSourcePop = [self popIn:_imageBox
                          frame:NSMakeRect(kFieldX, y, kHalfW, 22)
                         titles:@[ @"Embedded", @"External" ]];
  _imageSizingPop = [self popIn:_imageBox
                          frame:NSMakeRect(kHalf2X, y, kHalfW, 22)
                         titles:@[ @"Fit", @"FitProportional", @"Clip", @"AutoSize" ]];
  y += 28;
  [_imageBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildChartBox {
  CGFloat y = 4;
  _chartBox = [self boxWithHeight:220];
  [self label:@"Dataset" frame:NSMakeRect(kFieldX, y, kFieldW, 14) inView:_chartBox];
  y += 16;
  _chartDatasetPop = [self popIn:_chartBox frame:NSMakeRect(kFieldX, y, kFieldW, 22) titles:nil];
  y += 28;
  _titleField = [self row:@"Title" y:&y inView:_chartBox height:22];
  [self label:@"Kind" frame:NSMakeRect(kFieldX, y, kFieldW, 14) inView:_chartBox];
  y += 16;
  _chartKindPop = [self popIn:_chartBox
                        frame:NSMakeRect(kFieldX, y, kFieldW, 22)
                       titles:@[ @"Column", @"Bar", @"Line", @"Pie" ]];
  y += 28;
  [self label:@"Category field" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_chartBox];
  [self label:@"Value field" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_chartBox];
  y += 16;
  _catField = [self fieldIn:_chartBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _valField = [self fieldIn:_chartBox frame:NSMakeRect(kHalf2X, y, kHalfW, 22)];
  y += 28;
  [_chartBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

- (void)buildTablixBox {
  CGFloat y = 4;
  _tablixBox = [self boxWithHeight:170];
  [self label:@"Dataset" frame:NSMakeRect(kFieldX, y, kFieldW, 14) inView:_tablixBox];
  y += 16;
  _tablixDatasetPop = [self popIn:_tablixBox frame:NSMakeRect(kFieldX, y, kFieldW, 22) titles:nil];
  y += 28;
  [self label:@"Header in" frame:NSMakeRect(kFieldX, y, kHalfW, 14) inView:_tablixBox];
  [self label:@"Row in" frame:NSMakeRect(kHalf2X, y, kHalfW, 14) inView:_tablixBox];
  y += 16;
  _tablixHeaderHField = [self fieldIn:_tablixBox frame:NSMakeRect(kFieldX, y, kHalfW, 22)];
  _tablixRowHField = [self fieldIn:_tablixBox frame:NSMakeRect(kHalf2X, y, kHalfW, 22)];
  y += 28;
  NSButton *edit = [[NSButton alloc] initWithFrame:NSMakeRect(kFieldX, y, kFieldW, 24)];
  [edit setTitle:@"Edit Tablix…"];
  [edit setBezelStyle:NSShadowlessSquareBezelStyle];
  [edit setTarget:self];
  [edit setAction:@selector(editTablix:)];
  [_tablixBox addSubview:edit];
  y += 30;
  [_tablixBox setFrameSize:NSMakeSize(kInspectorWidth, y)];
}

// Opens the Report-Builder-style tablix editor for the selected tablix.
- (void)editTablix:(id)sender {
  (void)sender;
  RDLItem *it = [_context selectedItem];
  if (it == nil || ![it.type isEqualToString:@"Tablix"])
    return;
  [PicaTablixEditor runForTablix:it context:_context];
}

#pragma mark - Field bindings

// Every field that is a plain read-and-write of one model value. The four that
// are not -- value (which also clears rich-text runs), the margin field (four
// edges plus the body width), the page popup (two dimensions plus the width),
// and the band background (which may have to create the style) -- stay in
// -changed: below, because each is a composite that must undo as one step.
- (void)declareBindings {
  _bindings = [[PicaFieldBindings alloc] init];

  // Item geometry.
  [_bindings bind:_leftField keyPath:@"left" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];
  [_bindings bind:_topField keyPath:@"top" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];
  [_bindings bind:_widthField keyPath:@"width" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];
  [_bindings bind:_heightField keyPath:@"height" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];

  // Textbox.
  [_bindings bind:_fontField keyPath:@"style.fontFamily" scope:PicaFieldScopeItem
             kind:PicaFieldKindText values:nil placeholder:@"Georgia"];
  [_bindings bind:_sizeField keyPath:@"style.fontSize" scope:PicaFieldScopeItem
             kind:PicaFieldKindText values:nil placeholder:@"10pt"];
  [_bindings bind:_weightPop keyPath:@"style.fontWeight" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex values:@[ @"Normal", @"Bold" ] placeholder:nil];
  [_bindings bind:_alignPop keyPath:@"style.textAlign" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];
  [_bindings bind:_colorField keyPath:@"style.color" scope:PicaFieldScopeItem
             kind:PicaFieldKindText values:nil placeholder:@"#1a1916"];
  [_bindings bind:_formatField keyPath:@"style.format" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];

  // Line and Rectangle each expose one style property.
  [_bindings bind:_lineColorField keyPath:@"style.color" scope:PicaFieldScopeItem
             kind:PicaFieldKindText values:nil placeholder:@"#1a1916"];
  [_bindings bind:_rectBGField keyPath:@"style.backgroundColor" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];

  // Image.
  [_bindings bind:_imageValueField keyPath:@"value" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];
  [_bindings bind:_imageSourcePop keyPath:@"source" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex values:@[ @"Embedded", @"External" ] placeholder:nil];
  [_bindings bind:_imageSizingPop keyPath:@"sizing" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];

  // Chart.
  [_bindings bind:_chartDatasetPop keyPath:@"dataSetName" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];
  [_bindings bind:_titleField keyPath:@"title" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];
  [_bindings bind:_chartKindPop keyPath:@"chartType" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];
  [_bindings bind:_catField keyPath:@"categoryField" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];
  [_bindings bind:_valField keyPath:@"valueField" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];

  // Tablix.
  [_bindings bind:_tablixDatasetPop keyPath:@"dataSetName" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];
  [_bindings bind:_tablixHeaderHField keyPath:@"headerHeight" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];
  [_bindings bind:_tablixRowHField keyPath:@"rowHeight" scope:PicaFieldScopeItem
             kind:PicaFieldKindNumber];

  // Band and report.
  [_bindings bind:_bandHField keyPath:@"height" scope:PicaFieldScopeBand
             kind:PicaFieldKindNumber];
  [_bindings bind:_docNameField keyPath:@"name" scope:PicaFieldScopeReport
             kind:PicaFieldKindText];
  [_bindings bind:_authorField keyPath:@"author" scope:PicaFieldScopeReport
             kind:PicaFieldKindText];
  [_bindings bind:_descField keyPath:@"reportDescription" scope:PicaFieldScopeReport
             kind:PicaFieldKindText];
  [_bindings bind:_headerHField keyPath:@"pageHeader.height" scope:PicaFieldScopeReport
             kind:PicaFieldKindNumber];
  [_bindings bind:_bodyHField keyPath:@"body.height" scope:PicaFieldScopeReport
             kind:PicaFieldKindNumber];
  [_bindings bind:_footerHField keyPath:@"pageFooter.height" scope:PicaFieldScopeReport
             kind:PicaFieldKindNumber];
}

#pragma mark - Fill (model → UI)

- (void)stackBoxes:(NSArray *)boxes {
  NSArray *all = @[
    _docBox, _bandBox, _geoBox, _textBox, _lineBox, _rectBox, _imageBox, _chartBox, _tablixBox
  ];
  for (NSView *v in all)
    [v setHidden:YES];
  CGFloat y = 28;
  for (NSView *v in boxes) {
    [v setHidden:NO];
    NSRect f = [v frame];
    f.origin.y = y;
    [v setFrame:f];
    y += NSHeight(f) + 8;
  }
  [self setFrameSize:NSMakeSize(NSWidth(self.frame), MAX(y + 8, NSHeight([[self superview] frame])))];
}

- (void)rebuildDatasetPop:(NSPopUpButton *)pop selecting:(NSString *)name {
  [pop removeAllItems];
  for (RDLDataSet *ds in _context.report.dataSets)
    [pop addItemWithTitle:ds.name];
  if (name && [pop itemWithTitle:name])
    [pop selectItemWithTitle:name];
}

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  RDLReport *report = _context.report;
  RDLSelection *sel = _context.selection;
  RDLItem *it = [_context selectedItem];
  RDLBand *band = sel.scope == RDLSelectionScopeBand ? [report bandWithKey:sel.bandKey] : nil;

  if (it != nil) {
    [_kindLabel setStringValue:[NSString stringWithFormat:@"%@ · %@", it.type, it.name]];
    [_nameField setStringValue:it.name ?: @""];
    NSMutableArray *boxes = [NSMutableArray arrayWithObject:_geoBox];
    // The dataset popups are populated from the report before filling, since
    // their contents depend on it rather than being fixed at build time.
    if ([it.type isEqualToString:@"Textbox"]) {
      [boxes addObject:_textBox];
      [_valueField setStringValue:it.value ?: @""];
    } else if ([it.type isEqualToString:@"Line"]) {
      [boxes addObject:_lineBox];
    } else if ([it.type isEqualToString:@"Rectangle"]) {
      [boxes addObject:_rectBox];
    } else if ([it.type isEqualToString:@"Image"]) {
      [boxes addObject:_imageBox];
    } else if ([it.type isEqualToString:@"Chart"]) {
      [boxes addObject:_chartBox];
      [self rebuildDatasetPop:_chartDatasetPop selecting:it.dataSetName];
    } else if ([it.type isEqualToString:@"Tablix"]) {
      [boxes addObject:_tablixBox];
      [self rebuildDatasetPop:_tablixDatasetPop selecting:it.dataSetName];
    }
    [self stackBoxes:boxes];
  } else if (band != nil) {
    [_kindLabel setStringValue:[RDLItemFactory titleForBandKey:sel.bandKey]];
    // Only the Body carries a background in RDL, so the field is disabled
    // elsewhere rather than silently doing nothing.
    BOOL isBody = [RDLReport bandKeySupportsBackground:sel.bandKey];
    [_bandBGField setEditable:isBody];
    [_bandBGField setEnabled:isBody];
    [_bandBGField setStringValue:isBody ? (band.style.backgroundColor ?: @"") : @""];
    [_bandBGField setToolTip:isBody ? nil : @"Background is supported on the Body band only"];
    [self stackBoxes:@[ _bandBox ]];
  } else {
    [_kindLabel setStringValue:report.name ?: @"Report"];
    NSDictionary *size = [report.page matchingStandardSize];
    NSUInteger sizeIndex = size ? [[RDLPage standardSizes] indexOfObject:size] : NSNotFound;
    if (sizeIndex != NSNotFound)
      [_pagePop selectItemAtIndex:(NSInteger)sizeIndex];
    [_marginField setStringValue:[NSString stringWithFormat:@"%.3f", report.page.leftMargin]];
    [self stackBoxes:@[ _docBox ]];
  }

  [_bindings fillFromItem:it band:band report:report];
  _reloading = NO;
}

#pragma mark - Apply (UI → model)

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  [self changed:[obj object]];
}

// Expression completion (XPath-editor style): `!` pops the member list, and
// Escape completes function names, in any inspector text field.
- (void)controlTextDidChange:(NSNotification *)n {
  if (_completing)
    return;
  if (!PicaIsTypingEvent())
    return;
  NSTextView *tv = [[n userInfo] objectForKey:@"NSFieldEditor"];
  if (tv && PicaShouldAutoComplete([tv string], [tv selectedRange])) {
    _completing = YES;
    [tv complete:nil];
    _completing = NO;
  }
}

- (NSArray *)control:(NSControl *)control
               textView:(NSTextView *)textView
            completions:(NSArray *)words
    forPartialWordRange:(NSRange)charRange
    indexOfSelectedItem:(PicaCompletionIndex *)index {
  (void)control;
  (void)words;
  if (index)
    *index = 0;
  RDLItem *it = [_context selectedItem];
  return PicaExpressionCompletions([textView string], charRange, it.dataSetName,
                                   _context.report);
}

- (void)changed:(id)sender {
  if (_reloading)
    return;
  RDLEditor *editor = _context.editor;
  RDLSelection *sel = _context.selection;
  RDLItem *it = [_context selectedItem];

  // Most fields are a plain read-and-write of one model value.
  if ([_bindings applyControl:sender editor:editor item:it bandKey:sel.bandKey])
    return;

  // The rest are composites: each writes more than one property and must undo
  // as a single step.
  if (sender == _valueField && it != nil) {
    [editor beginGroup:@"Edit Text"];
    [editor setValue:[_valueField stringValue] forKeyPath:@"value" ofItem:it];
    // A plain edit replaces any rich-text runs.
    [editor setValue:nil forKeyPath:@"paragraphs" ofItem:it];
    [editor endGroup];
    return;
  }

  if (sender == _bandBGField && sel.scope == RDLSelectionScopeBand) {
    RDLBand *band = [_context.report bandWithKey:sel.bandKey];
    [editor beginGroup:@"Band Background"];
    // Creating the style belongs to the same step, so undoing does not leave
    // an empty Style behind for the writer to emit.
    if (band.style == nil)
      [editor setValue:[[RDLStyle alloc] init] forKeyPath:@"style" ofBandWithKey:sel.bandKey];
    [editor setValue:[_bandBGField stringValue]
          forKeyPath:@"style.backgroundColor"
       ofBandWithKey:sel.bandKey];
    [editor endGroup];
    return;
  }

  // Page dimensions and margins carry the body width with them, so the
  // dependency lives in RDLEditor rather than here.
  if (sender == _marginField) {
    [editor setUniformMargin:[[_marginField stringValue] doubleValue]];
    return;
  }

  if (sender == _pagePop) {
    NSArray *sizes = [RDLPage standardSizes];
    NSInteger i = [_pagePop indexOfSelectedItem];
    if (i >= 0 && i < (NSInteger)[sizes count]) {
      NSDictionary *size = sizes[(NSUInteger)i];
      [editor setPageWidth:[size[@"width"] doubleValue]
                    height:[size[@"height"] doubleValue]];
    }
    return;
  }
}

@end
