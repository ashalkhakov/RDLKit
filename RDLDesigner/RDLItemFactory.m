#import "RDLItemFactory.h"
#import "RDLKit.h"
#import "RDLSelection.h"
#import "RDLEditor.h"

// Depth-first search for `target`, reporting the Rectangle that holds it.
static RDLItem *RDLFindInItems(NSArray *items, RDLItem *target, RDLItem *parent,
                               RDLItem **outParent) {
  for (RDLItem *it in items) {
    if (it == target) {
      if (outParent)
        *outParent = parent;
      return it;
    }
    if ([it.childItems count]) {
      RDLItem *found = RDLFindInItems(it.childItems, target, it, outParent);
      if (found)
        return found;
    }
  }
  return nil;
}

// The point is immutable to its consumers; the factory is what fills it in.
@interface RDLInsertionPoint ()
@property (nonatomic, strong) RDLTablixCell *cell;
@property (nonatomic, strong) RDLTablix *cellTablix;
@property (nonatomic, assign) NSInteger cornerRow;
@property (nonatomic, assign) NSInteger cornerColumn;
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *container;
@property (nonatomic, strong) RDLItem *sibling;
@property (nonatomic, strong) NSMutableArray *items;
@end

@implementation RDLInsertionPoint
- (instancetype)init {
  if ((self = [super init])) {
    _cornerRow = -1;
    _cornerColumn = -1;
  }
  return self;
}

- (NSString *)localizedDescription {
  if (_cell != nil || _cornerRow >= 0)
    return [NSString stringWithFormat:@"into a cell of %@", _cellTablix.name ?: @"the table"];
  if (_container)
    return [NSString stringWithFormat:@"inside %@", _container.name ?: @"the rectangle"];
  if (_sibling)
    return [NSString stringWithFormat:@"after %@ in %@", _sibling.name ?: @"the selection",
                                      [RDLItemFactory titleForBandKey:_bandKey]];
  return [NSString stringWithFormat:@"into %@", [RDLItemFactory titleForBandKey:_bandKey]];
}
@end

@implementation RDLItemFactory

+ (NSString *)titleForBandKey:(NSString *)bandKey {
  if ([bandKey isEqualToString:@"pageHeader"])
    return @"Page Header";
  if ([bandKey isEqualToString:@"pageFooter"])
    return @"Page Footer";
  return @"Body";
}

#pragma mark - Location

