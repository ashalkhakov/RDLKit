#import "RDLInspectorView.h"
#import "RDLBordersEditor.h"
#import "RDLTablixStructure.h"
#import "RDLChange.h"
#import "RDLEditor.h"
#import "RDLItemFactory.h"
#import "RDLSelection.h"
#import "RDLEditingContext.h"
#import "RDLKit.h"
#import "RDLToolbarIcons.h"
#import "RDLFilterEditor.h"
#import "RDLSortEditor.h"
#import "RDLSubreportParametersEditor.h"
#import "RDLTablixEditor.h"
#import "RDLExpressionHelper.h"
#import "RDLInspectorFields.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLRichTextEditor.h"
#import "RDLTextAttributes.h"

// Model-Builder-style inspector: one compact section per selection kind,
// filled from the model on selection change and applied back field by field.
@interface RDLInspectorView () <NSTextFieldDelegate>
// One declaration per field drives both directions; see RDLInspectorFields.
@property (nonatomic, strong) RDLFieldBindings *bindings;
@property (nonatomic, strong) IBOutlet NSTextField *kindLabel;
@property (nonatomic, strong) IBOutlet NSColorWell *colorWell, *bgColorWell;
@property (nonatomic, strong) IBOutlet NSButton *fontPanelButton, *richTextButton;
@property (nonatomic, strong) IBOutlet NSButton *valueExprButton, *fontExprButton;
@property (nonatomic, strong) IBOutlet NSButton *colorExprButton, *formatExprButton, *rectBGExprButton;
// A text box's own background, which the engine paints and the pane did not
// offer; how its text sits in the box; whether it is italic; and what is drawn
// through or under it.
@property (nonatomic, strong) IBOutlet RDLExpressionField *textBGField;
// The four sides of a text box's padding, each its own length or expression.
@property (nonatomic, strong) IBOutlet RDLExpressionField *padLeftField, *padRightField;
@property (nonatomic, strong) IBOutlet RDLExpressionField *padTopField, *padBottomField;
@property (nonatomic, strong) IBOutlet NSButton *padLeftExprButton, *padRightExprButton;
@property (nonatomic, strong) IBOutlet NSButton *padTopExprButton, *padBottomExprButton;
@property (nonatomic, strong) IBOutlet NSButton *textBordersButton, *rectBordersButton;
@property (nonatomic, strong) IBOutlet NSButton *textBGExprButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *verticalPop, *decorationPop;
@property (nonatomic, strong) IBOutlet NSButton *italicCheck;
@property (nonatomic, strong) IBOutlet NSButton *sizeExprButton;
// The column of the selected cell. A column is part of the tablix's body rather
// than an item's property, so it is applied by hand rather than through a key
// path binding -- as are the tablix's row heights.
@property (nonatomic, strong) IBOutlet NSView *cellBox;
@property (nonatomic, strong) IBOutlet NSTextField *cellWidthField;
// Borders for a cell whose contents have no section that offers them: an empty
// cell, or an image, chart or other region in one.
@property (nonatomic, strong) IBOutlet NSButton *cellBordersButton;
// Report section
@property (nonatomic, strong) IBOutlet NSView *docBox;
@property (nonatomic, strong) IBOutlet NSTextField *docNameField, *authorField, *descField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *pagePop;
@property (nonatomic, strong) IBOutlet NSTextField *headerHField, *bodyHField, *footerHField;
// The paper: its size and which way up, its margins and columns, and what the
// pages say before anything names them.
@property (nonatomic, strong) IBOutlet NSView *paperBox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *orientationPop;
@property (nonatomic, strong) IBOutlet NSTextField *pageBGField, *paperWidthField, *paperHeightField;
@property (nonatomic, strong) IBOutlet NSTextField *leftMarginField, *rightMarginField, *topMarginField,
    *bottomMarginField, *columnsField, *columnSpacingField;
@property (nonatomic, strong) IBOutlet RDLExpressionField *initialPageNameField;
@property (nonatomic, strong) IBOutlet NSButton *initialPageNameExprButton, *consumeWhitespaceCheck;
@property (nonatomic, strong) IBOutlet NSTextField *paperWidthLabel, *paperHeightLabel, *leftMarginLabel,
    *rightMarginLabel, *topMarginLabel, *bottomMarginLabel, *columnSpacingLabel;
// Band section
@property (nonatomic, strong) IBOutlet NSView *bandBox;
@property (nonatomic, strong) IBOutlet NSTextField *bandHField, *bandBGField;
// Whether the page header or footer appears on the first and the last page.
@property (nonatomic, strong) IBOutlet NSView *printBox;
@property (nonatomic, strong) IBOutlet NSButton *printOnFirstPageCheck, *printOnLastPageCheck;
// Common item geometry section
@property (nonatomic, strong) IBOutlet NSView *geoBox;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *leftField, *topField, *widthField, *heightField;
// Textbox section
@property (nonatomic, strong) IBOutlet NSView *textBox;
@property (nonatomic, strong) IBOutlet RDLExpressionField *valueField, *fontField, *colorField, *formatField;
// Localization: the report's culture, and one text box's override of it.
@property (nonatomic, strong) IBOutlet RDLExpressionField *docLanguageField, *languageField;
// The unit the report is authored in, and the labels that have to say which
// unit their box is in. RDL measurements carry their own unit, so this is a
// matter of what the author reads and types, not of what the file means.
@property (nonatomic, strong) IBOutlet NSPopUpButton *unitPop;
@property (nonatomic, strong) IBOutlet NSTextField *headerHLabel, *bodyHLabel, *footerHLabel,
    *bandHeightLabel, *cellWidthLabel, *tablixHeaderLabel, *tablixRowLabel;
