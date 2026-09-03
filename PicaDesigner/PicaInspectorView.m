#import "PicaInspectorView.h"
#import "PicaChange.h"
#import "PicaEditor.h"
#import "PicaItemFactory.h"
#import "PicaSelection.h"
#import "PicaEditingContext.h"
#import "PicaKit.h"
#import "PicaTablixEditor.h"
#import "PicaExpressionHelper.h"
#import "PicaInspectorFields.h"

// Model-Builder-style inspector: one compact section per selection kind,
// filled from the model on selection change and applied back field by field.
@interface PicaInspectorView () <NSTextFieldDelegate>
// One declaration per field drives both directions; see PicaInspectorFields.
@property (nonatomic, strong) PicaFieldBindings *bindings;
@property (nonatomic, strong) IBOutlet NSTextField *kindLabel;
// Report section
@property (nonatomic, strong) IBOutlet NSView *docBox;
@property (nonatomic, strong) IBOutlet NSTextField *docNameField, *authorField, *descField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *pagePop;
@property (nonatomic, strong) IBOutlet NSTextField *headerHField, *bodyHField, *footerHField, *marginField;
// Band section
@property (nonatomic, strong) IBOutlet NSView *bandBox;
@property (nonatomic, strong) IBOutlet NSTextField *bandHField, *bandBGField;
// Common item geometry section
@property (nonatomic, strong) IBOutlet NSView *geoBox;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *leftField, *topField, *widthField, *heightField;
// Textbox section
@property (nonatomic, strong) IBOutlet NSView *textBox;
@property (nonatomic, strong) IBOutlet NSTextField *valueField, *fontField, *sizeField, *colorField, *formatField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *weightPop, *alignPop;
// Line section
@property (nonatomic, strong) IBOutlet NSView *lineBox;
@property (nonatomic, strong) IBOutlet NSTextField *lineColorField;
// Rectangle section
@property (nonatomic, strong) IBOutlet NSView *rectBox;
@property (nonatomic, strong) IBOutlet NSTextField *rectBGField;
// Image section
@property (nonatomic, strong) IBOutlet NSView *imageBox;
@property (nonatomic, strong) IBOutlet NSTextField *imageValueField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *imageSourcePop, *imageSizingPop;
// Chart section
@property (nonatomic, strong) IBOutlet NSView *chartBox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *chartDatasetPop, *chartKindPop;
@property (nonatomic, strong) IBOutlet NSTextField *titleField, *catField, *valField;
// Tablix section
@property (nonatomic, strong) IBOutlet NSView *tablixBox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *tablixDatasetPop;
@property (nonatomic, strong) IBOutlet NSTextField *tablixHeaderHField, *tablixRowHField;
@end

@implementation PicaInspectorView {
  BOOL _reloading;
  BOOL _completing; // Cocoa re-posts controlTextDidChange: during complete:
}

- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self)
    [self setContext:context];
  return self;
}

- (void)setContext:(PicaEditingContext *)context {
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  if (context == nil)
    return;
  if (_kindLabel == nil)
    [self buildSections];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(documentDidChange:)
                                               name:PicaDocumentDidChangeNotification
                                             object:context.document];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(reload)
                                               name:PicaSelectionDidChangeNotification
                                             object:context.selection];
  [self reload];
}

// The nine sections -- every label, field, popup and their fixed frames --
// are PicaInspectorSections.xib, as nine top-level views plus the kind label.
// Which of them is shown, and where each one sits, stays in -stackBoxes:
// below, because that depends on what is selected.
- (void)buildSections {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"PicaInspectorSections"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  [nib instantiateWithOwner:self topLevelObjects:NULL];
  // A nib's top-level view has no meaningful frame origin: Interface Builder
  // normalises it to (0,0) and records where it sits on the canvas instead. So
  // the label is placed here, the way -stackBoxes: places the sections.
  [_kindLabel setFrame:NSMakeRect(10, 8, 240, 16)];
  [self addSubview:_kindLabel];
  // The page popup lists the kit's standard paper sizes, which the XIB has no
  // way to know; the dataset popups are filled per report in -reload.
  for (NSDictionary *size in [RDLPage standardSizes])
    [_pagePop addItemWithTitle:size[@"name"]];
  for (NSView *box in @[ _docBox, _bandBox, _geoBox, _textBox, _lineBox, _rectBox,
                         _imageBox, _chartBox, _tablixBox ])
    [self addSubview:box];
  [self declareBindings];
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
  PicaChange *change = [note userInfo][PicaChangeKey];
  if (change.scope == RDLChangeScopeItem && change.item == [_context selectedItem] &&
      [change.keys count] > 0)
    return;
  [self reload];
}

