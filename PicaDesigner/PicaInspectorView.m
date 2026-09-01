#import "PicaInspectorView.h"
#import "PicaController.h"
#import "PicaKit.h"
#import "PicaTablixEditor.h"

// Model-Builder-style inspector: one compact section per selection kind,
// filled from the model on selection change and applied back field by field.
@interface PicaInspectorView () <NSTextFieldDelegate>
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

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:PicaReportDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:PicaSelectionDidChangeNotification
                                               object:nil];
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
  _pagePop = [self popIn:_docBox
                   frame:NSMakeRect(kFieldX, y, kFieldW, 22)
                  titles:@[ @"Letter 8.5 × 11", @"A4 210 × 297 mm" ]];
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
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (it == nil || ![it.type isEqualToString:@"Tablix"])
    return;
  if ([PicaTablixEditor runForTablix:it report:c.report])
    [c noteChange];
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
  PicaController *c = [PicaController sharedController];
  [pop removeAllItems];
  for (RDLDataSet *ds in c.report.dataSets)
    [pop addItemWithTitle:ds.name];
  if (name && [pop itemWithTitle:name])
    [pop selectItemWithTitle:name];
}

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (c.selectionScope == PicaSelectionItem && it != nil) {
    [_kindLabel setStringValue:[NSString stringWithFormat:@"%@ · %@", it.type, it.name]];
    [_nameField setStringValue:it.name ?: @""];
    [_leftField setStringValue:[NSString stringWithFormat:@"%.3f", it.left]];
    [_topField setStringValue:[NSString stringWithFormat:@"%.3f", it.top]];
    [_widthField setStringValue:[NSString stringWithFormat:@"%.3f", it.width]];
    [_heightField setStringValue:[NSString stringWithFormat:@"%.3f", it.height]];
    NSMutableArray *boxes = [NSMutableArray arrayWithObject:_geoBox];
    if ([it.type isEqualToString:@"Textbox"]) {
      [boxes addObject:_textBox];
      [_valueField setStringValue:it.value ?: @""];
      [_fontField setStringValue:it.style.fontFamily ?: @"Georgia"];
      [_sizeField setStringValue:it.style.fontSize ?: @"10pt"];
      [_weightPop selectItemAtIndex:[it.style.fontWeight isEqualToString:@"Bold"] ? 1 : 0];
      NSInteger ai = 0;
      if ([it.style.textAlign isEqualToString:@"Center"])
        ai = 1;
      else if ([it.style.textAlign isEqualToString:@"Right"])
        ai = 2;
      [_alignPop selectItemAtIndex:ai];
      [_colorField setStringValue:it.style.color ?: @"#1a1916"];
      [_formatField setStringValue:it.style.format ?: @""];
    } else if ([it.type isEqualToString:@"Line"]) {
      [boxes addObject:_lineBox];
      [_lineColorField setStringValue:it.style.color ?: @"#1a1916"];
    } else if ([it.type isEqualToString:@"Rectangle"]) {
      [boxes addObject:_rectBox];
      [_rectBGField setStringValue:it.style.backgroundColor ?: @""];
    } else if ([it.type isEqualToString:@"Image"]) {
      [boxes addObject:_imageBox];
      [_imageValueField setStringValue:it.value ?: @""];
      [_imageSourcePop selectItemAtIndex:[it.source isEqualToString:@"External"] ? 1 : 0];
      if (it.sizing && [_imageSizingPop itemWithTitle:it.sizing])
        [_imageSizingPop selectItemWithTitle:it.sizing];
      else
        [_imageSizingPop selectItemAtIndex:0];
    } else if ([it.type isEqualToString:@"Chart"]) {
      [boxes addObject:_chartBox];
      [self rebuildDatasetPop:_chartDatasetPop selecting:it.dataSetName];
      [_titleField setStringValue:it.title ?: @""];
      if (it.chartType && [_chartKindPop itemWithTitle:it.chartType])
        [_chartKindPop selectItemWithTitle:it.chartType];
      [_catField setStringValue:it.categoryField ?: @""];
      [_valField setStringValue:it.valueField ?: @""];
    } else if ([it.type isEqualToString:@"Tablix"]) {
      [boxes addObject:_tablixBox];
      [self rebuildDatasetPop:_tablixDatasetPop selecting:it.dataSetName];
      [_tablixHeaderHField setStringValue:[NSString stringWithFormat:@"%.3f", it.headerHeight]];
      [_tablixRowHField setStringValue:[NSString stringWithFormat:@"%.3f", it.rowHeight]];
    }
    [self stackBoxes:boxes];
  } else if (c.selectionScope == PicaSelectionBand) {
    RDLBand *band = [c.report bandWithKey:c.selectedBandKey];
    NSString *title = [c.selectedBandKey isEqualToString:@"pageHeader"]
                          ? @"Page Header"
                          : ([c.selectedBandKey isEqualToString:@"pageFooter"] ? @"Page Footer"
                                                                               : @"Body");
    [_kindLabel setStringValue:title];
    [_bandHField setStringValue:[NSString stringWithFormat:@"%.3f", band.height]];
    BOOL isBody = ![c.selectedBandKey isEqualToString:@"pageHeader"] &&
                  ![c.selectedBandKey isEqualToString:@"pageFooter"];
    [_bandBGField setEditable:isBody];
    [_bandBGField setEnabled:isBody];
    [_bandBGField setStringValue:isBody ? (band.style.backgroundColor ?: @"") : @""];
    [_bandBGField setToolTip:isBody ? nil : @"Background is supported on the Body band only"];
    [self stackBoxes:@[ _bandBox ]];
  } else {
    [_kindLabel setStringValue:c.report.name ?: @"Report"];
    [_docNameField setStringValue:c.report.name ?: @""];
    [_authorField setStringValue:c.report.author ?: @""];
    [_descField setStringValue:c.report.reportDescription ?: @""];
    BOOL a4 = fabs(c.report.page.pageWidth - 8.27) < 0.05;
    [_pagePop selectItemAtIndex:a4 ? 1 : 0];
    [_headerHField setStringValue:[NSString stringWithFormat:@"%.3f", c.report.pageHeader.height]];
    [_bodyHField setStringValue:[NSString stringWithFormat:@"%.3f", c.report.body.height]];
    [_footerHField setStringValue:[NSString stringWithFormat:@"%.3f", c.report.pageFooter.height]];
    [_marginField setStringValue:[NSString stringWithFormat:@"%.3f", c.report.page.leftMargin]];
    [self stackBoxes:@[ _docBox ]];
  }
  _reloading = NO;
}