@property (nonatomic, strong) IBOutlet NSButton *docLanguageExprButton, *languageExprButton;
@property (nonatomic, strong) IBOutlet RDLExpressionField *sizeField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *weightPop, *alignPop;
// Line section
@property (nonatomic, strong) IBOutlet NSView *lineBox;
@property (nonatomic, strong) IBOutlet NSTextField *lineColorField;
// A line's own thickness and dash, which the canvas has always drawn and the
// inspector never offered.
@property (nonatomic, strong) IBOutlet RDLExpressionField *lineWidthField;
@property (nonatomic, strong) IBOutlet NSButton *lineWidthExprButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *lineDashPop;
// Rectangle section
@property (nonatomic, strong) IBOutlet NSView *rectBox;
@property (nonatomic, strong) IBOutlet RDLExpressionField *rectBGField;
// Image section
@property (nonatomic, strong) IBOutlet NSView *imageBox;
@property (nonatomic, strong) IBOutlet NSTextField *imageValueField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *imageSourcePop, *imageSizingPop;
// Chart section
@property (nonatomic, strong) IBOutlet NSView *chartBox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *chartDatasetPop, *chartKindPop;
@property (nonatomic, strong) IBOutlet NSButton *chartFiltersButton;
@property (nonatomic, strong) IBOutlet NSTextField *titleField, *catField, *valField;
// Subreport section. Which report it shows, and the two things a person does
// with it: pass values to it, and open it -- because its contents belong to
// another file and are edited in that file's own window.
@property (nonatomic, strong) IBOutlet NSView *subreportBox;
@property (nonatomic, strong) IBOutlet NSTextField *subreportNameField, *subreportStatusLabel;
@property (nonatomic, strong) IBOutlet NSButton *subreportEditButton, *subreportParametersButton;
// Tablix section
@property (nonatomic, strong) IBOutlet NSView *tablixBox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *tablixDatasetPop;
@property (nonatomic, strong) IBOutlet NSTextField *tablixHeaderHField, *tablixRowHField;
// A tablix's own settings: what it shows with no rows, which way its columns
// run, and how its headers behave across pages and when scrolled.
@property (nonatomic, strong) IBOutlet NSView *tablixOptionsBox;
@property (nonatomic, strong) IBOutlet RDLExpressionField *noRowsMessageField;
@property (nonatomic, strong) IBOutlet NSButton *noRowsMessageExprButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *layoutDirectionPop;
@property (nonatomic, strong) IBOutlet NSTextField *groupsBeforeRowHeadersField;
@property (nonatomic, strong) IBOutlet NSButton *tablixSortingButton;
@property (nonatomic, strong) IBOutlet NSButton *repeatColumnHeadersCheck, *repeatRowHeadersCheck,
    *fixedColumnHeadersCheck, *fixedRowHeadersCheck, *omitBorderCheck;
// What every report item has, in the sections that apply to its kind: whether
// it shows and what toggles it; a link (a text box's or an image's); keeping it
// on one page; and the page breaks and page name of a region or rectangle.
@property (nonatomic, strong) IBOutlet NSView *nameBox, *visibilityBox, *linkBox, *keepBox, *pageBox;
@property (nonatomic, strong) IBOutlet RDLExpressionField *hiddenField, *hyperlinkField;
@property (nonatomic, strong) IBOutlet RDLExpressionField *pageBreakDisabledField, *pageNameField;
@property (nonatomic, strong) IBOutlet NSButton *hiddenExprButton, *hyperlinkExprButton;
@property (nonatomic, strong) IBOutlet NSButton *pageBreakDisabledExprButton, *pageNameExprButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *toggleItemPop, *pageBreakPop;
@property (nonatomic, strong) IBOutlet NSButton *keepTogetherCheck, *resetPageNumberCheck;
@end

@implementation RDLInspectorView {
  // Every section the XIB carries, in the order -buildSections added them.
  // What -stackBoxes: hides before showing the ones that apply.
  NSArray<NSView *> *_sections;
  BOOL _reloading;
  BOOL _completing; // Cocoa re-posts controlTextDidChange: during complete:
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self)
    [self setContext:context];
  return self;
}

- (void)setContext:(RDLEditingContext *)context {
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
                                               name:RDLDocumentDidChangeNotification
                                             object:context.document];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(reload)
                                               name:RDLSelectionDidChangeNotification
                                             object:context.selection];
  [self reload];
}

// The nine sections -- every label, field, popup and their fixed frames --
// are RDLInspectorSections.xib, as nine top-level views plus the kind label.
// Which of them is shown, and where each one sits, stays in -stackBoxes:
// below, because that depends on what is selected.
- (void)buildSections {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLInspectorSections"
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
  // Last, for a page that is none of them; choosing it changes nothing.
  [_pagePop addItemWithTitle:@"Custom"];
  [_orientationPop addItemWithTitle:@"Portrait"];
  [_orientationPop addItemWithTitle:@"Landscape"];
  [_unitPop addItemWithTitle:@"Inches"];
  [_unitPop addItemWithTitle:@"Centimeters"];
  // f(x) is a picture, not two letters and two brackets: at 24 points wide the
  // title is the platform's to draw, and GNUstep draws its own instead.
  for (NSButton *b in @[ _valueExprButton, _fontExprButton, _colorExprButton, _formatExprButton,
                         _languageExprButton, _docLanguageExprButton,
                         _rectBGExprButton, _sizeExprButton, _textBGExprButton,
                         _padLeftExprButton, _padRightExprButton, _padTopExprButton,
                         _padBottomExprButton, _lineWidthExprButton, _hiddenExprButton,
                         _hyperlinkExprButton, _pageBreakDisabledExprButton, _pageNameExprButton,
                         _initialPageNameExprButton, _noRowsMessageExprButton ])
    RDLSetToolbarIcon(b, RDLToolbarGlyphExpression);
  // One list, kept once: -stackBoxes: hides everything in it and then shows
  // the sections the selection calls for. It used to be written out twice, and
  // a section missing from the second copy stayed on screen under the next
  // selection -- two inspectors drawn over each other.
  _sections = @[ _docBox, _paperBox, _bandBox, _printBox, _geoBox, _textBox, _lineBox, _rectBox, _imageBox,
                 _subreportBox, _chartBox, _tablixBox, _tablixOptionsBox, _cellBox, _nameBox, _visibilityBox,
                 _linkBox, _keepBox, _pageBox ];
  for (NSView *box in _sections)
    [self addSubview:box];
  [self declareBindings];
}

// A button that opens a sort says how many keys it holds, since a sort is
// otherwise invisible from here.
- (void)syncSortingButton:(NSButton *)button count:(NSUInteger)count {
  [button setTitle:count ? [NSString stringWithFormat:@"Sorting (%lu)…", (unsigned long)count] : @"Sorting…"];
}

// The rows of a tablix, sorted before any group sees them.
- (void)editTablixSorting:(id)sender {
  (void)sender;
  RDLItem *item = [_context selectedItem];
  if (![item isKindOfClass:[RDLTablix class]])
    return;
  RDLTablix *tablix = (RDLTablix *)item;
  RDLDataSet *ds = [_context.report dataSetNamed:tablix.dataSetName];
  NSArray<RDLSortExpression *> *edited =
      [RDLSortEditor runForSortExpressions:tablix.sortExpressions
                                     title:tablix.name
                                    fields:[(ds ?: [_context.report.dataSets firstObject]) fieldNames]
                                    report:_context.report];
  if (edited == nil || RDLSortExpressionsEqual(edited, tablix.sortExpressions))
    return;
  [_context.editor setValue:[edited mutableCopy] forKeyPath:@"sortExpressions" ofItem:tablix];
  [self reload];
}

// A chart is a data region too, and RDL filters it in the same terms. The
// tablix opens the same panel from its own editor; this is the chart's way in.
- (void)editChartFilters:(id)sender {
  (void)sender;
  RDLItem *item = [_context selectedItem];
  if (![item isKindOfClass:[RDLChart class]])
    return;
  RDLChart *chart = (RDLChart *)item;
  RDLDataSet *ds = [_context.report dataSetNamed:chart.dataSetName];
  NSArray<RDLFilter *> *edited =
      [RDLFilterEditor runForFilters:chart.filters
                               title:chart.name
                              fields:[(ds ?: [_context.report.dataSets firstObject]) fieldNames]
                              report:_context.report];
  if (edited == nil)
    return;
  [_context.editor setValue:[edited mutableCopy] forKeyPath:@"filters" ofItem:chart];
}

