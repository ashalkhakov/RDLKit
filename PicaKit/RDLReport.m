#import "RDLReport.h"

@implementation RDLBorder
+ (instancetype)none {
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = @"None";
  b.width = @"1pt";
  b.color = @"#1a1916";
  return b;
}
+ (instancetype)solidColor:(NSString *)color {
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = @"Solid";
  b.width = @"1pt";
  b.color = color ?: @"#1a1916";
  return b;
}
@end

@implementation RDLStyle
+ (instancetype)defaultStyle {
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = @"Georgia";
  s.fontSize = @"10pt";
  s.fontWeight = @"Normal";
  s.fontStyle = @"Normal";
  s.color = @"#1a1916";
  s.backgroundColor = @"Transparent";
  s.textAlign = @"Left";
  s.verticalAlign = @"Top";
  s.textDecoration = @"None";
  s.paddingLeft = @"4pt";
  s.paddingRight = @"4pt";
  s.paddingTop = @"2pt";
  s.paddingBottom = @"2pt";
  s.border = [RDLBorder none];
  s.borderLeft = [RDLBorder none];
  s.borderRight = [RDLBorder none];
  s.borderTop = [RDLBorder none];
  s.borderBottom = [RDLBorder none];
  return s;
}
@end

@implementation RDLTablixColumn
@end

@implementation RDLTablixCell
- (instancetype)init {
  self = [super init];
  if (self) {
    _colSpan = 1;
    _rowSpan = 1;
  }
  return self;
}
@end

@implementation RDLTablixRow
- (instancetype)init {
  self = [super init];
  if (self) {
    _cells = [NSMutableArray array];
    _height = 0.28;
  }
  return self;
}
@end