+ (RDLInsertionPoint *)insertionPointInReport:(RDLReport *)report
                                    selection:(RDLSelection *)selection {
  RDLInsertionPoint *p = [[RDLInsertionPoint alloc] init];
  NSString *key = [selection.bandKey length] ? selection.bandKey : @"body";

  // An empty cell of a tablix: the new element becomes its contents.
  if (selection.scope == RDLSelectionScopeTablixCell && selection.tablix != nil &&
      selection.cellRow >= 0 && selection.cellColumn >= 0) {
    // The selection holds where in the grid the person clicked; the body cell
    // is that, less the row-header columns a grouped tablix draws first.
    // Over the row headers, it is the corner's.
    NSUInteger gridRow = (NSUInteger)selection.cellRow, gridColumn = (NSUInteger)selection.cellColumn;
    NSUInteger cornerRow = 0;
    BOOL corner = [RDLTablixGeometry tablix:selection.tablix
                              isCornerAtRow:gridRow
                                     column:gridColumn
                                  cornerRow:&cornerRow];
    RDLTablixCell *cell = corner ? [RDLTablixGeometry cornerCellOf:selection.tablix inRow:gridRow column:gridColumn]
                                 : [RDLTablixGeometry cellOf:selection.tablix inRow:gridRow column:gridColumn];
    if (cell != nil || corner) {
      p.bandKey = key;
      p.cell = cell;
      p.cellTablix = selection.tablix;
      if (cell == nil) {
        p.cornerRow = (NSInteger)cornerRow;
        p.cornerColumn = (NSInteger)gridColumn;
      }
      p.items = [report bandWithKey:key].items;  // never nil; unused for a cell
      return p;
    }
  }

  // An item that is itself the contents of a cell: what goes in beside it goes
  // in the same cell, which means the cell becomes a Rectangle holding both.
  if (selection.scope == RDLSelectionScopeItem && selection.item != nil) {
    RDLTablix *tablix = nil;
    RDLTablixCell *cell = [report cellContainingItem:selection.item tablix:&tablix];
    if (cell != nil) {
      p.bandKey = key;
      p.cell = cell;
      p.cellTablix = tablix;
      p.items = [report bandWithKey:key].items;
      return p;
    }
  }

  if (selection.scope == RDLSelectionScopeItem && selection.item != nil) {
    RDLItem *parent = nil;
    NSString *foundKey = nil;
    for (NSString *k in [RDLReport bandKeys]) {
      RDLItem *hit = RDLFindInItems([report bandWithKey:k].items, selection.item, nil, &parent);
      if (hit) {
        foundKey = k;
        break;
      }
    }
    if (foundKey) {
      p.bandKey = foundKey;
      // Selecting a Rectangle means "put it inside"; anything else means
      // "put it after me, alongside".
      if ([selection.item isKindOfClass:[RDLRectangle class]]) {
        p.container = selection.item;
        p.items = [(RDLRectangle *)selection.item items];
      } else {
        p.sibling = selection.item;
        p.container = parent;
        p.items = parent ? [(RDLRectangle *)parent items]
                         : [report bandWithKey:foundKey].items;
      }
      return p;
    }
  }

  // Nothing useful selected: the body is the default home for new elements.
  if (selection.scope == RDLSelectionScopeReport)
    key = @"body";
  p.bandKey = key;
  p.items = [report bandWithKey:key].items;
  return p;
}

#pragma mark - Policy

NSString *RDLTitleOfItemKind(RDLItemKind kind) {
  switch (kind) {
  case RDLItemKindTextbox:
    return @"Textbox";
  case RDLItemKindLine:
    return @"Line";
  case RDLItemKindRectangle:
    return @"Rectangle";
  case RDLItemKindImage:
    return @"Image";
  case RDLItemKindTablix:
    return @"Tablix";
  case RDLItemKindList:
    return @"List";
  case RDLItemKindChart:
    return @"Chart";
  case RDLItemKindSubreport:
    return @"Subreport";
  case RDLItemKindUnspecified:
    break;
  }
  return nil;
}

+ (NSArray<NSNumber *> *)elementKindsAllowedAt:(RDLInsertionPoint *)point {
  // Everything goes everywhere: MS-RDL allows a data region in a Rectangle
  // and in a tablix cell as much as a subreport, and the engine lays a region
  // out wherever it is -- a table per group, a chart per row.
  (void)point;
  return @[ @(RDLItemKindTextbox), @(RDLItemKindLine), @(RDLItemKindRectangle), @(RDLItemKindImage),
            @(RDLItemKindTablix), @(RDLItemKindList), @(RDLItemKindChart), @(RDLItemKindSubreport) ];
}

+ (BOOL)kind:(RDLItemKind)kind isAllowedAt:(RDLInsertionPoint *)point {
  return [[self elementKindsAllowedAt:point] containsObject:@(kind)];
}

#pragma mark - Naming

// Every name in use, including those of items in tablix cells, corners and
// group headers, which -childItems does not list: a name taken there is taken.
static NSMutableSet *RDLUsedNames(RDLReport *report) {
  NSMutableSet *used = [NSMutableSet set];
  for (RDLItem *it in [report allItemsIncludingNested])
    if (it.name)
      [used addObject:it.name];
  return used;
}

+ (NSString *)whyName:(NSString *)name
     isRefusedInReport:(RDLReport *)report
               besides:(RDLItem *)item {
  if ([name length] == 0)
    return @"Every element needs a name.";
  if (![[NSCharacterSet letterCharacterSet] characterIsMember:[name characterAtIndex:0]])
    return @"A name starts with a letter.";
  if (![self isValidName:name])
    return @"A name holds letters, digits and underscores only — no spaces.";
  if ([self name:name isTakenInReport:report besides:item])
    return [NSString stringWithFormat:@"Something else in this report is already called %@.", name];
  return nil;
}