// Whether the report this names has actually been found, said in the one place
// a person is looking when it has not: a subreport whose file is missing draws
// as "Error: Subreport could not be shown", and this is why.
- (void)fillSubreportStatus:(RDLSubreport *)sub {
  if ([sub.reportName length] == 0) {
    [_subreportStatusLabel setStringValue:@"No report named yet."];
    return;
  }
  if (sub.definition != nil) {
    NSUInteger declared = [sub.definition.parameters count];
    [_subreportStatusLabel
        setStringValue:[NSString stringWithFormat:@"Found. %lu parameter%s declared, %lu passed.",
                                                  (unsigned long)declared, declared == 1 ? "" : "s",
                                                  (unsigned long)[sub.parameters count]]];
    return;
  }
  [_subreportStatusLabel setStringValue:@"Not loaded yet — save this report, then Edit Subreport."];
}

// The subreport's contents belong to another file, so this asks whoever owns
// windows to open it. Sent up the responder chain rather than done here: an
// inspector has no business opening documents, and the window that does is
// what knows where to put the second one.
- (void)openSubreportDocument:(id)sender {
  (void)sender;
  [NSApp sendAction:@selector(editSubreport:) to:nil from:self];
}

// What this report hands to the subreport. One undoable step, like the filter
// panel: the whole array goes back at once.
- (void)editSubreportParameters:(id)sender {
  (void)sender;
  RDLItem *item = [_context selectedItem];
  if (![item isKindOfClass:[RDLSubreport class]])
    return;
  RDLSubreport *sub = (RDLSubreport *)item;
  NSArray<RDLSubreportParameter *> *edited =
      [RDLSubreportParametersEditor runForSubreport:sub inReport:_context.report];
  if (edited == nil)
    return;
  [_context.editor setValue:[edited mutableCopy] forKeyPath:@"parameters" ofItem:sub];
  [self reload];
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

// Opens the Report-Builder-style tablix editor for the selected tablix.
- (void)editTablix:(id)sender {
  (void)sender;
  RDLItem *it = [_context selectedItem];
  if (it == nil || ![it isKindOfClass:[RDLTablix class]])
    return;
  if ([RDLTablixEditor runForTablix:(RDLTablix *)it context:_context]) {
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
  _bindings = [[RDLFieldBindings alloc] init];
  // What every item has. Hidden and the break's Disabled are True, False or an
  // expression; the rest of the pagination is a box to tick and a list.
  [_bindings bind:_hiddenField keyPath:@"hidden" scope:RDLFieldScopeItem
             kind:RDLFieldKindValue values:nil placeholder:@"False"];
  [_bindings bind:_hyperlinkField keyPath:@"hyperlink" scope:RDLFieldScopeItem
             kind:RDLFieldKindValue values:nil placeholder:@"https://"];
  [_bindings bind:_keepTogetherCheck keyPath:@"keepTogether" scope:RDLFieldScopeItem
             kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];
  [_bindings bind:_resetPageNumberCheck keyPath:@"resetPageNumber" scope:RDLFieldScopeItem
             kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];
  [_bindings bind:_pageBreakPop
          keyPath:@"pageBreak"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_pageBreakPop, RDLPageBreakLocationNone, RDLPageBreakLocationBetween,
                               ^(NSInteger v) { return RDLStringFromPageBreakLocation((RDLPageBreakLocation)v); })
      placeholder:nil];
  [_bindings bind:_pageBreakDisabledField keyPath:@"pageBreakDisabled" scope:RDLFieldScopeItem
             kind:RDLFieldKindValue values:nil placeholder:@"False"];
  [_bindings bind:_pageNameField keyPath:@"pageName" scope:RDLFieldScopeItem
             kind:RDLFieldKindValue values:nil placeholder:nil];
  [_bindings bind:_noRowsMessageField keyPath:@"noRowsMessage" scope:RDLFieldScopeItem
             kind:RDLFieldKindText values:nil placeholder:nil];
  [_bindings bind:_layoutDirectionPop
          keyPath:@"layoutDirection"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_layoutDirectionPop, RDLLayoutDirectionLTR, RDLLayoutDirectionRTL,
                               ^(NSInteger v) { return v == RDLLayoutDirectionRTL ? @"Right to left" : @"Left to right"; })
      placeholder:nil];
  [_bindings bind:_groupsBeforeRowHeadersField keyPath:@"groupsBeforeRowHeaders" scope:RDLFieldScopeItem
             kind:RDLFieldKindInteger values:nil placeholder:nil];
  for (NSArray *pair in @[ @[ @"repeatColumnHeadersCheck", @"repeatColumnHeaders" ],
                           @[ @"repeatRowHeadersCheck", @"repeatRowHeaders" ],
                           @[ @"fixedColumnHeadersCheck", @"fixedColumnHeaders" ],
                           @[ @"fixedRowHeadersCheck", @"fixedRowHeaders" ],
                           @[ @"omitBorderCheck", @"omitBorderOnPageBreak" ] ])
    [_bindings bind:[self valueForKey:pair[0]] keyPath:pair[1] scope:RDLFieldScopeItem
               kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];
  [_bindings bind:_printOnFirstPageCheck keyPath:@"printOnFirstPage" scope:RDLFieldScopeBand
             kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];
  [_bindings bind:_printOnLastPageCheck keyPath:@"printOnLastPage" scope:RDLFieldScopeBand
             kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];
  [_bindings bind:_initialPageNameField keyPath:@"initialPageName" scope:RDLFieldScopeReport
             kind:RDLFieldKindValue values:nil placeholder:nil];
  [_bindings bind:_consumeWhitespaceCheck keyPath:@"consumeContainerWhitespace" scope:RDLFieldScopeReport
             kind:RDLFieldKindCheck values:@[ @NO, @YES ] placeholder:nil];

  // Item geometry.
  [_bindings bind:_leftField keyPath:@"left" scope:RDLFieldScopeItem
             kind:RDLFieldKindNumber];
  [_bindings bind:_topField keyPath:@"top" scope:RDLFieldScopeItem
             kind:RDLFieldKindNumber];
  [_bindings bind:_widthField keyPath:@"width" scope:RDLFieldScopeItem
             kind:RDLFieldKindNumber];
  [_bindings bind:_heightField keyPath:@"height" scope:RDLFieldScopeItem
             kind:RDLFieldKindNumber];

  // Textbox.
  [_bindings bind:_fontField keyPath:@"style.fontFamily" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression values:nil placeholder:@"Georgia"];
  [_bindings bind:_sizeField keyPath:@"style.fontSize" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"10pt"];
  // Vocabulary popups map menu index to the enum case, so the model value and
  // the menu title no longer have to be the same word ("Roman" shows Normal).
  // Each holds its whole vocabulary, filled from the enumeration: a popup that
  // did not offer a value showed the first entry instead, and the next edit of
  // anything in the section wrote that wrong value into the file.
  [_bindings bind:_weightPop
          keyPath:@"style.fontWeight"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_weightPop, RDLFontWeightLighter, RDLFontWeightExtraBold,
                               ^(NSInteger v) { return RDLStringFromFontWeight((RDLFontWeight)v); })
      placeholder:nil];
  [_bindings bind:_alignPop
          keyPath:@"style.textAlign"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_alignPop, RDLTextAlignGeneral, RDLTextAlignJustify,
                               ^(NSInteger v) { return RDLStringFromTextAlign((RDLTextAlign)v); })
      placeholder:nil];
  [_bindings bind:_verticalPop
          keyPath:@"style.verticalAlign"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_verticalPop, RDLVerticalAlignTop, RDLVerticalAlignBottom,
                               ^(NSInteger v) { return RDLStringFromVerticalAlign((RDLVerticalAlign)v); })
      placeholder:nil];
  [_bindings bind:_decorationPop
          keyPath:@"style.textDecoration"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_decorationPop, RDLTextDecorationNone, RDLTextDecorationLineThrough,
                               ^(NSInteger v) { return RDLStringFromTextDecoration((RDLTextDecoration)v); })
      placeholder:nil];
  // Italic is one of two, so it is a box to tick rather than a list of two.
  [_bindings bind:_italicCheck
          keyPath:@"style.fontStyle"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindCheck
           values:@[ @(RDLFontStyleNormal), @(RDLFontStyleItalic) ]
      placeholder:nil];
  [_bindings bind:_textBGField keyPath:@"style.backgroundColor" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression];
  // Padding, which the engine has always drawn and the inspector never showed:
  // 2pt a side is what a style that says nothing gets, so that is what the
  // empty field means rather than none.
  [_bindings bind:_padLeftField keyPath:@"style.paddingLeft" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"2pt"];
  [_bindings bind:_padRightField keyPath:@"style.paddingRight" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"2pt"];
  [_bindings bind:_padTopField keyPath:@"style.paddingTop" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"2pt"];
  [_bindings bind:_padBottomField keyPath:@"style.paddingBottom" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"2pt"];
  [_bindings bind:_colorField keyPath:@"style.color" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression values:nil placeholder:@"#1a1916"];
  [_bindings bind:_colorWell keyPath:@"style.color" scope:RDLFieldScopeItem
             kind:RDLFieldKindColor];
  [_bindings bind:_formatField keyPath:@"style.format" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression];
  // A text box may be written in its own culture: dates and numbers in it are
  // then formatted that way whatever the report says. Empty means "the
  // report's", which is what nearly every text box wants.
  [_bindings bind:_languageField keyPath:@"style.language" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression values:nil placeholder:nil];

  // Line and Rectangle each expose one style property.
  // A line is drawn in its border's colour, at its border's width, dashed as
  // its border says -- which is what MS-RDL means by a Line's style, and what
  // every backend reads. The ink field used to write style.color, where only a
  // line with no border colour of its own would ever show it.
  [_bindings bind:_lineColorField keyPath:@"style.border.color" scope:RDLFieldScopeItem
             kind:RDLFieldKindText values:nil placeholder:@"#1a1916"];
  [_bindings bind:_lineWidthField keyPath:@"style.border.width" scope:RDLFieldScopeItem
             kind:RDLFieldKindLengthOrExpression values:nil placeholder:@"1pt"];
  // None, Dotted, Dashed and Solid: the whole of what a line can be drawn as.
  // The treatments past Solid -- Double, Groove and the rest -- shade an edge
  // of a box, and a line stroked in any of them comes out solid, so offering
  // them would be offering something that does not happen.
  [_bindings bind:_lineDashPop
          keyPath:@"style.border.style"
            scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:RDLFillPopUp(_lineDashPop, RDLBorderStyleNone, RDLBorderStyleSolid,
                               ^(NSInteger v) { return RDLStringFromBorderStyle((RDLBorderStyle)v); })
      placeholder:nil];
  [_bindings bind:_rectBGField keyPath:@"style.backgroundColor" scope:RDLFieldScopeItem
             kind:RDLFieldKindTextOrExpression];
  [_bindings bind:_bgColorWell keyPath:@"style.backgroundColor" scope:RDLFieldScopeItem
             kind:RDLFieldKindColor];

  // Image.
  [_bindings bind:_imageValueField keyPath:@"value" scope:RDLFieldScopeItem
             kind:RDLFieldKindText];
  [_bindings bind:_imageSourcePop keyPath:@"source" scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:@[ @(RDLImageSourceEmbedded), @(RDLImageSourceExternal) ]
      placeholder:nil];
  [_bindings bind:_imageSizingPop keyPath:@"sizing" scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:@[ @(RDLImageSizingFit), @(RDLImageSizingFitProportional),
                     @(RDLImageSizingClip), @(RDLImageSizingAutoSize) ]
      placeholder:nil];

  // Subreport. The name is a file beside this report, written the way MS-RDL
  // writes it: without the .rdl.
  [_bindings bind:_subreportNameField keyPath:@"reportName" scope:RDLFieldScopeItem
             kind:RDLFieldKindText];

  // Chart.
  [_bindings bind:_chartDatasetPop keyPath:@"dataSetName" scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpTitle];
  [_bindings bind:_titleField keyPath:@"title" scope:RDLFieldScopeItem
             kind:RDLFieldKindText];
  // Every type the kit models, from the enumeration rather than from a list
  // typed into the XIB: a chart of a type the popup did not offer showed as
  // Column, and the first edit of any chart field wrote that back.
  [_chartKindPop removeAllItems];
  NSMutableArray<NSNumber *> *chartTypes = [NSMutableArray array];
  for (RDLChartType type = RDLChartTypeColumn; type <= RDLChartTypeRadar; type++) {
    [_chartKindPop addItemWithTitle:RDLStringFromChartType(type)];
    [chartTypes addObject:@(type)];
  }
  [_bindings bind:_chartKindPop keyPath:@"chartType" scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpIndex
           values:chartTypes
      placeholder:nil];
  [_bindings bind:_catField keyPath:@"categoryField" scope:RDLFieldScopeItem
             kind:RDLFieldKindText];
  [_bindings bind:_valField keyPath:@"valueField" scope:RDLFieldScopeItem
             kind:RDLFieldKindText];

  // Tablix.
  [_bindings bind:_tablixDatasetPop keyPath:@"dataSetName" scope:RDLFieldScopeItem
             kind:RDLFieldKindPopUpTitle];

  // Band and report.
  [_bindings bind:_bandHField keyPath:@"height" scope:RDLFieldScopeBand
             kind:RDLFieldKindNumber];
  [_bindings bind:_docNameField keyPath:@"name" scope:RDLFieldScopeReport
             kind:RDLFieldKindText];
  [_bindings bind:_authorField keyPath:@"author" scope:RDLFieldScopeReport
             kind:RDLFieldKindText];
  // The report's own culture: a code, or an expression -- "=User!Language" to
  // follow whoever is reading, "=Parameters!Culture.Value" to let them choose.
  // The unit is the report's, the way its page size is: every measurement box
  // in the inspector is read and written in it.
  [_bindings bind:_unitPop keyPath:@"unit" scope:RDLFieldScopeReport
             kind:RDLFieldKindPopUpIndex
           values:@[ @(RDLReportUnitInch), @(RDLReportUnitCentimeter) ]
      placeholder:nil];
  [_bindings bind:_docLanguageField keyPath:@"language" scope:RDLFieldScopeReport
             kind:RDLFieldKindValue values:nil placeholder:RDLHostLanguage()];
  [_bindings bind:_descField keyPath:@"reportDescription" scope:RDLFieldScopeReport
             kind:RDLFieldKindText];
  [_bindings bind:_headerHField keyPath:@"pageHeader.height" scope:RDLFieldScopeReport
             kind:RDLFieldKindNumber];
  [_bindings bind:_bodyHField keyPath:@"body.height" scope:RDLFieldScopeReport
             kind:RDLFieldKindNumber];
  [_bindings bind:_footerHField keyPath:@"pageFooter.height" scope:RDLFieldScopeReport
             kind:RDLFieldKindNumber];
}

