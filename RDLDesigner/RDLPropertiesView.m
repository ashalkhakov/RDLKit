/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <objc/runtime.h>
#import "RDLPropertiesView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLInspectorFields.h"
#import "RDLPane.h"
#import "RDLSelection.h"

// What the grid can do with a property, worked out from its type. Anything it
// cannot write it still shows: a list of filters reads as "3 items", which
// says more than a blank row.
typedef NS_ENUM(NSInteger, RDLPropertyKind) {
  RDLPropertyKindShownOnly = 0,
  RDLPropertyKindText,
  RDLPropertyKindNumber,
  RDLPropertyKindInteger,
  RDLPropertyKindBool,
  RDLPropertyKindLength,
  RDLPropertyKindValue
};

@interface RDLPropertyRow : NSObject
@property (nonatomic, copy) NSString *keyPath;
// "Left", "Style: font family" -- what the row is called in the grid.
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) RDLPropertyKind kind;
@end

@implementation RDLPropertyRow
@end

// The kind a property's type encoding names. The encodings are the runtime's:
// "T@\"NSString\"", "Td", "TB" and so on.
static RDLPropertyKind RDLKindOfAttributes(const char *attributes) {
  if (attributes == NULL)
    return RDLPropertyKindShownOnly;
  NSString *all = [NSString stringWithUTF8String:attributes];
  NSString *type = [[all componentsSeparatedByString:@","] firstObject] ?: @"";
  if ([type hasPrefix:@"T"])
    type = [type substringFromIndex:1];
  if ([type isEqualToString:@"d"] || [type isEqualToString:@"f"])
    return RDLPropertyKindNumber;
  if ([type isEqualToString:@"i"] || [type isEqualToString:@"q"] || [type isEqualToString:@"l"] ||
      [type isEqualToString:@"I"] || [type isEqualToString:@"Q"] || [type isEqualToString:@"L"])
    return RDLPropertyKindInteger;
  if ([type isEqualToString:@"B"] || [type isEqualToString:@"c"])
    return RDLPropertyKindBool;
  if ([type isEqualToString:@"@\"NSString\""])
    return RDLPropertyKindText;
  if ([type isEqualToString:@"@\"RDLLength\""])
    return RDLPropertyKindLength;
  if ([type isEqualToString:@"@\"RDLValue\""])
    return RDLPropertyKindValue;
  return RDLPropertyKindShownOnly;
}

// A property name as a heading: "fontFamily" reads "Font family".
static NSString *RDLHeadingOfName(NSString *name) {
  NSString *words = RDLWordsOfName(name);
  if ([words length] == 0)
    return name;
  return [[[words substringToIndex:1] uppercaseString] stringByAppendingString:[words substringFromIndex:1]];
}

// Every property `class` declares, itself and its superclasses up to `stop`,
// each class's own in the order they are declared -- which is the order the
// header puts them in, and so the order someone reading the model expects.
static void RDLCollectProperties(Class cls, Class stop, NSString *prefix, NSString *labelPrefix,
                                 NSMutableArray<RDLPropertyRow *> *into) {
  if (cls == Nil || cls == stop)
    return;
  RDLCollectProperties(class_getSuperclass(cls), stop, prefix, labelPrefix, into);
  unsigned int count = 0;
  objc_property_t *properties = class_copyPropertyList(cls, &count);
  for (unsigned int i = 0; i < count; i++) {
    NSString *name = [NSString stringWithUTF8String:property_getName(properties[i])];
    RDLPropertyRow *row = [[RDLPropertyRow alloc] init];
    row.keyPath = [prefix length] ? [NSString stringWithFormat:@"%@.%@", prefix, name] : name;
    row.label = [labelPrefix length] ? [NSString stringWithFormat:@"%@: %@", labelPrefix, RDLWordsOfName(name)]
                                     : RDLHeadingOfName(name);
    row.kind = RDLKindOfAttributes(property_getAttributes(properties[i]));
    // A read-only property is one the model works out, so it is shown and not
    // typed into.
    if (strstr(property_getAttributes(properties[i]), ",R") != NULL)
      row.kind = RDLPropertyKindShownOnly;
    [into addObject:row];
  }
  free(properties);
}

@interface RDLPropertiesView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *headingLabel;
@end

@implementation RDLPropertiesView {
  NSArray<RDLPropertyRow *> *_rows;
  // What the rows were built for, so they are built again only when the
  // selection moves to something else.
  RDLItem *_item;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  if (!RDLLoadPaneNib(self, @"RDLPropertiesView"))
    return nil;
  RDLFillHost(self, _content);
  _rows = @[];
  self.context = context;
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setContext:(RDLEditingContext *)context {
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  if (context != nil) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:RDLDocumentDidChangeNotification
                                               object:context.document];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:RDLSelectionDidChangeNotification
                                               object:context.selection];
  }
  [self reload];
}

#pragma mark - The rows

- (RDLItem *)selectedItem {
  return [_context selectedItem];
}

- (void)reload {
  RDLItem *item = [self selectedItem];
  if (item != _item) {
    _item = item;
    _rows = [self rowsForItem:item];
  }
  [_headingLabel setStringValue:item ? [NSString stringWithFormat:@"%@ (%@)", item.name ?: @"",
                                                                 NSStringFromClass([item class])]
                                     : @"Nothing is selected."];
  [_table reloadData];
}