#pragma mark - Apply (UI → model)

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  [self changed:[obj object]];
}

- (void)changed:(id)sender {
  if (_reloading)
    return;
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (c.selectionScope == PicaSelectionItem && it != nil) {
    if (sender == _leftField)
      it.left = [[_leftField stringValue] doubleValue];
    else if (sender == _topField)
      it.top = [[_topField stringValue] doubleValue];
    else if (sender == _widthField)
      it.width = [[_widthField stringValue] doubleValue];
    else if (sender == _heightField)
      it.height = [[_heightField stringValue] doubleValue];
    else if (sender == _valueField)
      it.value = [_valueField stringValue];
    else if (sender == _fontField)
      it.style.fontFamily = [_fontField stringValue];
    else if (sender == _sizeField)
      it.style.fontSize = [_sizeField stringValue];
    else if (sender == _weightPop)
      it.style.fontWeight = [_weightPop indexOfSelectedItem] == 1 ? @"Bold" : @"Normal";
    else if (sender == _alignPop)
      it.style.textAlign = [_alignPop titleOfSelectedItem];
    else if (sender == _colorField)
      it.style.color = [_colorField stringValue];
    else if (sender == _formatField)
      it.style.format = [_formatField stringValue];
    else if (sender == _lineColorField)
      it.style.color = [_lineColorField stringValue];
    else if (sender == _rectBGField)
      it.style.backgroundColor = [_rectBGField stringValue];
    else if (sender == _imageValueField)
      it.value = [_imageValueField stringValue];
    else if (sender == _imageSourcePop)
      it.source = [_imageSourcePop titleOfSelectedItem];
    else if (sender == _imageSizingPop)
      it.sizing = [_imageSizingPop titleOfSelectedItem];
    else if (sender == _chartDatasetPop)
      it.dataSetName = [_chartDatasetPop titleOfSelectedItem];
    else if (sender == _titleField)
      it.title = [_titleField stringValue];
    else if (sender == _chartKindPop)
      it.chartType = [_chartKindPop titleOfSelectedItem];
    else if (sender == _catField)
      it.categoryField = [_catField stringValue];
    else if (sender == _valField)
      it.valueField = [_valField stringValue];
    else if (sender == _tablixDatasetPop)
      it.dataSetName = [_tablixDatasetPop titleOfSelectedItem];
    else if (sender == _tablixHeaderHField)
      it.headerHeight = [[_tablixHeaderHField stringValue] doubleValue];
    else if (sender == _tablixRowHField)
      it.rowHeight = [[_tablixRowHField stringValue] doubleValue];
    else
      return;
    [c noteChange];
    return;
  }
  if (c.selectionScope == PicaSelectionBand) {
    RDLBand *band = [c.report bandWithKey:c.selectedBandKey];
    if (sender == _bandHField)
      band.height = [[_bandHField stringValue] doubleValue];
    else if (sender == _bandBGField) {
      if (band.style == nil)
        band.style = [[RDLStyle alloc] init];
      band.style.backgroundColor = [_bandBGField stringValue];
    } else
      return;
    [c noteChange];
    return;
  }
  if (sender == _docNameField)
    c.report.name = [_docNameField stringValue];
  else if (sender == _authorField)
    c.report.author = [_authorField stringValue];
  else if (sender == _descField)
    c.report.reportDescription = [_descField stringValue];
  else if (sender == _headerHField)
    c.report.pageHeader.height = [[_headerHField stringValue] doubleValue];
  else if (sender == _bodyHField)
    c.report.body.height = [[_bodyHField stringValue] doubleValue];
  else if (sender == _footerHField)
    c.report.pageFooter.height = [[_footerHField stringValue] doubleValue];
  else if (sender == _marginField) {
    CGFloat m = [[_marginField stringValue] doubleValue];
    c.report.page.leftMargin = c.report.page.rightMargin = c.report.page.topMargin =
        c.report.page.bottomMargin = m;
    c.report.width = c.report.page.pageWidth - 2 * m;
  } else if (sender == _pagePop) {
    if ([_pagePop indexOfSelectedItem] == 1) {
      c.report.page.pageWidth = 8.27;
      c.report.page.pageHeight = 11.69;
    } else {
      c.report.page.pageWidth = 8.5;
      c.report.page.pageHeight = 11.0;
    }
    c.report.width = c.report.page.pageWidth - c.report.page.leftMargin - c.report.page.rightMargin;
  } else
    return;
  [c noteChange];
}

@end