// A popup holding a whole vocabulary: every case from `first` to `last`, named
// as the model names it, and the matching values for the binding to write.
static NSArray<NSNumber *> *RDLFillPopUp(NSPopUpButton *pop, NSInteger first, NSInteger last,
                                         NSString *(^name)(NSInteger)) {
  [pop removeAllItems];
  NSMutableArray<NSNumber *> *values = [NSMutableArray array];
  for (NSInteger value = first; value <= last; value++) {
    [pop addItemWithTitle:name(value) ?: @""];
    [values addObject:@(value)];
  }
  return values;
}

#pragma mark - Fill (model → UI)

- (void)stackBoxes:(NSArray *)boxes {
  for (NSView *v in _sections)
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

// Applied once the XIB's objects exist.
- (void)awakeFromNib {
  [super awakeFromNib];
  [self applyExpressionContexts];
}

// Every measurement box says which unit it is in, because "0.5" means two very
// different rectangles in the two of them.
- (void)syncUnitLabels {
  NSString *abbr = RDLAbbreviationForReportUnit(_context.report.unit);
  NSDictionary *titles = @{
    @"headerHLabel" : @"Header",
    @"bodyHLabel" : @"Body",
    @"footerHLabel" : @"Footer",
    @"paperWidthLabel" : @"Width",
    @"paperHeightLabel" : @"Height",
    @"leftMarginLabel" : @"Left",
    @"rightMarginLabel" : @"Right",
    @"topMarginLabel" : @"Top",
    @"bottomMarginLabel" : @"Bottom",
    @"columnSpacingLabel" : @"Spacing",
    @"bandHeightLabel" : @"Height",
    @"cellWidthLabel" : @"Column width",
    @"tablixHeaderLabel" : @"Header",
    @"tablixRowLabel" : @"Row"
  };
  for (NSString *key in titles) {
    NSTextField *label = [self valueForKey:key];
    [label setStringValue:[NSString stringWithFormat:@"%@ %@", titles[key], abbr]];
  }
}

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  [self syncUnitLabels];
  RDLReport *report = _context.report;
  RDLSelection *sel = _context.selection;
  RDLItem *it = [_context selectedItem];
  RDLBand *band = sel.scope == RDLSelectionScopeBand ? [report bandWithKey:sel.bandKey] : nil;
  // The Report tab shows the document's own fields whatever is selected, which
  // is the same branch the shared inspector falls to when nothing is.
  if (_showsReportOnly) {
    it = nil;
    band = nil;
  }

  if (it != nil) {
    // An item that is the contents of a tablix cell has no geometry of its
    // own: MS-RDL ignores Top/Left/Height/Width inside CellContents, and the
    // cell decides both. Offering the boxes would be offering to change
    // numbers nothing reads.
    RDLTablix *cellTablix = nil;
    RDLTablixCell *cell = [report cellContainingItem:it tablix:&cellTablix];
    BOOL inCell = cell != nil;
    [_kindLabel setStringValue:inCell
                                   ? [NSString stringWithFormat:@"%@ · %@ · in %@",
                                                                it.rdlElementName, it.name,
                                                                cellTablix.name ?: @"a table"]
                                   : [NSString stringWithFormat:@"%@ · %@", it.rdlElementName,
                                                                it.name]];
    [_nameField setStringValue:it.name ?: @""];
    // Its name, which an item in a cell has too; its geometry, which it does not.
    NSMutableArray *boxes = [NSMutableArray arrayWithObject:_nameBox];
    if (!inCell)
      [boxes addObject:_geoBox];
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
    } else if ([it isKindOfClass:[RDLSubreport class]]) {
      [boxes addObject:_subreportBox];
      [self fillSubreportStatus:(RDLSubreport *)it];
    } else if ([it isKindOfClass:[RDLChart class]]) {
      [boxes addObject:_chartBox];
        [self rebuildDatasetPop:_chartDatasetPop selecting:[(RDLChart *)it dataSetName]];
    } else if ([it isKindOfClass:[RDLTablix class]]) {
      [boxes addObject:_tablixBox];
      [boxes addObject:_tablixOptionsBox];
      [self syncSortingButton:_tablixSortingButton count:[[(RDLTablix *)it sortExpressions] count]];
      [self rebuildDatasetPop:_tablixDatasetPop selecting:[(RDLTablix *)it dataSetName]];
      [self fillRowHeightsOfTablix:(RDLTablix *)it];
    }
    [boxes addObjectsFromArray:[self commonBoxesForItem:it]];
    [self rebuildTogglePopFor:it];
    // An item in a tablix cell: the column it is in, whose width is the cell's.
    NSUInteger cellRow = 0, cellColumn = 0;
    if (cell != nil && [cellTablix getRow:&cellRow column:&cellColumn ofCell:cell] &&
        [self fillColumn:(NSInteger)cellColumn ofTablix:cellTablix]) {
      // A text box and a rectangle carry the button in their own sections, and
      // a line's border is the line, edited in its section.
      BOOL ownSectionHasBorders = [it isKindOfClass:[RDLTextbox class]] ||
                                  [it isKindOfClass:[RDLRectangle class]] ||
                                  [it isKindOfClass:[RDLLine class]];
      [self showCellBorders:!ownSectionHasBorders];
      [boxes addObject:_cellBox];
    }
    [self stackBoxes:boxes];
  } else if (sel.scope == RDLSelectionScopeTablixCell && sel.tablix != nil && !_showsReportOnly) {
    // An empty cell: nothing in it to describe, so what is shown is the column
    // it belongs to -- its width -- and the label says where in the table it is.
    [_kindLabel setStringValue:[NSString stringWithFormat:@"Empty cell · %@ · row %ld, column %ld",
                                                          sel.tablix.name ?: @"table",
                                                          (long)sel.cellRow + 1,
                                                          (long)sel.cellColumn + 1]];
    NSMutableArray *boxes = [NSMutableArray array];
    NSInteger bodyColumn = [RDLTablixGeometry bodyColumnOf:sel.tablix
                                             forGridColumn:(NSUInteger)MAX(sel.cellColumn, 0)];
    if (bodyColumn >= 0 && [self fillColumn:bodyColumn ofTablix:sel.tablix]) {
      [self showCellBorders:YES];
      [boxes addObject:_cellBox];
    }
    [self stackBoxes:boxes];
  } else if (band != nil) {
    [_kindLabel setStringValue:[RDLItemFactory titleForBandKey:sel.bandKey]];
    BOOL hasStyle = [RDLReport bandKeySupportsBackground:sel.bandKey];
    [_bandBGField setEditable:hasStyle];
    [_bandBGField setEnabled:hasStyle];
    [_bandBGField setStringValue:hasStyle ? (band.style.backgroundColor ?: @"") : @""];
    // The page header and footer choose the pages they appear on; the body is
    // on all of them.
    BOOL pageSection = ![sel.bandKey isEqualToString:@"body"];
    [self stackBoxes:pageSection ? @[ _bandBox, _printBox ] : @[ _bandBox ]];
  } else {
    [_kindLabel setStringValue:report.name ?: @"Report"];
    [self fillPaper:report.page];
    [self stackBoxes:@[ _docBox, _paperBox ]];
  }

  [_bindings fillFromItem:it band:band report:report];
  _reloading = NO;
}

