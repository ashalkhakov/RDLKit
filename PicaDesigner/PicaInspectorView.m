#import "PicaInspectorView.h"
#import "PicaController.h"
#import "PicaKit.h"

@interface PicaInspectorView () <NSTextFieldDelegate>
@property (nonatomic, strong) NSTextField *kindLabel;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *valueField;
@property (nonatomic, strong) NSTextField *leftField, *topField, *widthField, *heightField;
@property (nonatomic, strong) NSTextField *fontField, *sizeField, *colorField, *formatField;
@property (nonatomic, strong) NSPopUpButton *weightPop, *alignPop, *pagePop, *datasetPop, *chartKindPop;
@property (nonatomic, strong) NSTextField *titleField, *catField, *valField;
@property (nonatomic, strong) NSTextField *authorField, *descField, *docNameField;
@property (nonatomic, strong) NSTextField *headerHField, *bodyHField, *footerHField, *marginField;
@property (nonatomic, strong) NSView *itemBox;
@property (nonatomic, strong) NSView *docBox;
@end

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

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _kindLabel = [self label:@"Document" frame:NSMakeRect(10, 8, 220, 16) inView:self];
    [_kindLabel setFont:[NSFont boldSystemFontOfSize:11]];

    _itemBox = [[NSView alloc] initWithFrame:NSMakeRect(0, 28, 240, 520)];
    _docBox = [[NSView alloc] initWithFrame:NSMakeRect(0, 28, 240, 360)];
    [self addSubview:_itemBox];
    [self addSubview:_docBox];

    CGFloat y = 4;
    [self label:@"Name" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _nameField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 220, 22)];
    [_nameField setEditable:NO];
    y += 28;
    [self label:@"Value" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _valueField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 220, 56)];
    y += 62;
    NSArray *geo = @[ @"Left", @"Top", @"Width", @"Height" ];
    NSMutableArray *gfs = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
      CGFloat x = 10 + (i % 2) * 112;
      CGFloat gy = y + (i / 2) * 40;
      [self label:geo[i] frame:NSMakeRect(x, gy, 100, 14) inView:_itemBox];
      [gfs addObject:[self fieldIn:_itemBox frame:NSMakeRect(x, gy + 16, 100, 22)]];
    }
    _leftField = gfs[0];
    _topField = gfs[1];
    _widthField = gfs[2];
    _heightField = gfs[3];
    y += 88;
    [self label:@"Typeface" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _fontField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 220, 22)];
    y += 28;
    [self label:@"Size" frame:NSMakeRect(10, y, 100, 14) inView:_itemBox];
    [self label:@"Weight" frame:NSMakeRect(122, y, 100, 14) inView:_itemBox];
    y += 16;
    _sizeField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 100, 22)];
    _weightPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(122, y, 108, 22) pullsDown:NO];
    [_weightPop addItemsWithTitles:@[ @"Roman", @"Bold" ]];
    [_weightPop setTarget:self];
    [_weightPop setAction:@selector(changed:)];
    [_itemBox addSubview:_weightPop];
    y += 28;
    [self label:@"Align" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _alignPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
    [_alignPop addItemsWithTitles:@[ @"Left", @"Center", @"Right" ]];
    [_alignPop setTarget:self];
    [_alignPop setAction:@selector(changed:)];
    [_itemBox addSubview:_alignPop];
    y += 28;
    [self label:@"Ink" frame:NSMakeRect(10, y, 100, 14) inView:_itemBox];
    [self label:@"Format" frame:NSMakeRect(122, y, 100, 14) inView:_itemBox];
    y += 16;
    _colorField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 100, 22)];
    _formatField = [self fieldIn:_itemBox frame:NSMakeRect(122, y, 108, 22)];
    y += 28;
    [self label:@"Dataset" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _datasetPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
    [_datasetPop setTarget:self];
    [_datasetPop setAction:@selector(changed:)];
    [_itemBox addSubview:_datasetPop];
    y += 28;
    [self label:@"Chart title" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _titleField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 220, 22)];
    y += 28;
    [self label:@"Kind" frame:NSMakeRect(10, y, 220, 14) inView:_itemBox];
    y += 16;
    _chartKindPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
    [_chartKindPop addItemsWithTitles:@[ @"Column", @"Bar", @"Line", @"Pie" ]];
    [_chartKindPop setTarget:self];
    [_chartKindPop setAction:@selector(changed:)];
    [_itemBox addSubview:_chartKindPop];
    y += 28;
    [self label:@"Category field" frame:NSMakeRect(10, y, 100, 14) inView:_itemBox];
    [self label:@"Value field" frame:NSMakeRect(122, y, 100, 14) inView:_itemBox];
    y += 16;
    _catField = [self fieldIn:_itemBox frame:NSMakeRect(10, y, 100, 22)];
    _valField = [self fieldIn:_itemBox frame:NSMakeRect(122, y, 108, 22)];

    y = 4;
    [self label:@"Name" frame:NSMakeRect(10, y, 220, 14) inView:_docBox];
    y += 16;
    _docNameField = [self fieldIn:_docBox frame:NSMakeRect(10, y, 220, 22)];
    y += 28;
    [self label:@"Author" frame:NSMakeRect(10, y, 220, 14) inView:_docBox];
    y += 16;
    _authorField = [self fieldIn:_docBox frame:NSMakeRect(10, y, 220, 22)];
    y += 28;
    [self label:@"Description" frame:NSMakeRect(10, y, 220, 14) inView:_docBox];
    y += 16;
    _descField = [self fieldIn:_docBox frame:NSMakeRect(10, y, 220, 44)];
    y += 50;
    [self label:@"Page" frame:NSMakeRect(10, y, 220, 14) inView:_docBox];
    y += 16;
    _pagePop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
    [_pagePop addItemsWithTitles:@[ @"Letter 8.5 × 11", @"A4 210 × 297 mm" ]];
    [_pagePop setTarget:self];
    [_pagePop setAction:@selector(changed:)];
    [_docBox addSubview:_pagePop];
    y += 28;
    [self label:@"Header in" frame:NSMakeRect(10, y, 100, 14) inView:_docBox];
    [self label:@"Body in" frame:NSMakeRect(122, y, 100, 14) inView:_docBox];
    y += 16;
    _headerHField = [self fieldIn:_docBox frame:NSMakeRect(10, y, 100, 22)];
    _bodyHField = [self fieldIn:_docBox frame:NSMakeRect(122, y, 108, 22)];
    y += 28;
    [self label:@"Footer in" frame:NSMakeRect(10, y, 100, 14) inView:_docBox];
    [self label:@"Margin in" frame:NSMakeRect(122, y, 100, 14) inView:_docBox];
    y += 16;
    _footerHField = [self fieldIn:_docBox frame:NSMakeRect(10, y, 100, 22)];
    _marginField = [self fieldIn:_docBox frame:NSMakeRect(122, y, 108, 22)];

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

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c.report itemNamed:c.selectedName inBand:NULL];
  [_itemBox setHidden:(it == nil)];
  [_docBox setHidden:(it != nil)];
  if (it) {
    [_kindLabel setStringValue:[NSString stringWithFormat:@"%@ · %@", it.type, it.name]];
    [_nameField setStringValue:it.name ?: @""];
    [_valueField setStringValue:it.value ?: @""];
    [_leftField setStringValue:[NSString stringWithFormat:@"%.3f", it.left]];
    [_topField setStringValue:[NSString stringWithFormat:@"%.3f", it.top]];
    [_widthField setStringValue:[NSString stringWithFormat:@"%.3f", it.width]];
    [_heightField setStringValue:[NSString stringWithFormat:@"%.3f", it.height]];
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
    [_datasetPop removeAllItems];
    for (RDLDataSet *ds in c.report.dataSets)
      [_datasetPop addItemWithTitle:ds.name];
    if (it.dataSetName)
      [_datasetPop selectItemWithTitle:it.dataSetName];
    [_titleField setStringValue:it.title ?: @""];
    if (it.chartType)
      [_chartKindPop selectItemWithTitle:it.chartType];
    [_catField setStringValue:it.categoryField ?: @""];
    [_valField setStringValue:it.valueField ?: @""];
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
  }
  _reloading = NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  [self changed:[obj object]];
}

- (void)changed:(id)sender {
  if (_reloading)
    return;
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c.report itemNamed:c.selectedName inBand:NULL];
  if (it) {
    if (sender == _valueField)
      it.value = [_valueField stringValue];
    else if (sender == _leftField)
      it.left = [[_leftField stringValue] doubleValue];
    else if (sender == _topField)
      it.top = [[_topField stringValue] doubleValue];
    else if (sender == _widthField)
      it.width = [[_widthField stringValue] doubleValue];
    else if (sender == _heightField)
      it.height = [[_heightField stringValue] doubleValue];
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
    else if (sender == _datasetPop)
      it.dataSetName = [_datasetPop titleOfSelectedItem];
    else if (sender == _titleField)
      it.title = [_titleField stringValue];
    else if (sender == _chartKindPop)
      it.chartType = [_chartKindPop titleOfSelectedItem];
    else if (sender == _catField)
      it.categoryField = [_catField stringValue];
    else if (sender == _valField)
      it.valueField = [_valField stringValue];
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
  }
  [c noteChange];
}

@end