// Opens the Report-Builder-style tablix editor for the selected tablix.
- (void)editTablix:(id)sender {
  (void)sender;
  RDLItem *it = [_context selectedItem];
  if (it == nil || ![it isKindOfClass:[RDLTablix class]])
    return;
  if ([PicaTablixEditor runForTablix:(RDLTablix *)it context:_context]) {
    // -documentDidChange: suppresses reload for a property edit of the item on
    // show, which is right while the user is typing in a field but wrong when
    // a modal has just rewritten several of them.
    [self reload];
  }
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
             kind:PicaFieldKindLength values:nil placeholder:@"10pt"];
  // Vocabulary popups map menu index to the enum case, so the model value and
  // the menu title no longer have to be the same word ("Roman" shows Normal).
  [_bindings bind:_weightPop keyPath:@"style.fontWeight" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex
           values:@[ @(RDLFontWeightNormal), @(RDLFontWeightBold) ]
      placeholder:nil];
  [_bindings bind:_alignPop keyPath:@"style.textAlign" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex
           values:@[ @(RDLTextAlignLeft), @(RDLTextAlignCenter), @(RDLTextAlignRight) ]
      placeholder:nil];
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
             kind:PicaFieldKindPopUpIndex
           values:@[ @(RDLImageSourceEmbedded), @(RDLImageSourceExternal) ]
      placeholder:nil];
  [_bindings bind:_imageSizingPop keyPath:@"sizing" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex
           values:@[ @(RDLImageSizingFit), @(RDLImageSizingFitProportional),
                     @(RDLImageSizingClip), @(RDLImageSizingAutoSize) ]
      placeholder:nil];

  // Chart.
  [_bindings bind:_chartDatasetPop keyPath:@"dataSetName" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpTitle];
  [_bindings bind:_titleField keyPath:@"title" scope:PicaFieldScopeItem
             kind:PicaFieldKindText];
  [_bindings bind:_chartKindPop keyPath:@"chartType" scope:PicaFieldScopeItem
             kind:PicaFieldKindPopUpIndex
           values:@[ @(RDLChartTypeColumn), @(RDLChartTypeBar), @(RDLChartTypeLine),
                     @(RDLChartTypeArea), @(RDLChartTypePie), @(RDLChartTypeDoughnut),
                     @(RDLChartTypeScatter) ]
      placeholder:nil];
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
  PicaSelection *sel = _context.selection;
  RDLItem *it = [_context selectedItem];
  RDLBand *band = sel.scope == RDLSelectionScopeBand ? [report bandWithKey:sel.bandKey] : nil;

  if (it != nil) {
      [_kindLabel setStringValue:[NSString stringWithFormat:@"%@ · %@",
                                                           it.rdlElementName,
                                                           it.name]];
    [_nameField setStringValue:it.name ?: @""];
    NSMutableArray *boxes = [NSMutableArray arrayWithObject:_geoBox];
    // The dataset popups are populated from the report before filling, since
    // their contents depend on it rather than being fixed at build time.
    if ([it isKindOfClass:[RDLTextbox class]]) {
      [boxes addObject:_textBox];
        [_valueField setStringValue:[(RDLTextbox *)it value] ?: @""];
    } else if ([it isKindOfClass:[RDLLine class]]) {
      [boxes addObject:_lineBox];
    } else if ([it isKindOfClass:[RDLRectangle class]]) {
      [boxes addObject:_rectBox];
    } else if ([it isKindOfClass:[RDLImage class]]) {
      [boxes addObject:_imageBox];
    } else if ([it isKindOfClass:[RDLChart class]]) {
      [boxes addObject:_chartBox];
        [self rebuildDatasetPop:_chartDatasetPop selecting:[(RDLChart *)it dataSetName]];
    } else if ([it isKindOfClass:[RDLTablix class]]) {
      [boxes addObject:_tablixBox];
        [self rebuildDatasetPop:_tablixDatasetPop selecting:[(RDLTablix *)it dataSetName]];
    }
    [self stackBoxes:boxes];
  } else if (band != nil) {
    [_kindLabel setStringValue:[PicaItemFactory titleForBandKey:sel.bandKey]];
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
  PicaExpressionScope *scope =
        [PicaExpressionScope scopeWithReport:_context.report
                                 dataSetName:[it isKindOfClass:[RDLDataRegion class]]
                                                 ? [(RDLDataRegion *)it dataSetName]
                                                 : nil];
  return PicaExpressionCompletions([textView string], charRange, scope);
}

- (void)changed:(id)sender {
  if (_reloading)
    return;
  PicaEditor *editor = _context.editor;
  PicaSelection *sel = _context.selection;
  RDLItem *it = [_context selectedItem];

  // Most fields are a plain read-and-write of one model value.
  if ([_bindings applyControl:sender editor:editor item:it bandKey:sel.bandKey])
    return;

  // The rest are composites: each writes more than one property and must undo
  // as a single step.
  if (sender == _valueField && it != nil) {
    // -controlTextDidEndEditing: fires whenever the field resigns first
    // responder, not only when something was typed, and opening the rich-text
    // panel is enough to do that. -setPlainValue:ofItem: is the one that knows
    // an unchanged value is not an edit and must leave the runs alone.
    [editor setPlainValue:[_valueField stringValue] ofItem:it];
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
  // dependency lives in PicaEditor rather than here.
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