// What MS-RDL lets each kind say. Visibility is every item's; a link is a text
// box's or an image's; KeepTogether is on a text box, a subreport, a rectangle
// and a data region; page breaks and a page name only on a rectangle or a
// data region.
- (NSArray<NSView *> *)commonBoxesForItem:(RDLItem *)it {
  NSMutableArray<NSView *> *boxes = [NSMutableArray arrayWithObject:_visibilityBox];
  BOOL region = [it isKindOfClass:[RDLRectangle class]] || [it isKindOfClass:[RDLTablix class]] ||
                [it isKindOfClass:[RDLChart class]];
  if ([it isKindOfClass:[RDLTextbox class]] || [it isKindOfClass:[RDLImage class]])
    [boxes addObject:_linkBox];
  if (region || [it isKindOfClass:[RDLTextbox class]] || [it isKindOfClass:[RDLSubreport class]])
    [boxes addObject:_keepBox];
  if (region)
    [boxes addObject:_pageBox];
  return boxes;
}

// The text boxes that could toggle `it`: every one in the report but itself,
// by name, after None. A ToggleItem naming something else -- a text box the
// report no longer has -- is listed too, so showing it does not lose it.
- (void)rebuildTogglePopFor:(RDLItem *)it {
  [_toggleItemPop removeAllItems];
  [_toggleItemPop addItemWithTitle:@"None"];
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (RDLBand *band in [_context.report allBands])
    for (RDLItem *top in band.items)
      for (RDLItem *candidate in [top itemsIncludingNested])
        if ([candidate isKindOfClass:[RDLTextbox class]] && candidate != it && [candidate.name length] &&
            ![names containsObject:candidate.name])
          [names addObject:candidate.name];
  if ([it.toggleItem length] && ![names containsObject:it.toggleItem])
    [names addObject:it.toggleItem];
  for (NSString *name in names) {
    // addItemWithTitle: would fold a name into one already there.
    [[_toggleItemPop menu] addItemWithTitle:name action:NULL keyEquivalent:@""];
  }
  if ([it.toggleItem length])
    [_toggleItemPop selectItemAtIndex:(NSInteger)[names indexOfObject:it.toggleItem] + 1];
  else
    [_toggleItemPop selectItemAtIndex:0];
}