+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix inReport:(RDLReport *)report {
  return [self uniqueNameWithPrefix:prefix inReport:report besides:nil];
}

+ (BOOL)isValidName:(NSString *)name {
  if ([name length] == 0 || ![[NSCharacterSet letterCharacterSet] characterIsMember:[name characterAtIndex:0]])
    return NO;
  NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
  [allowed addCharactersInString:@"_"];
  return [name rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

+ (BOOL)name:(NSString *)name isTakenInReport:(RDLReport *)report besides:(RDLItem *)item {
  for (RDLItem *it in [report allItemsIncludingNested])
    if (it != item && [it.name isEqualToString:name])
      return YES;
  return NO;
}

+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix
                          inReport:(RDLReport *)report
                           besides:(RDLItem *)item {
  NSMutableSet *used = RDLUsedNames(report);
  for (RDLItem *it in [item itemsIncludingNested])
    if (it.name)
      [used addObject:it.name];
  NSString *base = [prefix length] ? prefix : @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", base, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", base, (long)i];
}

+ (void)renameTreeUniquely:(RDLItem *)item inReport:(RDLReport *)report {
  NSMutableSet *used = RDLUsedNames(report);
  [self renameTree:item usedNames:used];
}

+ (void)renameTree:(RDLItem *)item usedNames:(NSMutableSet *)used {
  if (item == nil)
    return;
  NSString *prefix = item.rdlElementName ?: @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  item.name = [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
  [used addObject:item.name];
  for (RDLItem *child in item.childItems)
    [self renameTree:child usedNames:used];
}

#pragma mark - Defaults

+ (RDLItem *)itemOfKind:(RDLItemKind)kind
                 atPoint:(RDLInsertionPoint *)point
                inReport:(RDLReport *)report {
  RDLItem *it = [self newItemOfKind:kind];
  if (it == nil)
    return nil;
  it.name = [self uniqueNameWithPrefix:RDLTitleOfItemKind(kind) inReport:report];
  [self applyDefaultsTo:it report:report];
  if (kind == RDLItemKindList)
    [self makeList:(RDLTablix *)it report:report];

  // Position: follow the selection, tuck into a container, else inset on the page.
  if (point.sibling) {
    it.left = point.sibling.left;
    it.top = [RDLEditor snap:point.sibling.top + point.sibling.height + 0.1];
  } else if (point.container) {
    it.left = 0.1;
    it.top = 0.1;
  } else {
    it.left = 0.25;
    it.top = 0.25;
  }
  return it;
}

// The class each kind is made of; a List is a Tablix.
+ (RDLItem *)newItemOfKind:(RDLItemKind)kind {
  switch (kind) {
  case RDLItemKindTextbox:
    return [[RDLTextbox alloc] init];
  case RDLItemKindLine:
    return [[RDLLine alloc] init];
  case RDLItemKindRectangle:
    return [[RDLRectangle alloc] init];
  case RDLItemKindImage:
    return [[RDLImage alloc] init];
  case RDLItemKindTablix:
  case RDLItemKindList:
    return [[RDLTablix alloc] init];
  case RDLItemKindChart:
    return [[RDLChart alloc] init];
  case RDLItemKindSubreport:
    return [[RDLSubreport alloc] init];
  case RDLItemKindUnspecified:
    break;
  }
  return nil;
}

// A list, as Report Builder makes one: a single column and a single row, the
// row a details group repeated for each row of the dataset, its cell holding a
// rectangle to lay out in freely.
+ (void)makeList:(RDLTablix *)list report:(RDLReport *)report {
  static const CGFloat kListWidth = 3.0, kListHeight = 1.0;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixColumn *column = [[RDLTablixColumn alloc] init];
  column.width = kListWidth;
  body.columns = [@[ column ] mutableCopy];
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = kListHeight;
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  RDLRectangle *content = [[RDLRectangle alloc] init];
  content.name = [self uniqueNameWithPrefix:@"Rectangle" inReport:report besides:list];
  content.width = kListWidth;
  content.height = kListHeight;
  cell.item = content;
  row.cells = [@[ cell ] mutableCopy];
  body.rows = [@[ row ] mutableCopy];
  list.tablixBody = body;
  RDLTablixMember *details = [[RDLTablixMember alloc] init];
  details.groupName = [NSString stringWithFormat:@"%@_Details", list.name ?: @"List"];
  list.rowHierarchy = [[RDLTablixHierarchy alloc] init];
  list.rowHierarchy.members = [@[ details ] mutableCopy];
  list.columnHierarchy = [[RDLTablixHierarchy alloc] init];
  list.columnHierarchy.members = [@[ [[RDLTablixMember alloc] init] ] mutableCopy];
  list.cornerRows = [NSMutableArray array];
  list.width = kListWidth;
  list.height = kListHeight;
}

+ (void)applyDefaultsTo:(RDLItem *)it report:(RDLReport *)report {
  it.width = 2.0;
  it.height = 0.32;
  if ([it isKindOfClass:[RDLTextbox class]]) {
    [(RDLTextbox *)it setValue:@"Text"];
    it.style.fontSize = [RDLLength points:11];
  } else if ([it isKindOfClass:[RDLLine class]]) {
    // Flat. A line runs from one corner of its box to the other, so any height
    // at all is a slope -- and a line inserted from the menu is meant to be a
    // rule across the page, not a diagonal.
    it.height = 0.0;
    it.width = 3.0;
  } else if ([it isKindOfClass:[RDLRectangle class]]) {
    it.width = 2.4;
    it.height = 1.0;
    it.style.backgroundColor = @"#ece6d8";
  } else if ([it isKindOfClass:[RDLImage class]]) {
    it.width = 1.2;
    it.height = 1.2;
  } else if ([it isKindOfClass:[RDLSubreport class]]) {
    // Big enough to see, and empty: which report it shows is the one thing
    // nobody can guess, so it is asked for in the inspector rather than
    // pointed at a file that happens to be next door.
    it.width = 3.0;
    it.height = 1.0;
  } else if ([it isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)it;
    it.width = 5.0;
    it.height = 2.2;
    chart.chartType = RDLChartTypeColumn;
    chart.title = @"Chart";
    // Bind something plausible so a new chart draws instead of sitting empty.
    RDLDataSet *ds = [report.dataSets firstObject];
    if (ds) {
      chart.dataSetName = ds.name;
      if ([ds.fields count] > 0)
        chart.categoryField = [self fieldNameAtIndex:0 ofDataSet:ds];
      if ([ds.fields count] > 1)
        chart.valueField = [self fieldNameAtIndex:1 ofDataSet:ds];
    }
  } else if ([it isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tablix = (RDLTablix *)it;
    tablix.headerHeight = 0.3;
    tablix.rowHeight = 0.28;
    RDLDataSet *ds = [report.dataSets firstObject];
    tablix.dataSetName = ds.name ?: @"";
    NSMutableArray *specs = [NSMutableArray array];
    NSArray *fields = [ds.fields count] ? ds.fields : @[ @"Field" ];
    for (NSUInteger i = 0; i < [fields count]; i++) {
      NSString *f = [self fieldNameAtIndex:i ofDataSet:ds] ?: @"Field";
      [specs addObject:@{
        @"width" : @1.6,
        @"header" : f,
        @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", f]
      }];
    }
    tablix.columnSpecs = specs;
    [tablix rebuildTablix];
    it.width = 1.6 * [specs count];
    it.height = 0.6;
  }
}

+ (NSString *)fieldNameAtIndex:(NSUInteger)index ofDataSet:(RDLDataSet *)ds {
  NSArray<NSString *> *names = [ds fieldNames];
  return index < [names count] ? names[index] : nil;
}

@end
