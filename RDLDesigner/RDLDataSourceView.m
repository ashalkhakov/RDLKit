/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataSourceView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"

// Where the document is. Not an RDL vocabulary -- RDL says it by which key the
// connect string uses -- but it is the question a person is answering, so the
// pane asks it that way and writes the right key.
typedef NS_ENUM(NSInteger, RDLDocumentLocation) {
  RDLDocumentLocationFile = 0,
  RDLDocumentLocationEmbedded,
};

@interface RDLDataSourceView () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePop, *wherePop, *delimiterPop;
@property (nonatomic, strong) IBOutlet NSTextField *documentLabel, *documentField, *widthsField;
@property (nonatomic, strong) IBOutlet NSButton *headerCheck;
@property (nonatomic, strong) IBOutlet NSScrollView *contentScroll;
@property (nonatomic, strong) IBOutlet NSTextView *contentView;
@property (nonatomic, strong) IBOutlet NSTextField *summaryLabel;
@property (nonatomic, strong) IBOutlet NSTextField *empty;
@end

@implementation RDLDataSourceView {
  RDLEditingContext *_context;
  BOOL _filling;
}

// The delimiters worth offering, and what each one writes. Named rather than
// typed: nobody can put a tab into a properties line.
+ (NSArray<NSString *> *)delimiterNames {
  return @[ @"Comma", @"Tab", @"Semicolon", @"Pipe", @"Space" ];
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLDataSourceView"))
    return nil;
  RDLFillHost(self, _content);
  for (RDLDataProviderKind kind = RDLDataProviderKindJSON; kind <= RDLDataProviderKindCSV; kind++)
    [_typePop addItemWithTitle:RDLStringFromDataProviderKind(kind)];
  [_wherePop addItemWithTitle:@"A file beside the report"];
  [_wherePop addItemWithTitle:@"Carried in the report"];
  for (NSString *name in [[self class] delimiterNames])
    [_delimiterPop addItemWithTitle:name];
  [_contentView setFont:[NSFont userFixedPitchFontOfSize:11]];
  [self reload];
  return self;
}

- (void)setDataSource:(RDLDataSource *)dataSource {
  _dataSource = dataSource;
  [self reload];
}

- (RDLDataProviderKind)chosenKind {
  NSInteger index = [_typePop indexOfSelectedItem];
  return index < 0 ? RDLDataProviderKindJSON
                   : (RDLDataProviderKind)(RDLDataProviderKindJSON + index);
}

- (RDLDocumentLocation)chosenLocation {
  return [_wherePop indexOfSelectedItem] == 1 ? RDLDocumentLocationEmbedded
                                              : RDLDocumentLocationFile;
}

#pragma mark - Model -> pane

- (void)reload {
  _filling = YES;
  BOOL any = _dataSource != nil;
  NSDictionary *properties = RDLConnectionProperties(_dataSource.connectString);
  RDLDataProviderKind kind = RDLDataProviderKindFromString(_dataSource.dataProvider);
  if (kind == RDLDataProviderKindUnspecified)
    kind = RDLDataProviderKindJSON;

  [_nameField setStringValue:_dataSource.name ?: @""];
  [_typePop selectItemAtIndex:kind - RDLDataProviderKindJSON];

  NSString *inlineText = properties[RDLInlineKeyForProviderKind(kind)];
  BOOL embedded = [inlineText length] > 0;
  [_wherePop selectItemAtIndex:embedded ? 1 : 0];
  [_documentField setStringValue:properties[RDLDocumentKeyForProviderKind(kind)] ?: @""];
  [_contentView setString:inlineText ?: @""];

  NSString *headers = properties[@"hasheaders"] ?: properties[@"headers"];
  [_headerCheck setState:(headers == nil || [headers boolValue]) ? NSOnState : NSOffState];
  NSString *delimiter = properties[@"delimiter"] ?: @"Comma";
  if ([_delimiterPop itemWithTitle:[delimiter capitalizedString]])
    [_delimiterPop selectItemWithTitle:[delimiter capitalizedString]];
  else
    [_delimiterPop selectItemAtIndex:0];
  [_widthsField setStringValue:properties[@"widths"] ?: @""];

  [self syncVisibility];
  _filling = NO;
}

// What a kind of document needs asking about: delimited text has a header row
// and a separator, and the other two do not. Showing the questions that do not
// apply is how a pane ends up looking like a connect string again.
- (void)syncVisibility {
  BOOL any = _dataSource != nil;
  BOOL csv = [self chosenKind] == RDLDataProviderKindCSV;
  BOOL embedded = [self chosenLocation] == RDLDocumentLocationEmbedded;
  for (NSView *v in @[ _nameField, _typePop, _wherePop, _documentLabel ])
    [v setHidden:!any];
  for (NSView *v in @[ _headerCheck, _delimiterPop, _widthsField ])
    [v setHidden:!any || !csv];
  [_documentField setHidden:!any || embedded];
  [_contentScroll setHidden:!any || !embedded];
  [_empty setHidden:any];
  [_documentLabel setStringValue:embedded ? @"Content" : @"File"];
  [_summaryLabel setStringValue:any ? [NSString stringWithFormat:@"Connect string: %@",
                                                                 _dataSource.connectString ?: @""]
                                    : @""];
}

#pragma mark - Pane -> model

// Every control writes the whole source, because the connect string is one
// line: which key names the document depends on the kind, and the options
// depend on it too.
- (void)changed:(id)sender {
  (void)sender;
  if (_filling || _dataSource == nil)
    return;
  RDLDataProviderKind kind = [self chosenKind];
  NSMutableDictionary *properties = [NSMutableDictionary dictionary];
  if ([self chosenLocation] == RDLDocumentLocationEmbedded) {
    NSString *text = [_contentView string] ?: @"";
    if ([text length])
      properties[RDLInlineKeyForProviderKind(kind)] = text;
  } else {
    NSString *file = [_documentField stringValue];
    if ([file length])
      properties[RDLDocumentKeyForProviderKind(kind)] = file;
  }
  if (kind == RDLDataProviderKindCSV) {
    // Written both ways round, because "the default" is a header row and a
    // report that says nothing gets one.
    properties[@"hasheaders"] = [_headerCheck state] == NSOnState ? @"true" : @"false";
    NSString *delimiter = [_delimiterPop titleOfSelectedItem];
    if ([delimiter length] && ![delimiter isEqualToString:@"Comma"])
      properties[@"delimiter"] = delimiter;
    NSString *widths = [_widthsField stringValue];
    if ([widths length])
      properties[@"widths"] = widths;
  }
  [_context.editor setProvider:RDLStringFromDataProviderKind(kind)
                 connectString:RDLConnectionString(properties)
                  ofDataSource:_dataSource];
  [self syncVisibility];
}

// Renaming a source carries the datasets that read from it; the editor does
// that, because a rename that left them pointing at nothing would empty the
// report the next time it was bound.
- (void)rename:(id)sender {
  (void)sender;
  if (_filling || _dataSource == nil)
    return;
  NSString *name = [[_nameField stringValue]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([name length] == 0 || [name isEqualToString:_dataSource.name]) {
    [self reload];
    return;
  }
  [_context.editor renameDataSource:_dataSource to:name];
  [self reload];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
  if ([note object] == _nameField)
    [self rename:_nameField];
  else
    [self changed:[note object]];
}

- (void)textDidEndEditing:(NSNotification *)note {
  (void)note;
  [self changed:_contentView];
}

@end