- (BOOL)applyToggleControl:(id)sender item:(RDLItem *)it {
  if (sender != _toggleItemPop)
    return NO;
  NSInteger index = [_toggleItemPop indexOfSelectedItem];
  NSString *name = index > 0 ? [_toggleItemPop titleOfSelectedItem] : nil;
  if (it != nil && !(name == it.toggleItem || [name isEqualToString:it.toggleItem]))
    [_context.editor setValue:name forKeyPath:@"toggleItem" ofItem:it];
  return YES;
}

// The width of a tablix's body column, or NO when there is no such column --
// in which case the section is not shown at all rather than shown empty. What
// the column's cells show and how they align are the cells' own, and are edited
// by selecting what is in them.
// A measurement as the inspector shows it: in the report's unit.
- (NSString *)stringFromInches:(CGFloat)inches {
  return [NSString stringWithFormat:@"%.3f", RDLUnitsFromInches(inches, _context.report.unit)];
}

- (BOOL)fillColumn:(NSInteger)column ofTablix:(RDLTablix *)tablix {
  NSArray<RDLTablixColumn *> *columns = tablix.tablixBody.columns;
  if (column < 0 || column >= (NSInteger)[columns count])
    return NO;
  [_cellWidthField setStringValue:[self stringFromInches:columns[(NSUInteger)column].width]];
  return YES;
}

// The two rows a tablix's columns are described by: the heading row and the
// value row. A field is blank where the tablix has no such row -- a
// crosstab's headings are its column groups' headers.
- (void)fillRowHeightsOfTablix:(RDLTablix *)tablix {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  NSInteger heading = [RDLTablixStructure headingRowOfTablix:tablix];
  NSInteger value = [RDLTablixStructure valueRowOfTablix:tablix];
  [_tablixHeaderHField setStringValue:heading >= 0 ? [self stringFromInches:rows[(NSUInteger)heading].height] : @""];
  [_tablixRowHField setStringValue:value >= 0 ? [self stringFromInches:rows[(NSUInteger)value].height] : @""];
}

// A height typed into one of them: that row's, set in place.
- (BOOL)applyRowHeightControl:(id)sender {
  if (sender != _tablixHeaderHField && sender != _tablixRowHField)
    return NO;
  RDLItem *it = [_context selectedItem];
  if (![it isKindOfClass:[RDLTablix class]])
    return YES;
  RDLTablix *tablix = (RDLTablix *)it;
  NSInteger row = sender == _tablixHeaderHField ? [RDLTablixStructure headingRowOfTablix:tablix]
                                                : [RDLTablixStructure valueRowOfTablix:tablix];
  CGFloat height = RDLInchesFromUnits([[(NSTextField *)sender stringValue] doubleValue], _context.report.unit);
  if (row >= 0 && height > 0)
    [_context.editor setTablixRow:(NSUInteger)row height:height ofTablix:tablix];
  return YES;
}