@implementation RDLTablixBody
- (instancetype)init {
  self = [super init];
  if (self) {
    _columns = [NSMutableArray array];
    _rows = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLTablixMember
- (instancetype)init {
  self = [super init];
  if (self) {
    _members = [NSMutableArray array];
    _groupExpressions = [NSMutableArray array];
    _sortExpressions = [NSMutableArray array];
    _filters = [NSMutableArray array];
    _keepWithGroup = @"None";
  }
  return self;
}
@end

@implementation RDLFilter
- (instancetype)init {
  self = [super init];
  if (self) {
    _values = [NSMutableArray array];
    _oper = @"Equal";
  }
  return self;
}
@end

@implementation RDLSortExpression
- (instancetype)init {
  self = [super init];
  if (self) {
    _direction = @"Ascending";
  }
  return self;
}
@end

@implementation RDLTablixHeader
@end


@implementation RDLTablixHierarchy
- (instancetype)init {
  self = [super init];
  if (self) {
    _members = [NSMutableArray array];
  }
  return self;
}
@end

// One column of the designer table, resolved once per build.
@interface PicaColSpec : NSObject
@property (nonatomic, copy) NSString *header, *value, *align, *aggregate, *field;
@property (nonatomic, assign) CGFloat width;
@end
@implementation PicaColSpec
@end

@implementation RDLItem {
  CGFloat _stashHeaderH;
  CGFloat _stashRowH;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _style = [RDLStyle defaultStyle];
    _type = @"Textbox";
    _canGrow = YES;
    _stashHeaderH = 0.3;
    _stashRowH = 0.28;
    _items = [NSMutableArray array];
    _filters = [NSMutableArray array];
    _sortExpressions = [NSMutableArray array];
    _cornerRows = [NSMutableArray array];
  }
  return self;
}

- (CGFloat)headerHeight {
  if ([_tablixBody.rows count])
    return _tablixBody.rows[0].height;
  return _stashHeaderH;
}

- (void)setHeaderHeight:(CGFloat)h {
  _stashHeaderH = h;
  if ([_tablixBody.rows count])
    _tablixBody.rows[0].height = h;
}

- (CGFloat)rowHeight {
  if ([_tablixBody.rows count] > 1)
    return _tablixBody.rows[1].height;
  return _stashRowH;
}

- (void)setRowHeight:(CGFloat)h {
  _stashRowH = h;
  if ([_tablixBody.rows count] > 1)
    _tablixBody.rows[1].height = h;
}

// "=Sum(Fields!Amount.Value)" → aggregate "Sum". Returns nil when the value
// is not a plain aggregate call.
static NSString *PicaAggregateOfValue(NSString *value) {
  if (![value hasPrefix:@"="])
    return nil;
  NSRange paren = [value rangeOfString:@"("];
  if (paren.location == NSNotFound || paren.location < 2)
    return nil;
  NSString *fn = [value substringWithRange:NSMakeRange(1, paren.location - 1)];
  static NSSet *known = nil;
  if (known == nil)
    known = [NSSet setWithArray:@[ @"Sum", @"Avg", @"Count", @"CountDistinct", @"Min", @"Max" ]];
  return [known containsObject:fn] ? fn : nil;
}

- (NSArray *)columns {
  if ([_tablixBody.columns count] == 0)
    return @[];
  RDLTablixRow *header = _tablixBody.rows.firstObject;
  RDLTablixRow *detail = [_tablixBody.rows count] > 1 ? _tablixBody.rows[1] : header;
  // Aggregate metadata lives in the subtotal / grand total rows, if present.
  RDLTablixRow *aggRow = [_tablixBody.rows count] > 2 ? _tablixBody.rows.lastObject : nil;
  NSMutableArray *cols = [NSMutableArray array];
  NSUInteger n = [_tablixBody.columns count];
  for (NSUInteger i = 0; i < n; i++) {
    CGFloat w = _tablixBody.columns[i].width;
    NSMutableDictionary *col = [NSMutableDictionary dictionary];
    col[@"width"] = @(w);
    col[@"header"] = @"";
    col[@"value"] = @"";
    if (i < [header.cells count] && header.cells[i].item.value)
      col[@"header"] = header.cells[i].item.value;
    if (detail && i < [detail.cells count]) {
      RDLItem *dItem = detail.cells[i].item;
      if (dItem.value)
        col[@"value"] = dItem.value;
      if ([dItem.style.textAlign length])
        col[@"align"] = dItem.style.textAlign;
    }
    if (aggRow && i < [aggRow.cells count]) {
      NSString *agg = PicaAggregateOfValue(aggRow.cells[i].item.value ?: @"");
      if (agg)
        col[@"aggregate"] = agg;
    }
    [cols addObject:col];
  }
  return cols;
}

- (void)setColumns:(NSArray *)cols {
  _type = @"Tablix";
  [self picaBuildTable:cols headerHeight:_stashHeaderH rowHeight:_stashRowH];
}

- (void)rebuildTableFromColumns {
  [self picaBuildTable:self.columns headerHeight:self.headerHeight rowHeight:self.rowHeight];
}

- (RDLTablixRow *)picaAggregateRow:(NSArray<PicaColSpec *> *)specs
                             label:(NSString *)label
                            prefix:(NSString *)prefix
                            height:(CGFloat)h
                      fallbackField:(NSString *)fallbackField {
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = h;
  NSInteger n = (NSInteger)[specs count];
  BOOL anyExplicit = NO;
  for (PicaColSpec *s in specs)
    if ([s.aggregate length] && [s.field length])
      anyExplicit = YES;
  for (NSInteger i = 0; i < n; i++) {
    PicaColSpec *s = specs[(NSUInteger)i];
    RDLItem *t = [[RDLItem alloc] init];
    t.type = @"Textbox";
    t.name = [NSString stringWithFormat:@"%@%@%ld", self.name ?: @"T", prefix, (long)i];
    t.style.fontWeight = @"Bold";
    t.style.borderTop = [RDLBorder solidColor:@"#1a1916"];
    t.style.borderTop.width = @"0.5pt";
    if ([s.align length])
      t.style.textAlign = s.align;
    NSString *agg = nil;
    if (anyExplicit) {
      if ([s.aggregate length] && [s.field length])
        agg = [NSString stringWithFormat:@"=%@(Fields!%@.Value)", s.aggregate, s.field];
    } else if (i == n - 1 && [fallbackField length]) {
      agg = [NSString stringWithFormat:@"=Sum(Fields!%@.Value)", fallbackField];
    }
    if (agg) {
      t.value = agg;
    } else if (i == 0) {
      t.value = label;
      t.style.fontStyle = @"Italic";
      t.style.color = @"#5c574e";
    } else {
      t.value = @"";
    }
    RDLTablixCell *c = [[RDLTablixCell alloc] init];
    c.item = t;
    [row.cells addObject:c];
  }
  return row;
}

- (void)picaBuildTable:(NSArray *)cols headerHeight:(CGFloat)hh rowHeight:(CGFloat)rh {
  if (hh <= 0)
    hh = 0.3;
  if (rh <= 0)
    rh = 0.28;
  NSString *groupBy = [self.groupBy length] ? self.groupBy : nil;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixRow *header = [[RDLTablixRow alloc] init];
  header.height = hh;
  RDLTablixRow *detail = [[RDLTablixRow alloc] init];
  detail.height = rh;
  RDLTablixHierarchy *colH = [[RDLTablixHierarchy alloc] init];
  NSInteger i = 0;
  NSString *sumField = nil;
  NSMutableArray<PicaColSpec *> *specs = [NSMutableArray array];
  for (NSDictionary *c in cols) {
    RDLTablixColumn *tc = [[RDLTablixColumn alloc] init];
    tc.width = [c[@"width"] doubleValue];
    if (tc.width <= 0)
      tc.width = 1.6;
    [body.columns addObject:tc];
    [colH.members addObject:[[RDLTablixMember alloc] init]];

    NSString *align = c[@"align"];
    RDLItem *ht = [[RDLItem alloc] init];
    ht.type = @"Textbox";
    ht.name = [NSString stringWithFormat:@"%@H%ld", self.name ?: @"T", (long)i];
    ht.value = [c[@"header"] description] ?: @"";
    ht.style.fontWeight = @"Bold";
    if ([align length])
      ht.style.textAlign = align;
    RDLTablixCell *hc = [[RDLTablixCell alloc] init];
    hc.item = ht;
    [header.cells addObject:hc];

    RDLItem *dt = [[RDLItem alloc] init];
    dt.type = @"Textbox";
    dt.name = [NSString stringWithFormat:@"%@D%ld", self.name ?: @"T", (long)i];
    dt.value = [c[@"value"] description] ?: @"";
    if ([align length])
      dt.style.textAlign = align;
    RDLTablixCell *dc = [[RDLTablixCell alloc] init];
    dc.item = dt;
    [detail.cells addObject:dc];

    NSString *val = [c[@"value"] description] ?: @"";
    NSString *field = nil;
    NSRange bang = [val rangeOfString:@"Fields!"];
    if (bang.location != NSNotFound) {
      NSString *rest = [val substringFromIndex:bang.location + 7];
      NSRange dot = [rest rangeOfString:@"."];
      field = dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
      sumField = field;
    }
    PicaColSpec *spec = [[PicaColSpec alloc] init];
    spec.header = [c[@"header"] description] ?: @"";
    spec.value = val;
    spec.align = align;
    spec.aggregate = c[@"aggregate"];
    spec.field = field;
    spec.width = tc.width;
    [specs addObject:spec];
    i += 1;
  }
  [body.rows addObject:header];
  [body.rows addObject:detail];

  RDLTablixHierarchy *rowH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *hMem = [[RDLTablixMember alloc] init];
  hMem.repeatOnNewPage = YES;
  hMem.keepWithGroup = @"After";
  [rowH.members addObject:hMem];

  NSInteger extraRows = 0;
  if (groupBy) {
    [body.rows addObject:[self picaAggregateRow:specs
                                          label:@"Subtotal"
                                         prefix:@"F"
                                         height:rh
                                  fallbackField:sumField]];
    extraRows += 1;

    RDLTablixMember *gMem = [[RDLTablixMember alloc] init];
    gMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", groupBy];
    [gMem.groupExpressions addObject:[NSString stringWithFormat:@"=Fields!%@.Value", groupBy]];
    gMem.keepTogether = YES;
    RDLTablixHeader *th = [[RDLTablixHeader alloc] init];
    th.size = 1.2;
    RDLItem *gh = [[RDLItem alloc] init];
    gh.type = @"Textbox";
    gh.name = [NSString stringWithFormat:@"%@G", self.name ?: @"T"];
    gh.value = [NSString stringWithFormat:@"=Fields!%@.Value", groupBy];
    gh.style.fontWeight = @"Bold";
    gh.style.backgroundColor = @"#ece6d8";
    gh.style.verticalAlign = @"Middle";
    th.item = gh;
    gMem.header = th;
    RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
    dMem.groupName = [NSString stringWithFormat:@"%@_Details", self.name ?: @"Tablix"];
    RDLTablixMember *fMem = [[RDLTablixMember alloc] init];
    fMem.keepWithGroup = @"Before";
    [gMem.members addObject:dMem];
    [gMem.members addObject:fMem];
    [rowH.members addObject:gMem];

    self.repeatColumnHeaders = YES;
    if (![self.noRowsMessage length])
      self.noRowsMessage = @"No rows.";
    RDLTablixCell *corner = [[RDLTablixCell alloc] init];
    RDLItem *ct = [[RDLItem alloc] init];
    ct.type = @"Textbox";
    ct.name = [NSString stringWithFormat:@"%@Corner", self.name ?: @"T"];
    ct.value = groupBy;
    ct.style.fontWeight = @"Bold";
    ct.style.fontSize = @"8pt";
    ct.style.color = @"#5c574e";
    corner.item = ct;
    self.cornerRows = [NSMutableArray arrayWithObject:[NSMutableArray arrayWithObject:corner]];
  } else {
    RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
    dMem.groupName = [NSString stringWithFormat:@"%@_Details", self.name ?: @"Tablix"];
    [rowH.members addObject:dMem];
    self.cornerRows = [NSMutableArray array];
  }

  if (self.showGrandTotal) {
    [body.rows addObject:[self picaAggregateRow:specs
                                          label:@"Total"
                                         prefix:@"GT"
                                         height:rh
                                  fallbackField:sumField]];
    RDLTablixMember *tMem = [[RDLTablixMember alloc] init];
    tMem.keepWithGroup = @"Before";
    [rowH.members addObject:tMem];
    extraRows += 1;
  }

  if (groupBy) {
    CGFloat bodyW = 0;
    for (RDLTablixColumn *tc in body.columns)
      bodyW += tc.width;
    if (self.width < bodyW + 1.2)
      self.width = bodyW + 1.2;
  }
  if (self.height < hh + rh + extraRows * rh)
    self.height = hh + rh + extraRows * rh;

  self.tablixBody = body;
  self.columnHierarchy = colH;
  self.rowHierarchy = rowH;
  _stashHeaderH = hh;
  _stashRowH = rh;
}


@end

@implementation RDLBand
- (instancetype)init {
  self = [super init];
  if (self) {
    _items = [NSMutableArray array];
    _printOnFirstPage = YES;
    _printOnLastPage = YES;
    _height = 0.5;
  }
  return self;
}
@end

@implementation RDLField
@end

@implementation RDLEmbeddedImage
@end

@implementation RDLDataSet
- (instancetype)init {
  self = [super init];
  if (self) {
    _filters = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLDataSource
@end

@implementation RDLParameter
- (instancetype)init {
  self = [super init];
  if (self) {
    _defaultValues = [NSMutableArray array];
    _validValues = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLPage
- (instancetype)init {
  self = [super init];
  if (self) {
    _pageWidth = 8.5;
    _pageHeight = 11.0;
    _leftMargin = _rightMargin = _topMargin = _bottomMargin = 0.5;
  }
  return self;
}
@end

@implementation RDLReport
+ (instancetype)emptyReportNamed:(NSString *)name {
  RDLReport *r = [[RDLReport alloc] init];
  r.name = name ?: @"Untitled";
  r.author = @"Pica";
  r.reportDescription = @"";
  r.width = 7.5;
  r.page = [[RDLPage alloc] init];
  r.pageHeader = [[RDLBand alloc] init];
  r.pageHeader.height = 0.55;
  r.body = [[RDLBand alloc] init];
  r.body.height = 4.0;
  r.pageFooter = [[RDLBand alloc] init];
  r.pageFooter.height = 0.4;
  r.dataSources = [NSMutableArray array];
  RDLDataSource *dsrc = [[RDLDataSource alloc] init];
  dsrc.name = @"Demo";
  dsrc.dataProvider = @"JSON";
  dsrc.connectString = @"";
  [r.dataSources addObject:dsrc];
  r.dataSets = [NSMutableArray array];
  r.parameters = [NSMutableArray array];
  r.embeddedImages = [NSMutableArray array];
  r.warnings = [NSMutableArray array];
  return r;
}

- (RDLEmbeddedImage *)embeddedImageNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLEmbeddedImage *img in self.embeddedImages)
    if ([img.name caseInsensitiveCompare:name] == NSOrderedSame)
      return img;
  return nil;
}

- (RDLBand *)bandWithKey:(NSString *)key {
  if ([key isEqualToString:@"pageHeader"])
    return self.pageHeader;
  if ([key isEqualToString:@"pageFooter"])
    return self.pageFooter;
  return self.body;
}

- (NSArray<RDLItem *> *)allItems {
  NSMutableArray *a = [NSMutableArray array];
  [a addObjectsFromArray:self.pageHeader.items];
  [a addObjectsFromArray:self.body.items];
  [a addObjectsFromArray:self.pageFooter.items];
  return a;
}

- (RDLItem *)itemNamed:(NSString *)name inBand:(RDLBand **)outBand {
  NSArray *keys = @[ @"pageHeader", @"body", @"pageFooter" ];
  for (NSString *k in keys) {
    RDLBand *b = [self bandWithKey:k];
    for (RDLItem *it in b.items) {
      if ([it.name isEqualToString:name]) {
        if (outBand)
          *outBand = b;
        return it;
      }
    }
  }
  if (outBand)
    *outBand = nil;
  return nil;
}

- (NSString *)nextNameWithPrefix:(NSString *)prefix {
  NSMutableSet *used = [NSMutableSet set];
  for (RDLItem *it in [self allItems])
    if (it.name)
      [used addObject:it.name];
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
}
@end

@implementation RDLLaidOutItem
@end

@implementation RDLLaidOutPage
- (instancetype)init {
  self = [super init];
  if (self) {
    _items = [NSMutableArray array];
  }
  return self;
}
@end