// The element's own properties, then its style's. Down to RDLItem's, which is
// where a report item's properties start; NSObject's are the runtime's, not
// the report's.
- (NSArray<RDLPropertyRow *> *)rowsForItem:(RDLItem *)item {
  if (item == nil)
    return @[];
  NSMutableArray<RDLPropertyRow *> *rows = [NSMutableArray array];
  RDLCollectProperties([item class], [NSObject class], nil, nil, rows);
  if ([item respondsToSelector:@selector(style)])
    RDLCollectProperties([RDLStyle class], [NSObject class], @"style", @"Style", rows);
  return rows;
}

- (NSArray<NSString *> *)keyPaths {
  return [_rows valueForKey:@"keyPath"];
}

- (RDLPropertyRow *)rowForKeyPath:(NSString *)keyPath {
  for (RDLPropertyRow *row in _rows)
    if ([row.keyPath isEqualToString:keyPath])
      return row;
  return nil;
}

#pragma mark - Values as text

static NSString *RDLTextOfValue(id value, RDLPropertyKind kind) {
  if (value == nil)
    return @"";
  switch (kind) {
    case RDLPropertyKindNumber:
      return [NSString stringWithFormat:@"%.4g", [value doubleValue]];
    case RDLPropertyKindInteger:
      return [NSString stringWithFormat:@"%ld", (long)[value integerValue]];
    case RDLPropertyKindBool:
      return [value boolValue] ? @"Yes" : @"No";
    case RDLPropertyKindLength:
      return [(RDLLength *)value stringValue] ?: @"";
    case RDLPropertyKindValue:
      return [(RDLValue *)value source] ?: @"";
    case RDLPropertyKindText:
      return [value description] ?: @"";
    case RDLPropertyKindShownOnly:
      break;
  }
  // Something with contents rather than a value: how much of it there is says
  // more than its address does.
  if ([value respondsToSelector:@selector(count)])
    return [NSString stringWithFormat:@"%lu item%@", (unsigned long)[value count],
                                      [value count] == 1 ? @"" : @"s"];
  return [value description] ?: @"";
}

- (NSString *)textForKeyPath:(NSString *)keyPath {
  RDLPropertyRow *row = [self rowForKeyPath:keyPath];
  if (row == nil || _item == nil)
    return nil;
  return RDLTextOfValue([self valueAtKeyPath:row.keyPath], row.kind);
}

// Reading a key path a nil style would make meaningless: the model makes a
// style on demand, so asking is safe, but an element that has none reads empty
// rather than throwing.
- (id)valueAtKeyPath:(NSString *)keyPath {
  @try {
    return [_item valueForKeyPath:keyPath];
  } @catch (NSException *e) {
    RDL_UNUSED(e);
    return nil;
  }
}

// Text back into the model's own type. nil for text that is not a value of
// that type at all, which leaves the property alone.
static id RDLValueOfText(NSString *text, RDLPropertyKind kind) {
  NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  switch (kind) {
    case RDLPropertyKindText:
      // Empty clears the property rather than storing "", which is what the
      // inspector's text fields do and what the writer then leaves out.
      return [trimmed length] ? trimmed : nil;
    case RDLPropertyKindNumber:
      return @([trimmed doubleValue]);
    case RDLPropertyKindInteger:
      return @([trimmed integerValue]);
    case RDLPropertyKindBool:
      return @([trimmed caseInsensitiveCompare:@"yes"] == NSOrderedSame ||
               [trimmed caseInsensitiveCompare:@"true"] == NSOrderedSame ||
               [trimmed isEqualToString:@"1"]);
    case RDLPropertyKindLength:
      return [trimmed length] ? [RDLLength lengthFromString:trimmed] : nil;
    case RDLPropertyKindValue:
      return [trimmed length] ? [RDLValue valueWithSource:trimmed] : nil;
    case RDLPropertyKindShownOnly:
      return nil;
  }
  return nil;
}

- (BOOL)setText:(NSString *)text forKeyPath:(NSString *)keyPath {
  RDLPropertyRow *row = [self rowForKeyPath:keyPath];
  if (row == nil || _item == nil || row.kind == RDLPropertyKindShownOnly)
    return NO;
  // The name is the one property with a rule of its own -- everything that
  // names the element follows it -- so it goes through the editor's rename.
  if ([row.keyPath isEqualToString:@"name"])
    return [_context.editor renameItem:_item to:[text stringByTrimmingCharactersInSet:
                                                          [NSCharacterSet whitespaceCharacterSet]]];
  [_context.editor setValue:RDLValueOfText(text, row.kind) forKeyPath:row.keyPath ofItem:_item];
  return YES;
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  RDL_UNUSED(tableView);
  return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  RDL_UNUSED(tableView);
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  RDLPropertyRow *r = _rows[(NSUInteger)row];
  if ([[column identifier] isEqualToString:@"property"])
    return r.label;
  return RDLTextOfValue([self valueAtKeyPath:r.keyPath], r.kind);
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  RDL_UNUSED(tableView);
  if (row < 0 || row >= (NSInteger)[_rows count] || ![[column identifier] isEqualToString:@"value"])
    return;
  [self setText:[value description] forKeyPath:_rows[(NSUInteger)row].keyPath];
}

// Only the value column, and only a property the grid can write.
- (BOOL)tableView:(NSTableView *)tableView
    shouldEditTableColumn:(NSTableColumn *)column
                      row:(NSInteger)row {
  RDL_UNUSED(tableView);
  if (row < 0 || row >= (NSInteger)[_rows count])
    return NO;
  return [[column identifier] isEqualToString:@"value"] &&
         _rows[(NSUInteger)row].kind != RDLPropertyKindShownOnly;
}

@end