// A column's width typed in: the column the selected cell item, or the selected
// empty cell, is in -- set exactly, and in place.
- (BOOL)applyCellControl:(id)sender {
  if (sender != _cellWidthField)
    return NO;
  RDLSelection *sel = _context.selection;
  RDLTablix *tablix = nil;
  NSInteger column = -1;
  if (sel.scope == RDLSelectionScopeTablixCell && sel.tablix != nil) {
    tablix = sel.tablix;
    column = [RDLTablixGeometry bodyColumnOf:tablix forGridColumn:(NSUInteger)MAX(sel.cellColumn, 0)];
  } else {
    RDLTablixCell *cell = [_context.report cellContainingItem:[_context selectedItem] tablix:&tablix];
    NSUInteger row = 0, bodyColumn = 0;
    if (cell != nil && [tablix getRow:&row column:&bodyColumn ofCell:cell])
      column = (NSInteger)bodyColumn;
  }
  CGFloat width = RDLInchesFromUnits([[_cellWidthField stringValue] doubleValue], _context.report.unit);
  if (tablix != nil && column >= 0 && width > 0)
    [_context.editor setTablixColumn:(NSUInteger)column width:width ofTablix:tablix];
  return YES;
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
  if (!RDLIsTypingEvent())
    return;
  NSTextView *tv = [[n userInfo] objectForKey:@"NSFieldEditor"];
  if (tv && RDLShouldAutoComplete([tv string], [tv selectedRange])) {
    _completing = YES;
    [tv complete:nil];
    _completing = NO;
  }
}

- (NSArray *)control:(NSControl *)control
               textView:(NSTextView *)textView
            completions:(NSArray *)words
    forPartialWordRange:(NSRange)charRange
    indexOfSelectedItem:(RDLCompletionIndex *)index {
  (void)control;
  (void)words;
  if (index)
    *index = 0;
  RDLItem *it = [_context selectedItem];
  RDLExpressionScope *scope =
        [RDLExpressionScope scopeWithReport:_context.report
                                 dataSetName:[it isKindOfClass:[RDLDataRegion class]]
                                                 ? [(RDLDataRegion *)it dataSetName]
                                                 : nil];
  return RDLExpressionCompletions([textView string], charRange, scope);
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
  if (sender == _nameField && it != nil) {
    // A name that is not an RDL name, or is another item's, is refused and the
    // field goes back to the name the item has.
    NSString *name = [[_nameField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![editor renameItem:it to:name]) {
      NSBeep();
      [_nameField setStringValue:it.name ?: @""];
    }
    return;
  }
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
    // Read before anything changes: making the style is an edit, the inspector
    // reloads on it, and the field then shows the colour the band had -- none.
    NSString *color = [[_bandBGField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [editor beginGroup:@"Band Background"];
    // Creating the style belongs to the same step, so undoing does not leave
    // an empty Style behind for the writer to emit.
    if (band.style == nil)
      [editor setValue:[[RDLStyle alloc] init] forKeyPath:@"style" ofBandWithKey:sel.bandKey];
    [editor setValue:[color length] ? color : nil
          forKeyPath:@"style.backgroundColor"
       ofBandWithKey:sel.bandKey];
    [editor endGroup];
    return;
  }

  // Page dimensions and margins carry the body width with them, so the
  // dependency lives in RDLEditor rather than here.
  if ([self applyCellControl:sender] || [self applyRowHeightControl:sender] ||
      [self applyToggleControl:sender item:it])
    return;
  [self applyPaperControl:sender];
}

#pragma mark - The paper

- (void)fillPaper:(RDLPage *)page {
  NSDictionary *size = [page matchingStandardSize];
  NSUInteger sizeIndex = size ? [[RDLPage standardSizes] indexOfObject:size] : NSNotFound;
  [_pagePop selectItemAtIndex:sizeIndex != NSNotFound ? (NSInteger)sizeIndex : [_pagePop numberOfItems] - 1];
  [_orientationPop selectItemAtIndex:[page isLandscape] ? 1 : 0];
  [_paperWidthField setStringValue:[self stringFromInches:page.pageWidth]];
  [_paperHeightField setStringValue:[self stringFromInches:page.pageHeight]];
  [_leftMarginField setStringValue:[self stringFromInches:page.leftMargin]];
  [_rightMarginField setStringValue:[self stringFromInches:page.rightMargin]];
  [_topMarginField setStringValue:[self stringFromInches:page.topMargin]];
  [_bottomMarginField setStringValue:[self stringFromInches:page.bottomMargin]];
  [_columnsField setStringValue:[NSString stringWithFormat:@"%ld", (long)MAX(page.columns, (NSInteger)1)]];
  [_columnSpacingField setStringValue:[self stringFromInches:page.columnSpacing]];
  [_pageBGField setStringValue:page.style.backgroundColor ?: @""];
}

- (CGFloat)inchesInField:(NSTextField *)field {
  return RDLInchesFromUnits([[field stringValue] doubleValue], _context.report.unit);
}

// The paper's controls, each through the editor, which keeps the body's width
// in step with the page. A size keeps the page the way up it is.
- (BOOL)applyPaperControl:(id)sender {
  RDLEditor *editor = _context.editor;
  RDLPage *page = _context.report.page;
  if (sender == _pagePop) {
    NSArray *sizes = [RDLPage standardSizes];
    NSInteger i = [_pagePop indexOfSelectedItem];
    if (i >= 0 && i < (NSInteger)[sizes count]) {
      CGFloat shorter = [sizes[(NSUInteger)i][@"width"] doubleValue];
      CGFloat longer = [sizes[(NSUInteger)i][@"height"] doubleValue];
      BOOL landscape = [page isLandscape];
      [editor setPageWidth:landscape ? longer : shorter height:landscape ? shorter : longer];
    }
  } else if (sender == _orientationPop) {
    BOOL landscape = [_orientationPop indexOfSelectedItem] == 1;
    if (landscape != [page isLandscape])
      [editor setPageWidth:page.pageHeight height:page.pageWidth];
  } else if (sender == _paperWidthField || sender == _paperHeightField) {
    [editor setPageWidth:[self inchesInField:_paperWidthField] height:[self inchesInField:_paperHeightField]];
  } else if (sender == _leftMarginField) {
    [editor setMargin:[self inchesInField:sender] forEdge:RDLBoxEdgeLeft];
  } else if (sender == _rightMarginField) {
    [editor setMargin:[self inchesInField:sender] forEdge:RDLBoxEdgeRight];
  } else if (sender == _topMarginField) {
    [editor setMargin:[self inchesInField:sender] forEdge:RDLBoxEdgeTop];
  } else if (sender == _bottomMarginField) {
    [editor setMargin:[self inchesInField:sender] forEdge:RDLBoxEdgeBottom];
  } else if (sender == _columnsField || sender == _columnSpacingField) {
    [editor setColumns:[[_columnsField stringValue] integerValue]
               spacing:[self inchesInField:_columnSpacingField]];
  } else if (sender == _pageBGField) {
    [editor setPageBackgroundColor:[[_pageBGField stringValue]
                                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
  } else {
    return NO;
  }
  // A value the editor refused, or put right, shows as it is.
  [self fillPaper:page];
  return YES;
}

// What each expression-capable field has to produce. Set once: it is a
// property of the attribute, not of what is selected.
- (void)applyExpressionContexts {
  _valueField.expressionContext = RDLExpressionContextText;
  _fontField.expressionContext = RDLExpressionContextText;
  _colorField.expressionContext = RDLExpressionContextColor;
  _rectBGField.expressionContext = RDLExpressionContextColor;
  _formatField.expressionContext = RDLExpressionContextText;
  _languageField.expressionContext = RDLExpressionContextText;
  _docLanguageField.expressionContext = RDLExpressionContextText;
  _sizeField.expressionContext = RDLExpressionContextLength;
  _hiddenField.expressionContext = RDLExpressionContextBoolean;
  _hyperlinkField.expressionContext = RDLExpressionContextText;
  _pageBreakDisabledField.expressionContext = RDLExpressionContextBoolean;
  _pageNameField.expressionContext = RDLExpressionContextText;
  _initialPageNameField.expressionContext = RDLExpressionContextText;
  _noRowsMessageField.expressionContext = RDLExpressionContextText;
}

// Which field each f(x) button belongs to. One action for all of them: the
// button says which attribute is being edited, and the field is where the
// answer goes back.
- (RDLExpressionField *)expressionFieldForButton:(id)sender {
  if (sender == _valueExprButton) return _valueField;
  if (sender == _fontExprButton) return _fontField;
  if (sender == _colorExprButton) return _colorField;
  if (sender == _formatExprButton) return _formatField;
  if (sender == _languageExprButton) return _languageField;
  if (sender == _docLanguageExprButton) return _docLanguageField;
  if (sender == _rectBGExprButton) return _rectBGField;
  if (sender == _textBGExprButton) return _textBGField;
  if (sender == _sizeExprButton) return _sizeField;
  if (sender == _padLeftExprButton) return _padLeftField;
  if (sender == _padRightExprButton) return _padRightField;
  if (sender == _padTopExprButton) return _padTopField;
  if (sender == _padBottomExprButton) return _padBottomField;
  if (sender == _lineWidthExprButton) return _lineWidthField;
  if (sender == _hiddenExprButton) return _hiddenField;
  if (sender == _hyperlinkExprButton) return _hyperlinkField;
  if (sender == _pageBreakDisabledExprButton) return _pageBreakDisabledField;
  if (sender == _pageNameExprButton) return _pageNameField;
  if (sender == _initialPageNameExprButton) return _initialPageNameField;
  if (sender == _noRowsMessageExprButton) return _noRowsMessageField;
  return nil;
}

// The borders of the selected item: the default and the four edges, in a panel
// of their own because there are fifteen values behind them and the section
// has room for a button.
- (void)editBorders:(id)sender {
  (void)sender;
  RDLItem *item = [_context selectedItem];
  BOOL accepted = item != nil ? [RDLBordersEditor runForItem:item context:_context]
                              : [RDLBordersEditor runForSelectedEmptyCellInContext:_context];
  if (accepted)
    [self reload];
}

// The cell section's Borders… button, shown only where the cell's contents
// have no section of their own that offers it, and the section sized to match
// so a hidden button leaves no gap.
- (void)showCellBorders:(BOOL)shown {
  [_cellBordersButton setHidden:!shown];
  // The box grows and shrinks over the button, which is the topmost thing in
  // it; everything else stays where the XIB put it. Left to autoresizing, a
  // shrink moved the width field out of the box, and the next height worked
  // out from the moved frames came out short.
  [_cellBox setAutoresizesSubviews:NO];
  NSRect button = [_cellBordersButton frame];
  CGFloat gap = NSMinY(button) - NSMaxY([_cellWidthField frame]);
  NSRect box = [_cellBox frame];
  box.size.height = shown ? NSMaxY(button) + gap : NSMinY(button);
  [_cellBox setFrame:box];
}

- (void)editExpression:(id)sender {
  RDLExpressionField *field = [self expressionFieldForButton:sender];
  if (field == nil)
    return;
  NSString *edited = [RDLExpressionEditor runForSource:[field stringValue]
                                               context:field.expressionContext
                                                report:_context.report];
  if (edited == nil)
    return;  // cancelled: the field keeps what it had
  [field setStringValue:edited];
  // Through the same path as typing, so it is one edit and it undoes.
  [self changed:field];
}

#pragma mark - Font and rich text panels

// The font panel is the standard way to choose a family, a size and a weight,
// and it is one panel rather than three controls that have to agree. The
// inspector keeps its own font and size fields: a report often specifies a
// face by name that is not installed here, and typing it has to stay possible.
// The font panel's action arrives through the responder chain, so this view
// has to be able to hold first responder.
- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)openFontPanel:(id)sender {
  RDLItem *item = [_context selectedItem];
  if (item == nil)
    return;
  NSFontManager *manager = [NSFontManager sharedFontManager];
  NSDictionary *attrs = [RDLTextAttributes attributesForStyle:item.style
                                              paragraphAlign:RDLTextAlignUnspecified
                                                       scale:1.0];
  NSFont *font = attrs[NSFontAttributeName];
  if (font)
    [manager setSelectedFont:font isMultiple:NO];
  [manager setAction:@selector(changeFont:)];
  // Not -setTarget:. That is a macOS convenience; the documented behaviour, and
  // GNUstep's, is that the font manager sends its action to nil -- down the
  // responder chain. So the inspector has to be IN that chain rather than name
  // itself as a target, which also ends any field edit in progress, committing
  // it before the font changes underneath it.
  [[self window] makeFirstResponder:self];
  [[manager fontPanel:YES] orderFront:sender];
}

// Family, size, weight and slant arrive together and are written together, as
// one undo step: undoing a font choice one property at a time would leave the
// style in a state the user never chose.
- (void)changeFont:(id)sender {
  RDLItem *item = [_context selectedItem];
  if (item == nil)
    return;
  NSDictionary *attrs = [RDLTextAttributes attributesForStyle:item.style
                                              paragraphAlign:RDLTextAlignUnspecified
                                                       scale:1.0];
  NSFont *current = attrs[NSFontAttributeName];
  NSFont *chosen = current ? [sender convertFont:current] : [sender selectedFont];
  if (chosen == nil)
    return;

  NSFontManager *manager = [NSFontManager sharedFontManager];
  NSFontTraitMask traits = [manager traitsOfFont:chosen];
  RDLEditor *editor = _context.editor;
  [editor beginGroup:@"Font"];
  [editor setValue:[chosen familyName] forKeyPath:@"style.fontFamily" ofItem:item];
  [editor setValue:[RDLLength points:[chosen pointSize]]
        forKeyPath:@"style.fontSize"
            ofItem:item];
  [editor setValue:@((traits & NSBoldFontMask) ? RDLFontWeightBold : RDLFontWeightNormal)
        forKeyPath:@"style.fontWeight"
            ofItem:item];
  [editor setValue:@((traits & NSItalicFontMask) ? RDLFontStyleItalic : RDLFontStyleNormal)
        forKeyPath:@"style.fontStyle"
            ofItem:item];
  [editor endGroup];
  [self reload];
}

// The value field holds one line; a textbox that carries paragraphs and runs
// needs the rich-text editor, which is a panel rather than a field.
- (void)editRichText:(id)sender {
  RDL_UNUSED(sender);
  RDLItem *item = [_context selectedItem];
  if (![item isKindOfClass:[RDLTextbox class]])
    return;
  if ([RDLRichTextEditor runForTextbox:(RDLTextbox *)item context:_context])
    [self reload];
}

@end
