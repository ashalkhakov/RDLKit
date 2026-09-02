#import "RDLLayoutEngine.h"
#import "RDLReport.h"
#import "RDLExpression.h"
#import <math.h>

@interface PicaTablixCellInst : NSObject
@property (nonatomic, assign) CGFloat xRel;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, assign) NSInteger rowSpan;
@property (nonatomic, assign) BOOL skip;
@property (nonatomic, assign) BOOL rowHeader;
// Crosstab: when a dynamic column group produced this cell, the data rows
// belonging to the column instance. Evaluation intersects them with the
// row instance's rows.
@property (nonatomic, copy) NSArray *colRows;
@end
@implementation PicaTablixCellInst
@end

@interface PicaTablixInst : NSObject
@property (nonatomic, assign) CGFloat yRel;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) BOOL repeatOnNewPage;
@property (nonatomic, assign) BOOL pageBreakBefore;
@property (nonatomic, assign) BOOL resetPageNumber;
@property (nonatomic, copy) NSString *pageName;
@property (nonatomic, assign) CGFloat keepTogetherHeight;
@property (nonatomic, strong) NSMutableArray<PicaTablixCellInst *> *cells;
@property (nonatomic, copy) NSDictionary *row;
@property (nonatomic, copy) NSArray *groupRows;
@end
@implementation PicaTablixInst
@end

// One rendered column of the tablix body. For dynamic (crosstab) column
// groups the same body column repeats once per distinct group instance.
// One tier of a column-group header above a plan leaf. Consecutive leaves
// sharing the same node (pointer identity) are merged into one spanning cell.
@interface PicaColHeaderNode : NSObject
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, assign) CGFloat size;
@property (nonatomic, copy) NSArray *rows; // group-instance rows; nil = all rows
@end
@implementation PicaColHeaderNode
@end

@interface PicaColPlanEntry : NSObject
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) NSUInteger bodyCol;
@property (nonatomic, copy) NSArray *colRows; // nil for static columns
@property (nonatomic, copy) NSArray<PicaColHeaderNode *> *headerChain; // outermost tier first
@end
@implementation PicaColPlanEntry
@end

@implementation RDLLayoutEngine

static RDLDataSet *PicaFindSet(RDLReport *report, NSString *name) {
  for (RDLDataSet *d in report.dataSets)
    if ([d.name isEqualToString:name])
      return d;
  return nil;
}

static NSInteger PicaLeafCount(NSArray<RDLTablixMember *> *members) {
  NSInteger n = 0;
  for (RDLTablixMember *m in members) {
    if ([m.members count])
      n += PicaLeafCount(m.members);
    else
      n += 1;
  }
  return n;
}

static CGFloat PicaHeaderWidth(NSArray<RDLTablixMember *> *members) {
  CGFloat max = 0;
  for (RDLTablixMember *m in members) {
    CGFloat own = m.header.size;
    CGFloat child = [m.members count] ? PicaHeaderWidth(m.members) : 0;
    if (own + child > max)
      max = own + child;
  }
  return max;
}

static NSString *PicaFieldOf(NSString *expr) {
  if (expr == nil)
    return nil;
  NSRange r = [expr rangeOfString:@"Fields!"];
  if (r.location == NSNotFound)
    return nil;
  NSString *rest = [expr substringFromIndex:r.location + 7];
  NSRange dot = [rest rangeOfString:@"."];
  return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
}

// A grouping/sort/filter value against one row. A literal that names a field
// ("Fields!Total.Value" written without the "=") still resolves against the
// row, which is why this is not just -[RDLValue evaluateInScope:].
static id PicaEvalRow(RDLValue *value, NSDictionary *row, RDLEvalScope *scope) {
  if (value == nil)
    return @"";
  NSString *source = [value source];
  if (![value isExpression]) {
    NSString *f = PicaFieldOf(source);
    if (f && row) {
      for (NSString *k in row)
        if ([k caseInsensitiveCompare:f] == NSOrderedSame)
          return row[k];
    }
    return source;
  }
  if (scope) {
    NSDictionary *saved = scope.row;
    scope.row = row;
    id v = [value evaluateInScope:scope];
    scope.row = saved;
    return v;
  }
  // No scope to evaluate in: fall back to the field the expression names.
  NSString *f = PicaFieldOf(source);
  if (f && row) {
    for (NSString *k in row)
      if ([k caseInsensitiveCompare:f] == NSOrderedSame)
        return row[k];
  }
  return [source substringFromIndex:1];
}

static NSString *PicaAsStr(id v) {
  if (v == nil || v == [NSNull null])
    return @"";
  return [v description];
}

// Visibility/Hidden: constant true/false or an `=` expression.
// An expression with nothing to evaluate against stays visible, rather than
// disappearing from a preview that has no data bound yet.
static BOOL PicaIsHiddenExpr(RDLValue *hidden, RDLEvalScope *scope) {
  if (hidden == nil)
    return NO;
  if ([hidden isExpression])
    return scope ? [hidden evaluateBoolInScope:scope] : NO;
  return [hidden evaluateBoolInScope:nil];
}

// Styles may carry `=` expressions (conditional formatting), kept apart from
// the constants in style.expressions. Resolve them per instance at layout time
// so backends only ever see constants; returns the original object when the
// style is fully static.
// A border resolves independently of the style that holds it.
static RDLBorder *PicaResolveBorder(RDLBorder *b, RDLEvalScope *scope) {
  if (b == nil || b.expressions == nil || [b.expressions isEmpty])
    return b;
  RDLBorderExpressions *e = b.expressions;
  RDLBorder *r = [[RDLBorder alloc] init];
  r.style = e.style ? RDLBorderStyleFromString([e.style evaluateTextInScope:scope]) : b.style;
  r.width = e.width ? [RDLLength lengthFromString:[e.width evaluateTextInScope:scope]] : b.width;
  r.color = e.color ? [e.color evaluateTextInScope:scope] : b.color;
  return r;
}

static BOOL PicaBorderIsDynamic(RDLBorder *b) {
  return b.expressions != nil && ![b.expressions isEmpty];
}

// Borders carry their own expressions, so a style with none of its own may
// still need resolving.
static BOOL PicaStyleIsDynamic(RDLStyle *s) {
  if (s.expressions != nil && ![s.expressions isEmpty])
    return YES;
  return PicaBorderIsDynamic(s.border) || PicaBorderIsDynamic(s.borderLeft) ||
         PicaBorderIsDynamic(s.borderRight) || PicaBorderIsDynamic(s.borderTop) ||
         PicaBorderIsDynamic(s.borderBottom);
}

static RDLStyle *PicaResolveStyle(RDLStyle *s, RDLEvalScope *scope) {
  if (s == nil || scope == nil || !PicaStyleIsDynamic(s))
    return s;
  RDLStyleExpressions *e = s.expressions;  // nil-safe: messages to nil yield nil
  RDLStyle *r = [[RDLStyle alloc] init];
  r.color = e.color ? [e.color evaluateTextInScope:scope] : s.color;
  r.backgroundColor =
      e.backgroundColor ? [e.backgroundColor evaluateTextInScope:scope] : s.backgroundColor;
  r.fontFamily = e.fontFamily ? [e.fontFamily evaluateTextInScope:scope] : s.fontFamily;
  r.fontSize = e.fontSize ? [RDLLength lengthFromString:[e.fontSize evaluateTextInScope:scope]]
                          : s.fontSize;
  r.format = e.format ? [e.format evaluateTextInScope:scope] : s.format;
  // A vocabulary property's expression yields one of that vocabulary's names.
  r.fontWeight = e.fontWeight ? RDLFontWeightFromString([e.fontWeight evaluateTextInScope:scope])
                              : s.fontWeight;
  r.fontStyle =
      e.fontStyle ? RDLFontStyleFromString([e.fontStyle evaluateTextInScope:scope]) : s.fontStyle;
  r.textAlign =
      e.textAlign ? RDLTextAlignFromString([e.textAlign evaluateTextInScope:scope]) : s.textAlign;
  r.verticalAlign = e.verticalAlign
                        ? RDLVerticalAlignFromString([e.verticalAlign evaluateTextInScope:scope])
                        : s.verticalAlign;
  r.textDecoration =
      e.textDecoration ? RDLTextDecorationFromString([e.textDecoration evaluateTextInScope:scope])
                       : s.textDecoration;
  r.paddingLeft = e.paddingLeft
                      ? [RDLLength lengthFromString:[e.paddingLeft evaluateTextInScope:scope]]
                      : s.paddingLeft;
  r.paddingRight = e.paddingRight
                       ? [RDLLength lengthFromString:[e.paddingRight evaluateTextInScope:scope]]
                       : s.paddingRight;
  r.paddingTop = e.paddingTop
                     ? [RDLLength lengthFromString:[e.paddingTop evaluateTextInScope:scope]]
                     : s.paddingTop;
  r.paddingBottom = e.paddingBottom
                        ? [RDLLength lengthFromString:[e.paddingBottom evaluateTextInScope:scope]]
                        : s.paddingBottom;
  r.border = PicaResolveBorder(s.border, scope);
  r.borderLeft = PicaResolveBorder(s.borderLeft, scope);
  r.borderRight = PicaResolveBorder(s.borderRight, scope);
  r.borderTop = PicaResolveBorder(s.borderTop, scope);
  r.borderBottom = PicaResolveBorder(s.borderBottom, scope);
  return r;
}

// The unit is part of the value now, so "0.5in" is half an inch rather than
// the half a point [raw doubleValue] used to read it as.
static CGFloat PicaPtToIn(RDLLength *length, CGFloat fallbackPt) {
  CGFloat pt = length ? [length points] : 0;
  if (pt <= 0)
    pt = fallbackPt;
  return pt / 72.0;
}

// Deterministic, backend-independent text height estimate for CanGrow.
static CGFloat PicaEstimateTextHeight(NSString *text, RDLStyle *style, CGFloat widthIn) {
  if ([text length] == 0)
    return 0;
  CGFloat fontIn = PicaPtToIn(style.fontSize, 10);
  CGFloat lineH = fontIn * 1.35;
  CGFloat charW = fontIn * 0.52;
  CGFloat padL = PicaPtToIn(style.paddingLeft, 0);
  CGFloat padR = PicaPtToIn(style.paddingRight, 0);
  CGFloat padT = PicaPtToIn(style.paddingTop, 0);
  CGFloat padB = PicaPtToIn(style.paddingBottom, 0);
  CGFloat usable = widthIn - padL - padR;
  if (usable < charW)
    usable = charW;
  NSInteger lines = 0;
  for (NSString *para in [text componentsSeparatedByString:@"\n"]) {
    NSInteger perLine = (NSInteger)floor(usable / charW);
    if (perLine < 1)
      perLine = 1;
    NSInteger need = (NSInteger)ceil((double)[para length] / (double)perLine);
    lines += MAX(need, 1);
  }
  return lines * lineH + padT + padB;
}

// Height a textbox wants when CanGrow is on (>= design height).
static CGFloat PicaTextboxGrownHeight(RDLTextbox *item, CGFloat width, RDLEvalScope *scope) {
  if (![item isKindOfClass:[RDLTextbox class]] || !item.canGrow || scope == nil)
    return item.height;
  RDLStyle *st = PicaResolveStyle(item.style, scope);
  NSString *text = [RDLExpression formatValue:[RDLExpression evaluate:item.value scope:scope]
                                       format:st.format];
  CGFloat needed = PicaEstimateTextHeight(text, st ?: item.style, width > 0 ? width : item.width);
  return MAX(item.height, needed);
}

static double PicaAsN(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

static NSComparisonResult PicaCmp(id a, id b) {
  BOOL numeric = [a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]];
  if (numeric) {
    double d = PicaAsN(a) - PicaAsN(b);
    if (d < 0)
      return NSOrderedAscending;
    if (d > 0)
      return NSOrderedDescending;
    return NSOrderedSame;
  }
  return [PicaAsStr(a) caseInsensitiveCompare:PicaAsStr(b)];
}

static BOOL PicaLike(NSString *value, NSString *pattern) {
  NSMutableString *p = [pattern mutableCopy];
  [p replaceOccurrencesOfString:@"." withString:@"\\." options:0 range:NSMakeRange(0, p.length)];
  [p replaceOccurrencesOfString:@"*" withString:@".*" options:0 range:NSMakeRange(0, p.length)];
  [p replaceOccurrencesOfString:@"?" withString:@"." options:0 range:NSMakeRange(0, p.length)];
  NSRegularExpression *re =
      [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", p]
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:nil];
  NSString *val = value ?: @"";
  return [re numberOfMatchesInString:val options:0 range:NSMakeRange(0, val.length)] > 0;
}

static BOOL PicaPassesFilter(NSDictionary *row, RDLFilter *f, RDLEvalScope *scope) {
  id left = PicaEvalRow(f.expression, row, scope);
  RDLFilterOperator op = f.oper != RDLFilterOperatorUnspecified ? f.oper : RDLFilterOperatorEqual;
  id right = [f.values count] ? PicaEvalRow(f.values[0], row, scope) : @"";
  if (op == RDLFilterOperatorEqual)
    return PicaCmp(left, right) == NSOrderedSame;
  if (op == RDLFilterOperatorNotEqual)
    return PicaCmp(left, right) != NSOrderedSame;
  if (op == RDLFilterOperatorGreaterThan)
    return PicaCmp(left, right) == NSOrderedDescending;
  if (op == RDLFilterOperatorGreaterThanOrEqual)
    return PicaCmp(left, right) != NSOrderedAscending;
  if (op == RDLFilterOperatorLessThan)
    return PicaCmp(left, right) == NSOrderedAscending;
  if (op == RDLFilterOperatorLessThanOrEqual)
    return PicaCmp(left, right) != NSOrderedDescending;
  if (op == RDLFilterOperatorContains)
    return [PicaAsStr(left).lowercaseString rangeOfString:PicaAsStr(right).lowercaseString].location !=
           NSNotFound;
  if (op == RDLFilterOperatorLike)
    return PicaLike(PicaAsStr(left), PicaAsStr(right));
  if (op == RDLFilterOperatorBetween) {
    id hi = [f.values count] > 1 ? PicaEvalRow(f.values[1], row, scope) : right;
    return PicaCmp(left, right) != NSOrderedAscending && PicaCmp(left, hi) != NSOrderedDescending;
  }
  if (op == RDLFilterOperatorIn) {
    for (RDLValue *v in f.values) {
      if (PicaCmp(left, PicaEvalRow(v, row, scope)) == NSOrderedSame)
        return YES;
    }
    return NO;
  }
  return YES;
}

static NSArray *PicaApplyFilters(NSArray *rows, NSArray<RDLFilter *> *filters, RDLEvalScope *scope) {
  if ([filters count] == 0)
    return rows;
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *row in rows) {
    BOOL ok = YES;
    for (RDLFilter *f in filters) {
      if (!PicaPassesFilter(row, f, scope)) {
        ok = NO;
        break;
      }
    }
    if (ok)
      [out addObject:row];
  }
  return out;
}

static NSArray *PicaApplySort(NSArray *rows, NSArray<RDLSortExpression *> *sorts, RDLEvalScope *scope) {
  if ([sorts count] == 0)
    return rows;
  return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    for (RDLSortExpression *s in sorts) {
      NSComparisonResult c = PicaCmp(PicaEvalRow(s.expression, a, scope), PicaEvalRow(s.expression, b, scope));
      if (s.direction == RDLSortDirectionDescending) {
        if (c == NSOrderedAscending)
          c = NSOrderedDescending;
        else if (c == NSOrderedDescending)
          c = NSOrderedAscending;
      }
      if (c != NSOrderedSame)
        return c;
    }
    return NSOrderedSame;
  }];
}

static NSArray *PicaPartition(NSArray *rows, NSArray<RDLValue *> *exprs, RDLEvalScope *scope) {
  NSMutableArray *order = [NSMutableArray array];
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  for (NSDictionary *row in rows) {
    NSMutableString *key = [NSMutableString string];
    for (RDLValue *e in exprs) {
      [key appendString:PicaAsStr(PicaEvalRow(e, row, scope))];
      [key appendString:@"\x1f"];
    }
    NSMutableArray *bucket = map[key];
    if (bucket == nil) {
      bucket = [NSMutableArray array];
      map[key] = bucket;
      [order addObject:key];
    }
    [bucket addObject:row];
  }
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *k in order)
    [out addObject:map[k]];
  return out;
}

static NSArray *PicaSortParts(NSArray *parts, NSArray<RDLSortExpression *> *sorts, RDLEvalScope *scope) {
  if ([sorts count] == 0)
    return parts;
  return [parts sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
    NSDictionary *ra = [a count] ? a[0] : @{};
    NSDictionary *rb = [b count] ? b[0] : @{};
    for (RDLSortExpression *s in sorts) {
      NSComparisonResult c = PicaCmp(PicaEvalRow(s.expression, ra, scope), PicaEvalRow(s.expression, rb, scope));
      if (s.direction == RDLSortDirectionDescending) {
        if (c == NSOrderedAscending)
          c = NSOrderedDescending;
        else if (c == NSOrderedDescending)
          c = NSOrderedAscending;
      }
      if (c != NSOrderedSame)
        return c;
    }
    return NSOrderedSame;
  }];
}

// Build the rendered column list from TablixColumnHierarchy. Returns nil when
// there is no dynamic column group (static layout keeps the fast path).
static BOOL PicaAnyDynamicMember(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length] && [m.groupExpressions count])
      return YES;
    if ([m.members count] && PicaAnyDynamicMember(m.members))
      return YES;
  }
  return NO;
}

// Recursively expand column members into leaf plan entries. `leafStart` is the
// body-column index of the first leaf under `members`; each dynamic group
// instance re-expands the same underlying body columns.
static void PicaColPlanWalk(NSArray<RDLTablixMember *> *members, NSArray *dataRows, RDLTablix *tab,
                            RDLEvalScope *scope, NSArray<PicaColHeaderNode *> *chain,
                            NSInteger leafStart, NSMutableArray *plan) {
  NSArray<RDLTablixColumn *> *cols = tab.tablixBody.columns;
  NSInteger leaf = leafStart;
  for (RDLTablixMember *m in members) {
    BOOL nested = [m.members count] > 0;
    NSInteger count = nested ? PicaLeafCount(m.members) : 1;
    if (PicaIsHiddenExpr(m.hidden, scope)) {
      leaf += count;
      continue;
    }
    CGFloat w = leaf < (NSInteger)[cols count] ? cols[(NSUInteger)leaf].width : 1.0;
    if ([m.groupName length] && [m.groupExpressions count]) {
      NSArray *parts = PicaPartition(dataRows, m.groupExpressions, scope);
      NSMutableArray *kept = [NSMutableArray array];
      for (NSArray *part in parts) {
        NSArray *fp = PicaApplyFilters(part, m.filters, scope);
        if ([fp count])
          [kept addObject:fp];
      }
      for (NSArray *part in PicaSortParts(kept, m.sortExpressions, scope)) {
        PicaColHeaderNode *node = [[PicaColHeaderNode alloc] init];
        node.item = m.header.item;
        node.size = m.header.size;
        node.rows = part;
        NSArray *newChain = [chain arrayByAddingObject:node];
        if (nested) {
          PicaColPlanWalk(m.members, part, tab, scope, newChain, leaf, plan);
        } else {
          PicaColPlanEntry *e = [[PicaColPlanEntry alloc] init];
          e.width = w;
          e.bodyCol = (NSUInteger)leaf;
          e.colRows = part;
          e.headerChain = newChain;
          [plan addObject:e];
        }
      }
    } else {
      PicaColHeaderNode *node = [[PicaColHeaderNode alloc] init];
      node.item = m.header.item;
      node.size = m.header.size;
      node.rows = nil;
      NSArray *newChain = [chain arrayByAddingObject:node];
      if (nested) {
        PicaColPlanWalk(m.members, dataRows, tab, scope, newChain, leaf, plan);
      } else {
        PicaColPlanEntry *e = [[PicaColPlanEntry alloc] init];
        e.width = w;
        e.bodyCol = (NSUInteger)leaf;
        e.headerChain = newChain;
        [plan addObject:e];
      }
    }
    leaf += count;
  }
}

static NSArray<PicaColPlanEntry *> *PicaColumnPlan(RDLTablix *tab, NSArray *dataRows, RDLEvalScope *scope) {
  NSArray<RDLTablixMember *> *members = tab.columnHierarchy.members;
  if ([members count] == 0)
    return nil;
  if (!PicaAnyDynamicMember(members))
    return nil;
  NSMutableArray *plan = [NSMutableArray array];
  PicaColPlanWalk(members, dataRows, tab, scope, @[], 0, plan);
  return plan;
}

static NSMutableArray *PicaBodyCells(RDLTablixRow *bodyRow, NSArray<RDLTablixColumn *> *columns,
                                     CGFloat bodyX, CGFloat height, NSArray<PicaColPlanEntry *> *plan) {
  NSMutableArray *cells = [NSMutableArray array];
  if (bodyRow == nil)
    return cells;
  if (plan) {
    CGFloat px = bodyX;
    for (PicaColPlanEntry *e in plan) {
      RDLTablixCell *cell = e.bodyCol < [bodyRow.cells count] ? bodyRow.cells[e.bodyCol] : nil;
      PicaTablixCellInst *cix = [[PicaTablixCellInst alloc] init];
      cix.xRel = px;
      cix.width = e.width;
      cix.height = height;
      cix.item = cell.item;
      cix.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : 1;
      cix.colRows = e.colRows;
      [cells addObject:cix];
      px += e.width;
    }
    return cells;
  }
  NSUInteger n = [columns count];
  NSUInteger ci = 0;
  CGFloat x = bodyX;
  while (ci < n) {
    RDLTablixCell *cell = ci < [bodyRow.cells count] ? bodyRow.cells[ci] : nil;
    NSInteger span = cell.colSpan > 1 ? cell.colSpan : 1;
    CGFloat w = 0;
    for (NSInteger s = 0; s < span && ci + (NSUInteger)s < n; s++)
      w += columns[ci + (NSUInteger)s].width;
    PicaTablixCellInst *cix = [[PicaTablixCellInst alloc] init];
    cix.xRel = x;
    cix.width = w;
    cix.height = height;
    cix.item = cell.item;
    cix.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : 1;
    [cells addObject:cix];
    x += w;
    ci += (NSUInteger)MAX(span, 1);
  }
  return cells;
}

// Rows shared between a row instance and a column instance (pointer identity;
// both sides are subsets of the same dataset row array).
static NSArray *PicaIntersectRows(NSArray *rowsA, NSArray *colRows) {
  if (rowsA == nil)
    return colRows;
  NSMutableArray *out = [NSMutableArray array];
  for (id r in rowsA) {
    if ([colRows indexOfObjectIdenticalTo:r] != NSNotFound)
      [out addObject:r];
  }
  return out;
}

static void PicaApplyRowSpan(NSArray<PicaTablixInst *> *insts) {
  for (NSUInteger i = 0; i < [insts count]; i++) {
    for (PicaTablixCellInst *cell in insts[i].cells) {
      if (cell.rowSpan <= 1)
        continue;
      CGFloat h = 0;
      for (NSInteger k = 0; k < cell.rowSpan && i + (NSUInteger)k < [insts count]; k++)
        h += insts[i + (NSUInteger)k].height;
      cell.height = h;
      for (NSInteger k = 1; k < cell.rowSpan && i + (NSUInteger)k < [insts count]; k++) {
        for (PicaTablixCellInst *c in insts[i + (NSUInteger)k].cells) {
          if (fabs(c.xRel - cell.xRel) < 1e-6)
            c.skip = YES;
        }
      }
    }
  }
}

static NSArray *PicaEmitRuns(RDLTablixMember *m, RDLTablixRow *bodyRow, NSArray *currentRows,
                             BOOL dynamic, NSDictionary *row, NSArray *groupRows, RDLTablix *tab,
                             CGFloat headerW, NSArray<PicaColPlanEntry *> *plan) {
  CGFloat h = bodyRow.height > 0 ? bodyRow.height : 0.28;
  BOOL repeat = m.repeatOnNewPage || (tab.repeatColumnHeaders && m.keepWithGroup == RDLKeepWithGroupAfter &&
                                      [m.groupName length] == 0);
  NSArray *runs = dynamic ? ([currentRows count] ? currentRows : @[ @{} ])
                          : @[ row ?: [NSNull null] ];
  NSMutableArray *local = [NSMutableArray array];
  for (id r in runs) {
    PicaTablixInst *inst = [[PicaTablixInst alloc] init];
    inst.height = h;
    inst.repeatOnNewPage = repeat && !dynamic;
    inst.cells = PicaBodyCells(bodyRow, tab.tablixBody.columns, headerW, h, plan);
    inst.row = (r == [NSNull null]) ? nil : r;
    inst.groupRows = groupRows;
    [local addObject:inst];
  }
  return local;
}

static NSArray *PicaWalkMembers(NSArray<RDLTablixMember *> *list, NSArray *currentRows, CGFloat headerX,
                                NSInteger leafStart, RDLTablix *tab, RDLEvalScope *scope, CGFloat headerW,
                                NSArray<PicaColPlanEntry *> *plan);

static NSArray *PicaWalkMembers(NSArray<RDLTablixMember *> *list, NSArray *currentRows, CGFloat headerX,
                                NSInteger leafStart, RDLTablix *tab, RDLEvalScope *scope, CGFloat headerW,
                                NSArray<PicaColPlanEntry *> *plan) {
  NSMutableArray *out = [NSMutableArray array];
  NSInteger leaf = leafStart;
  RDLTablixBody *body = tab.tablixBody;
  for (RDLTablixMember *m in list) {
    BOOL nested = [m.members count] > 0;
    NSInteger count = nested ? PicaLeafCount(m.members) : 1;
    BOOL hasGroup = [m.groupName length] > 0;
    NSArray *exprs = m.groupExpressions;
    CGFloat childX = headerX + m.header.size;
    if (PicaIsHiddenExpr(m.hidden, scope)) {
      leaf += count;
      continue;
    }

    if (hasGroup && [exprs count]) {
      NSArray *parts = PicaPartition(currentRows, exprs, scope);
      NSMutableArray *kept = [NSMutableArray array];
      for (NSArray *part in parts) {
        NSArray *fp = PicaApplyFilters(part, m.filters, scope);
        if ([fp count])
          [kept addObject:fp];
      }
      parts = kept;
      if ([m.sortExpressions count]) {
        parts = [parts sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
          NSDictionary *ra = [a count] ? a[0] : @{};
          NSDictionary *rb = [b count] ? b[0] : @{};
          for (RDLSortExpression *s in m.sortExpressions) {
            NSComparisonResult c =
                PicaCmp(PicaEvalRow(s.expression, ra, scope), PicaEvalRow(s.expression, rb, scope));
            if (s.direction == RDLSortDirectionDescending) {
              if (c == NSOrderedAscending)
                c = NSOrderedDescending;
              else if (c == NSOrderedDescending)
                c = NSOrderedAscending;
            }
            if (c != NSOrderedSame)
              return c;
          }
          return NSOrderedSame;
        }];
      }
      NSInteger partIndex = 0;
      for (NSArray *part in parts) {
        NSArray *childInsts = nested ? PicaWalkMembers(m.members, part, childX, leaf, tab, scope, headerW, plan)
                                     : PicaEmitRuns(m, leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : nil,
                                                    part, NO, [part firstObject], part, tab, headerW, plan);
        if ([childInsts count] == 0) {
          partIndex += 1;
          continue;
        }
        CGFloat groupH = 0;
        for (PicaTablixInst *ci in childInsts)
          groupH += ci.height;
        PicaTablixInst *first = childInsts[0];
        if (m.header) {
          PicaTablixCellInst *hc = [[PicaTablixCellInst alloc] init];
          hc.xRel = headerX;
          hc.width = m.header.size > 0 ? m.header.size : headerW;
          hc.height = groupH;
          hc.item = m.header.item;
          hc.rowHeader = YES;
          NSMutableArray *cells = [NSMutableArray arrayWithObject:hc];
          [cells addObjectsFromArray:first.cells];
          first.cells = cells;
        }
        if (m.keepTogether)
          first.keepTogetherHeight = groupH;
        RDLPageBreakLocation brk = m.pageBreak;
        if (partIndex > 0 && (brk == RDLPageBreakLocationBetween ||
                              brk == RDLPageBreakLocationStartAndEnd))
          first.pageBreakBefore = YES;
        if (partIndex == 0 && (brk == RDLPageBreakLocationStart ||
                               brk == RDLPageBreakLocationStartAndEnd))
          first.pageBreakBefore = YES;
        if (first.pageBreakBefore) {
          first.resetPageNumber = first.resetPageNumber || m.resetPageNumber;
          if (m.pageName != nil)
            first.pageName = PicaAsStr(PicaEvalRow(m.pageName, [part firstObject], scope));
        }
        for (PicaTablixInst *ci in childInsts) {
          if (ci.groupRows == nil)
            ci.groupRows = part;
          if (ci.row == nil)
            ci.row = [part firstObject];
        }
        [out addObjectsFromArray:childInsts];
        partIndex += 1;
      }
      leaf += count;
      continue;
    }

    if (hasGroup && !nested) {
      RDLTablixRow *br = leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : body.rows.lastObject;
      [out addObjectsFromArray:PicaEmitRuns(m, br, currentRows, YES, nil, currentRows, tab, headerW, plan)];
      leaf += 1;
      continue;
    }

    if (nested) {
      NSArray *childInsts = PicaWalkMembers(m.members, currentRows, childX, leaf, tab, scope, headerW, plan);
      [out addObjectsFromArray:childInsts];
      leaf += count;
      continue;
    }

    RDLTablixRow *br = leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : body.rows.lastObject;
    [out addObjectsFromArray:PicaEmitRuns(m, br, currentRows, NO, [currentRows firstObject], currentRows, tab,
                                          headerW, plan)];
    leaf += 1;
  }
  return out;
}

static NSArray *PicaApplyPageRules(NSArray<PicaTablixInst *> *insts, CGFloat bodyAvail, CGFloat tablixTop) {
  if ([insts count] == 0 || bodyAvail <= 0)
    return insts;
  CGFloat y = 0;
  for (PicaTablixInst *inst in insts) {
    if (inst.pageBreakBefore) {
      CGFloat abs = tablixTop + y;
      CGFloat into = fmod(abs, bodyAvail);
      if (into < 0)
        into += bodyAvail;
      if (into > 0.0001)
        y += bodyAvail - into;
    }
    if (inst.keepTogetherHeight > 0) {
      CGFloat abs = tablixTop + y;
      CGFloat into = fmod(abs, bodyAvail);
      if (into < 0)
        into += bodyAvail;
      CGFloat remain = bodyAvail - into;
      if (inst.keepTogetherHeight > remain + 0.001 && inst.keepTogetherHeight <= bodyAvail + 0.001) {
        if (into > 0.0001)
          y += bodyAvail - into;
      }
    }
    inst.yRel = y;
    y += inst.height;
  }
  return insts;
}

static NSArray<PicaTablixInst *> *PicaExpandTablix(RDLTablix *tab, RDLReport *report, RDLEvalScope *scope,
                                                   CGFloat bodyAvail, CGFloat tablixTop) {
  if (tab.tablixBody == nil || [tab.tablixBody.rows count] == 0)
    [tab rebuildTablix];
  RDLTablixBody *body = tab.tablixBody;
  if ([body.rows count] == 0)
    return @[];
  RDLDataSet *ds = PicaFindSet(report, tab.dataSetName);
  NSArray *dataRows = ds.rows ?: @[];
  dataRows = PicaApplyFilters(dataRows, tab.filters, scope);
  dataRows = PicaApplySort(dataRows, tab.sortExpressions, scope);

  if ([dataRows count] == 0 && [tab.noRowsMessage length]) {
    PicaTablixInst *inst = [[PicaTablixInst alloc] init];
    inst.height = tab.rowHeight > 0 ? tab.rowHeight : 0.35;
    PicaTablixCellInst *cell = [[PicaTablixCellInst alloc] init];
    cell.xRel = 0;
    cell.width = tab.width > 0 ? tab.width : 7.5;
    cell.height = inst.height;
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = [NSString stringWithFormat:@"%@NoRows", tab.name ?: @"T"];
    tb.value = tab.noRowsMessage;
    tb.style.fontStyle = RDLFontStyleItalic;
    cell.item = tb;
    inst.cells = [NSMutableArray arrayWithObject:cell];
    inst.groupRows = @[];
    return @[ inst ];
  }

  NSArray *rows = [dataRows count] ? dataRows : @[ @{} ];
  NSArray<PicaColPlanEntry *> *plan = PicaColumnPlan(tab, dataRows, scope);
  NSArray *members = tab.rowHierarchy.members;
  CGFloat headerW = PicaHeaderWidth(members);
  NSArray *walked;
  if ([members count]) {
    walked = PicaWalkMembers(members, rows, 0, 0, tab, scope, headerW, plan);
  } else {
    NSMutableArray *synth = [NSMutableArray array];
    for (NSUInteger i = 0; i < [body.rows count]; i++) {
      RDLTablixMember *m = [[RDLTablixMember alloc] init];
      if (i == 0) {
        m.repeatOnNewPage = YES;
        m.keepWithGroup = RDLKeepWithGroupAfter;
      } else {
        m.groupName = @"Details";
      }
      [synth addObject:m];
    }
    walked = PicaWalkMembers(synth, rows, 0, 0, tab, scope, headerW, plan);
  }

  // Crosstab: emit one column-header row per column-group tier. Consecutive
  // leaves sharing a header node are merged into a single spanning cell.
  CGFloat planHdrTotalH = 0;
  if (plan) {
    NSUInteger tiers = 0;
    for (PicaColPlanEntry *e in plan)
      tiers = MAX(tiers, [e.headerChain count]);
    NSMutableArray *headerRows = [NSMutableArray array];
    for (NSUInteger t = 0; t < tiers; t++) {
      CGFloat hdrH = 0;
      BOOL anyHdr = NO;
      for (PicaColPlanEntry *e in plan) {
        PicaColHeaderNode *n = t < [e.headerChain count] ? e.headerChain[t] : nil;
        if (n.item) {
          anyHdr = YES;
          hdrH = MAX(hdrH, n.size);
        }
      }
      if (!anyHdr)
        continue;
      if (hdrH <= 0)
        hdrH = 0.28;
      PicaTablixInst *hi = [[PicaTablixInst alloc] init];
      hi.height = hdrH;
      hi.repeatOnNewPage = tab.repeatColumnHeaders;
      hi.cells = [NSMutableArray array];
      CGFloat hx = headerW;
      NSUInteger i = 0;
      while (i < [plan count]) {
        PicaColPlanEntry *e = plan[i];
        PicaColHeaderNode *n = t < [e.headerChain count] ? e.headerChain[t] : nil;
        CGFloat span = e.width;
        NSUInteger j = i + 1;
        while (j < [plan count]) {
          PicaColPlanEntry *e2 = plan[j];
          PicaColHeaderNode *n2 = t < [e2.headerChain count] ? e2.headerChain[t] : nil;
          if (n == nil || n2 != n)
            break;
          span += e2.width;
          j++;
        }
        if (n.item) {
          PicaTablixCellInst *c = [[PicaTablixCellInst alloc] init];
          c.xRel = hx;
          c.width = span;
          c.height = hdrH;
          c.item = n.item;
          c.colRows = n.rows ?: dataRows;
          [hi.cells addObject:c];
        }
        hx += span;
        i = j;
      }
      hi.groupRows = rows;
      [headerRows addObject:hi];
    }
    if ([headerRows count]) {
      for (PicaTablixInst *hr in headerRows)
        planHdrTotalH += hr.height;
      NSMutableArray *withHeader = [NSMutableArray arrayWithArray:headerRows];
      [withHeader addObjectsFromArray:walked];
      walked = withHeader;
    }
  }

  if (headerW > 0 && [tab.cornerRows count]) {
    NSArray *cornerRow = tab.cornerRows[0];
    if ([cornerRow count]) {
      RDLTablixCell *cc = cornerRow[0];
      PicaTablixInst *headerInst = nil;
      for (PicaTablixInst *r in walked) {
        if (r.repeatOnNewPage) {
          headerInst = r;
          break;
        }
      }
      if (headerInst == nil)
        headerInst = [walked firstObject];
      BOOL already = NO;
      for (PicaTablixCellInst *c in headerInst.cells)
        if (c.rowHeader && fabs(c.xRel) < 1e-6)
          already = YES;
      if (!already && headerInst) {
        PicaTablixCellInst *hc = [[PicaTablixCellInst alloc] init];
        hc.xRel = 0;
        hc.width = headerW;
        hc.height = MAX(headerInst.height, planHdrTotalH);
        hc.item = cc.item;
        hc.rowHeader = YES;
        NSMutableArray *cells = [NSMutableArray arrayWithObject:hc];
        [cells addObjectsFromArray:headerInst.cells];
        headerInst.cells = cells;
      }
    }
  }

  PicaApplyRowSpan(walked);

  // CanGrow: grow row instances so long cell text is not clipped.
  if (scope) {
    NSDictionary *savedRow = scope.row;
    NSArray *savedGroup = scope.groupRows;
    RDLDataSet *savedSet = scope.dataSet;
    scope.dataSet = ds ?: savedSet;
    for (PicaTablixInst *inst in walked) {
      if (inst.row)
        scope.row = inst.row;
      if (inst.groupRows)
        scope.groupRows = inst.groupRows;
      CGFloat grown = inst.height;
      for (PicaTablixCellInst *cell in inst.cells) {
        if (cell.skip || cell.rowSpan > 1 || cell.item == nil)
          continue;
        NSDictionary *cSavedRow = scope.row;
        NSArray *cSavedGroup = scope.groupRows;
        if (cell.colRows) {
          NSArray *base = inst.groupRows ?: (inst.row ? @[ inst.row ] : nil);
          NSArray *inter = PicaIntersectRows(base, cell.colRows);
          scope.groupRows = inter;
          scope.row = [inter firstObject];
        }
          CGFloat need = PicaTextboxGrownHeight((RDLTextbox *)cell.item, cell.width, scope);
        scope.row = cSavedRow;
        scope.groupRows = cSavedGroup;
        if (need > grown)
          grown = need;
      }
      if (grown > inst.height) {
        for (PicaTablixCellInst *cell in inst.cells) {
          if (!cell.skip && cell.rowSpan <= 1 && fabs(cell.height - inst.height) < 1e-6)
            cell.height = grown;
        }
        inst.height = grown;
      }
      scope.row = savedRow;
      scope.groupRows = savedGroup;
    }
    scope.dataSet = savedSet;
  }
  if (tab.keepTogether && [walked count]) {
    CGFloat total = 0;
    for (PicaTablixInst *r in walked)
      total += r.height;
    PicaTablixInst *first = walked[0];
    if (total > first.keepTogetherHeight)
      first.keepTogetherHeight = total;
  }
  if (tab.pageBreak == RDLPageBreakLocationStart && [walked count]) {
    PicaTablixInst *first0 = walked[0];
    first0.pageBreakBefore = YES;
    first0.resetPageNumber = first0.resetPageNumber || tab.resetPageNumber;
    if (tab.pageName != nil && first0.pageName == nil)
      first0.pageName = PicaAsStr(PicaEvalRow(tab.pageName, nil, scope));
  }

  CGFloat y = 0;
  for (PicaTablixInst *inst in walked) {
    inst.yRel = y;
    y += inst.height;
  }
  return PicaApplyPageRules(walked, bodyAvail, tablixTop);
}

static CGFloat PicaTablixHeight(RDLTablix *item, RDLReport *report, RDLEvalScope *scope, CGFloat bodyAvail,
                                CGFloat tablixTop) {
  NSArray *insts = PicaExpandTablix(item, report, scope, bodyAvail, tablixTop);
  if ([insts count] == 0)
    return item.height;
  PicaTablixInst *last = [insts lastObject];
  return last.yRel + last.height;
}

// Design-height delta for an item once expanded/grown (tablix rows, CanGrow text).
static CGFloat PicaGrownDelta(RDLItem *t, RDLReport *report, RDLEvalScope *scope, CGFloat bodyAvail) {
  if ([t isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tb = (RDLTablix *)t;
    CGFloat design = t.height > 0 ? t.height : (tb.headerHeight + tb.rowHeight);
    return PicaTablixHeight(tb, report, scope, bodyAvail, t.top) - design;
  }
  if ([t isKindOfClass:[RDLTextbox class]] && [(RDLTextbox *)t canGrow])
    return PicaTextboxGrownHeight((RDLTextbox *)t, t.width, scope) - t.height;
  return 0;
}

static CGFloat PicaExtraBelow(CGFloat y, NSArray<RDLItem *> *growers, RDLReport *report,
                              RDLEvalScope *scope, CGFloat bodyAvail) {
  CGFloat extra = 0;
  for (RDLTablix *t in growers) {
    if (t.top < y) {
      CGFloat grown = PicaGrownDelta(t, report, scope, bodyAvail);
      if (grown > 0)
        extra += grown;
    }
  }
  return extra;
}

+ (void)placeItem:(RDLItem *)item
          originX:(CGFloat)ox
          originY:(CGFloat)oy
            scope:(RDLEvalScope *)scope
           onPage:(RDLLaidOutPage *)page
            clipTop:(CGFloat)clipTop
         clipBottom:(CGFloat)clipBottom {
  if ([item isKindOfClass:[RDLTablix class]])
    return;
  if (PicaIsHiddenExpr(item.hidden, scope))
    return;
  CGFloat x = ox + item.left;
  CGFloat y = oy + item.top;
  CGFloat w = item.width;
  CGFloat h = item.height;
  if ([item isKindOfClass:[RDLTextbox class]] && [(RDLTextbox *)item canGrow])
    h = MAX(h, PicaTextboxGrownHeight((RDLTextbox *)item, w, scope));
  if (y + h < clipTop || y > clipBottom)
    return;
  // The laid-out class mirrors the item's; Tablix never reaches here because it
  // has already been expanded into the elements below.
  RDLLaidOutItem *li = nil;
  if ([item isKindOfClass:[RDLTextbox class]])
    li = [[RDLLaidOutTextbox alloc] init];
  else if ([item isKindOfClass:[RDLLine class]])
    li = [[RDLLaidOutLine alloc] init];
  else if ([item isKindOfClass:[RDLImage class]])
    li = [[RDLLaidOutImage alloc] init];
  else if ([item isKindOfClass:[RDLChart class]])
    li = [[RDLLaidOutChart alloc] init];
  else
    li = [[RDLLaidOutRectangle alloc] init];
  li.name = item.name;
  li.x = x;
  li.y = y;
  li.w = w;
  li.h = h;
  li.zIndex = item.zIndex;
  li.style = PicaResolveStyle(item.style, scope);
  if (item.hyperlink != nil) {
    NSString *url = [item.hyperlink evaluateTextInScope:scope];
    if ([url length])
      li.hyperlink = url;
  }
  if ([item isKindOfClass:[RDLTextbox class]]) {
    RDLTextbox *tb0 = (RDLTextbox *)item;
    RDLLaidOutTextbox *lt = (RDLLaidOutTextbox *)li;
    lt.text = [RDLExpression formatValue:[RDLExpression evaluate:tb0.value scope:scope]
                                  format:(li.style ?: item.style).format];
    if ([tb0.paragraphs count]) {
      NSMutableArray *spans = [NSMutableArray array];
      NSMutableArray *flat = [NSMutableArray array];
        for (RDLParagraph *para in tb0.paragraphs) {
        RDLParagraph *outPara = [[RDLParagraph alloc] init];
        outPara.style = para.style;
        NSMutableString *paraText = [NSMutableString string];
        for (RDLTextRun *run in para.runs) {
          RDLTextRun *outRun = [[RDLTextRun alloc] init];
          outRun.style = run.style;
          NSString *fmt = [run.style.format length] ? run.style.format
                                                    : (li.style ?: item.style).format;
          outRun.value = [RDLExpression formatValue:[RDLExpression evaluate:run.value scope:scope]
                                             format:fmt];
          [outPara.runs addObject:outRun];
          [paraText appendString:outRun.value ?: @""];
        }
        [spans addObject:outPara];
        [flat addObject:paraText];
      }
      lt.spans = spans;
      lt.text = [flat componentsJoinedByString:@"\n"];
    }
  } else if ([item isKindOfClass:[RDLImage class]]) {
    RDLImage *img0 = (RDLImage *)item;
    RDLLaidOutImage *lm = (RDLLaidOutImage *)li;
    NSString *val = [img0.value hasPrefix:@"="]
                        ? [RDLExpression evaluateText:img0.value scope:scope]
                        : img0.value;
    lm.sizing = img0.sizing != RDLImageSizingUnspecified ? img0.sizing : RDLImageSizingFit;
    if (img0.source == RDLImageSourceEmbedded) {
      RDLEmbeddedImage *img = [scope.report embeddedImageNamed:val];
      lm.imageData = img.imageData;
      lm.imageMIME = img.mimeType.length ? img.mimeType : @"image/png";
      lm.imageSrc = val;
    } else {
      lm.imageSrc = val;
    }
  } else if ([item isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)item;
    RDLLaidOutChart *lc = (RDLLaidOutChart *)li;
    lc.chartType = chart.chartType;
    lc.title = chart.title;
    RDLDataSet *ds = PicaFindSet(scope.report, chart.dataSetName);
    NSString *catField = PicaFieldOf(chart.categoryField) ?: chart.categoryField;
    NSString *valField = PicaFieldOf(chart.valueField) ?: chart.valueField;
    NSMutableArray *cats = [NSMutableArray array];
    NSMutableArray *vals = [NSMutableArray array];
    for (NSDictionary *row in ds.rows) {
      id ck = nil;
      id vk = nil;
      for (NSString *k in row) {
        if (catField && [k caseInsensitiveCompare:catField] == NSOrderedSame)
          ck = row[k];
        if (valField && [k caseInsensitiveCompare:valField] == NSOrderedSame)
          vk = row[k];
      }
      [cats addObject:ck ? [ck description] : @""];
      [vals addObject:@([vk respondsToSelector:@selector(doubleValue)] ? [vk doubleValue] : 0)];
    }
    lc.categories = cats;
    lc.values = vals;
  } else if ([item isKindOfClass:[RDLRectangle class]]) {
    [page.items addObject:li];
    for (RDLItem *child in item.childItems)
      [self placeItem:child originX:x originY:y scope:scope onPage:page clipTop:clipTop clipBottom:clipBottom];
    return;
  }
  [page.items addObject:li];
}

+ (void)placeTablixInst:(PicaTablixInst *)inst
                    tab:(RDLTablix *)tab
                     x0:(CGFloat)x0
                      y:(CGFloat)y
                  scope:(RDLEvalScope *)scope
                 onPage:(RDLLaidOutPage *)page
                clipTop:(CGFloat)clipTop
             clipBottom:(CGFloat)clipBottom
                chunkX0:(CGFloat)chunkX0
                chunkX1:(CGFloat)chunkX1
                  hLead:(CGFloat)hLead {
  if (y + inst.height < clipTop || y > clipBottom)
    return;
  NSDictionary *savedRow = scope.row;
  RDLDataSet *savedSet = scope.dataSet;
  NSArray *savedGroup = scope.groupRows;
  if (inst.row)
    scope.row = inst.row;
  scope.dataSet = PicaFindSet(scope.report, tab.dataSetName) ?: savedSet;
  if (inst.groupRows)
    scope.groupRows = inst.groupRows;
  for (PicaTablixCellInst *cell in inst.cells) {
    if (cell.skip)
      continue;
    RDLItem *contents = cell.item;
    if (contents == nil)
      continue;
    CGFloat cellX = cell.xRel;
    CGFloat cellW = cell.width;
    if (chunkX1 > 0) {
      if (cell.rowHeader) {
        // Row headers/corner: shown on the first chunk, and repeated on later
        // chunks only when RepeatRowHeaders reserved room for them.
        if (chunkX0 > 1e-6 && hLead <= 0)
          continue;
      } else {
        CGFloat s = MAX(cellX, chunkX0);
        CGFloat e = MIN(cellX + cellW, chunkX1);
        if (e - s <= 1e-6)
          continue;
        cellX = hLead + (s - chunkX0);
        cellW = e - s;
      }
    }
    NSDictionary *cellSavedRow = scope.row;
    NSArray *cellSavedGroup = scope.groupRows;
    if (cell.colRows) {
      NSArray *base = inst.groupRows ?: (inst.row ? @[ inst.row ] : nil);
      NSArray *inter = PicaIntersectRows(base, cell.colRows);
      scope.groupRows = inter;
      scope.row = [inter firstObject];
    }
    CGFloat savedL = contents.left, savedT = contents.top, savedW = contents.width, savedH = contents.height;
    contents.left = 0;
    contents.top = 0;
    contents.width = cellW;
    contents.height = cell.height > 0 ? cell.height : inst.height;
    [self placeItem:contents
            originX:(x0 + cellX)
            originY:y
              scope:scope
             onPage:page
            clipTop:clipTop
         clipBottom:clipBottom];
    contents.left = savedL;
    contents.top = savedT;
    contents.width = savedW;
    contents.height = savedH;
    scope.row = cellSavedRow;
    scope.groupRows = cellSavedGroup;
  }
  scope.row = savedRow;
  scope.dataSet = savedSet;
  scope.groupRows = savedGroup;
}

// Horizontal pagination: compute column chunks for a tablix wider than the
// available page width. Returns nil when the tablix fits. Each chunk is
// {x0, x1} in tablix-relative units; chunks after the first reserve room for
// repeated row headers (width headerW) when RepeatRowHeaders is set.
static NSArray<NSDictionary *> *PicaHChunks(NSArray<PicaTablixInst *> *insts, CGFloat headerW,
                                            BOOL repeatRowHeaders, CGFloat availW) {
  if (availW <= 0.01)
    return nil;
  CGFloat totalW = 0;
  NSMutableSet *edgeSet = [NSMutableSet set];
  for (PicaTablixInst *r in insts) {
    for (PicaTablixCellInst *c in r.cells) {
      if (c.skip)
        continue;
      CGFloat end = c.xRel + c.width;
      if (end > totalW)
        totalW = end;
      if (c.xRel > headerW + 1e-6)
        [edgeSet addObject:@(round(c.xRel * 1000) / 1000)];
    }
  }
  if (totalW <= availW + 0.01)
    return nil;
  NSMutableArray *edges = [[edgeSet allObjects] mutableCopy];
  [edges sortUsingSelector:@selector(compare:)];
  [edges addObject:@(totalW)];
  NSMutableArray *chunks = [NSMutableArray array];
  CGFloat x0 = 0;
  CGFloat lead = 0;
  NSUInteger i = 0;
  while (x0 < totalW - 1e-6 && [chunks count] < 200) {
    CGFloat cap = availW - lead;
    CGFloat x1 = x0;
    while (i < [edges count]) {
      CGFloat e = [edges[i] doubleValue];
      if (e <= x0 + 1e-6) {
        i++;
        continue;
      }
      if (e - x0 > cap + 0.01)
        break;
      x1 = e;
      i++;
    }
    if (x1 <= x0 + 1e-6) {
      // A single column wider than the page: advance to the next edge anyway.
      x1 = i < [edges count] ? [edges[i] doubleValue] : totalW;
      if (i < [edges count])
        i++;
    }
    [chunks addObject:@{ @"x0" : @(x0), @"x1" : @(x1) }];
    x0 = x1;
    lead = repeatRowHeaders ? headerW : 0;
  }
  return [chunks count] > 1 ? chunks : nil;
}

+ (void)placeTablix:(RDLItem *)item
            originX:(CGFloat)ox
          tablixTop:(CGFloat)tablixTop
            sliceTop:(CGFloat)sliceTop
           bodyTop:(CGFloat)bodyTop
        bodyBottom:(CGFloat)bodyBottom
             scope:(RDLEvalScope *)scope
            onPage:(RDLLaidOutPage *)page
         firstPage:(BOOL)firstPage
           chunkX0:(CGFloat)chunkX0
           chunkX1:(CGFloat)chunkX1
             hLead:(CGFloat)hLead {
  CGFloat bodyAvail = bodyBottom - bodyTop;
  NSArray *insts = PicaExpandTablix((RDLTablix *)item, scope.report, scope, bodyAvail, tablixTop);
  CGFloat x0 = ox + item.left;
  CGFloat sliceBot = sliceTop + bodyAvail;
  CGFloat repeatH = 0;
  if (!firstPage) {
    for (PicaTablixInst *r in insts) {
      if (r.repeatOnNewPage)
        repeatH += r.height;
    }
  }
  BOOL any = NO;
  for (PicaTablixInst *r in insts) {
    CGFloat absY = tablixTop + r.yRel;
    if (absY + r.height <= sliceTop || absY >= sliceBot)
      continue;
    any = YES;
    break;
  }
  if (!any)
    return;

  NSDictionary *savedPrev = scope.previousRow;
  if (!firstPage && repeatH > 0) {
    CGFloat hy = bodyTop;
    for (PicaTablixInst *r in insts) {
      if (!r.repeatOnNewPage)
        continue;
      [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:hy scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom
                     chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
      hy += r.height;
    }
  }
  NSDictionary *prev = savedPrev;
  for (PicaTablixInst *r in insts) {
    if (!firstPage && r.repeatOnNewPage) {
      if (r.row)
        prev = r.row;
      continue;
    }
    CGFloat absY = tablixTop + r.yRel;
    if (absY + r.height <= sliceTop || absY >= sliceBot) {
      if (r.row)
        prev = r.row;
      continue;
    }
    CGFloat pageY = bodyTop + (absY - sliceTop) + (firstPage ? 0 : repeatH);
    scope.previousRow = prev;
    [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:pageY scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom
                   chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
    if (r.row)
      prev = r.row;
  }
  scope.previousRow = savedPrev;
}

// Page-break shift for a body item positioned at y0 with height h. `PageBreak
// Start` moves the item to the next slice boundary; `KeepTogether` avoids
// straddling a boundary when the item fits in one slice.
static CGFloat PicaBodyItemShift(RDLItem *item, CGFloat y0, CGFloat h, CGFloat bodyAvail) {
  if (bodyAvail <= 0)
    return 0;
  CGFloat into = fmod(y0, bodyAvail);
  if (into < 0)
    into += bodyAvail;
  if (into <= 0.0001)
    return 0;
  BOOL breakStart =
      item.pageBreak == RDLPageBreakLocationStart || item.pageBreak == RDLPageBreakLocationStartAndEnd;
  if (breakStart && y0 > 0.0001)
    return bodyAvail - into;
  if (item.keepTogether && h <= bodyAvail + 0.001 && h > (bodyAvail - into) + 0.001)
    return bodyAvail - into;
  return 0;
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params {
  CGFloat mx = report.page.leftMargin;
  CGFloat my = report.page.topMargin;
  CGFloat headerH = report.pageHeader.height;
  CGFloat footerH = report.pageFooter.height;
  CGFloat bodyTop = my + headerH;
  CGFloat bodyBottom = report.page.pageHeight - report.page.bottomMargin - footerH;
  CGFloat bodyAvail = bodyBottom - bodyTop;
  if (bodyAvail < 0.5)
    bodyAvail = 0.5;

  // Measuring scope: used for dataset filters, expansion and growth estimates.
  RDLEvalScope *measure = [[RDLEvalScope alloc] init];
  measure.report = report;
  measure.executionTime = [NSDate date];
  measure.paramValues = params ?: @{};
  if ([report.dataSets count])
    measure.dataSet = report.dataSets[0];

  // Dataset-level filters apply to every consumer (details and aggregates).
  // Filter into locals; the report model's rows are restored before returning.
  NSMapTable *savedRows = [NSMapTable strongToStrongObjectsMapTable];
  for (RDLDataSet *ds in report.dataSets) {
    if ([ds.filters count] && [ds.rows count]) {
      RDLDataSet *saved = measure.dataSet;
      measure.dataSet = ds;
      [savedRows setObject:ds.rows forKey:ds];
      ds.rows = PicaApplyFilters(ds.rows, ds.filters, measure);
      measure.dataSet = saved;
    }
  }

  NSMutableArray *tablixes = [NSMutableArray array];
  NSMutableArray *growers = [NSMutableArray array];
  for (RDLItem *it in report.body.items) {
    if ([it isKindOfClass:[RDLTablix class]]) {
      [tablixes addObject:it];
      [growers addObject:it];
    } else if ([it isKindOfClass:[RDLTextbox class]] && [(RDLTextbox *)it canGrow]) {
      [growers addObject:it];
    }
  }

  CGFloat expanded = 0;
  for (RDLItem *it in report.body.items) {
    if ([it isKindOfClass:[RDLTablix class]]) {
      expanded = MAX(expanded,
                     it.top + PicaTablixHeight((RDLTablix *)it, report, measure, bodyAvail, it.top));
    } else {
      CGFloat gh = it.height + MAX(PicaGrownDelta(it, report, measure, bodyAvail), 0);
      CGFloat y0 = it.top + PicaExtraBelow(it.top, growers, report, measure, bodyAvail);
      y0 += PicaBodyItemShift(it, y0, gh, bodyAvail);
      expanded = MAX(expanded, y0 + gh);
    }
  }
  CGFloat bodyNeeded = MAX(report.body.height, expanded);
  NSInteger vTotal = (NSInteger)MAX(1, (NSInteger)ceil(bodyNeeded / bodyAvail));

  // Horizontal pagination: tablixes wider than the page split into column
  // chunks; extra pages are emitted to the right of each vertical slice.
  NSMapTable *chunkMap = [NSMapTable strongToStrongObjectsMapTable];
  NSInteger maxChunks = 1;
  for (RDLTablix *t in tablixes) {
    CGFloat tTop = t.top + PicaExtraBelow(t.top, growers, report, measure, bodyAvail);
    NSArray *tInsts = PicaExpandTablix(t, report, measure, bodyAvail, tTop);
    CGFloat availW = report.page.pageWidth - report.page.rightMargin - (mx + t.left);
    CGFloat hw = PicaHeaderWidth(t.rowHierarchy.members);
    NSArray *chunks = PicaHChunks(tInsts, hw, t.repeatRowHeaders, availW);
    if (chunks) {
      [chunkMap setObject:@{ @"chunks" : chunks, @"headerW" : @(hw) } forKey:t];
      maxChunks = MAX(maxChunks, (NSInteger)[chunks count]);
    }
  }
  NSInteger total = vTotal * maxChunks;

  // ResetPageNumber/PageName: collect slice indices where a section starts or
  // a page name changes (from body items and tablix group breaks).
  NSMutableArray<NSDictionary *> *marks = [NSMutableArray array];
  for (RDLItem *it in report.body.items) {
    if ([it isKindOfClass:[RDLTablix class]]) {
      CGFloat tTop = it.top + PicaExtraBelow(it.top, growers, report, measure, bodyAvail);
        NSArray *insts = PicaExpandTablix((RDLTablix *)it, report, measure, bodyAvail, tTop);
      for (PicaTablixInst *inst in insts) {
        if (!inst.resetPageNumber && [inst.pageName length] == 0)
          continue;
        NSInteger slice = (NSInteger)floor((tTop + inst.yRel) / bodyAvail + 0.0001);
        [marks addObject:@{
          @"slice" : @(slice),
          @"reset" : @(inst.resetPageNumber),
          @"name" : inst.pageName ?: @""
        }];
      }
    } else if (it.resetPageNumber || it.pageName != nil) {
      CGFloat gh = it.height + MAX(PicaGrownDelta(it, report, measure, bodyAvail), 0);
      CGFloat y0 = it.top + PicaExtraBelow(it.top, growers, report, measure, bodyAvail);
      y0 += PicaBodyItemShift(it, y0, gh, bodyAvail);
      NSInteger slice = (NSInteger)floor(y0 / bodyAvail + 0.0001);
      [marks addObject:@{
        @"slice" : @(slice),
        @"reset" : @(it.resetPageNumber),
        @"name" : it.pageName ?: @""
      }];
    }
  }
  [marks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    return [a[@"slice"] compare:b[@"slice"]];
  }];

  // Body background painted behind every page's body area when Body has Style.
  RDLItem *bodyBG = nil;
  if (report.body.style &&
      ([report.body.style.backgroundColor length] ||
       (report.body.style.border && report.body.style.border.style != RDLBorderStyleNone))) {
    bodyBG = [[RDLItem alloc] init];
      bodyBG.name = @"__BodyBackground";
    bodyBG.left = 0;
    bodyBG.top = 0;
    bodyBG.width = report.width > 0 ? report.width
                                    : report.page.pageWidth - mx - report.page.rightMargin;
    bodyBG.height = bodyAvail;
    bodyBG.zIndex = NSIntegerMin;
    bodyBG.style = report.body.style;
  }

  NSMutableArray *pages = [NSMutableArray array];
  for (NSInteger p = 1; p <= total; p++) {
    NSInteger sliceIdx = (p - 1) / maxChunks;
    NSInteger chunkIdx = (p - 1) % maxChunks;
    NSInteger sectStart = 0;
    NSInteger nextSect = vTotal;
    NSString *pname = nil;
    for (NSDictionary *mk in marks) {
      NSInteger s = [mk[@"slice"] integerValue];
      BOOL rst = [mk[@"reset"] boolValue];
      if (rst && s <= sliceIdx && s > sectStart)
        sectStart = s;
      if (rst && s > sliceIdx && s < nextSect)
        nextSect = s;
      if (s <= sliceIdx && [mk[@"name"] length])
        pname = mk[@"name"];
    }

    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.report = report;
    scope.pageNumber = (sliceIdx - sectStart) * maxChunks + chunkIdx + 1;
    scope.totalPages = (nextSect - sectStart) * maxChunks;
    scope.overallPageNumber = p;
    scope.overallTotalPages = total;
    scope.pageName = pname;
    scope.executionTime = [NSDate date];
    scope.paramValues = params ?: @{};
    if ([report.dataSets count])
      scope.dataSet = report.dataSets[0];

    RDLLaidOutPage *page = [[RDLLaidOutPage alloc] init];
    page.index = p;
    page.width = report.page.pageWidth;
    page.height = report.page.pageHeight;

    BOOL showHeader = (p == 1 && report.pageHeader.printOnFirstPage) ||
                      (p == total && report.pageHeader.printOnLastPage) || (p != 1 && p != total);
    BOOL showFooter = (p == 1 && report.pageFooter.printOnFirstPage) ||
                      (p == total && report.pageFooter.printOnLastPage) || (p != 1 && p != total);
    if (p == 1 && p == total) {
      showHeader = report.pageHeader.printOnFirstPage;
      showFooter = report.pageFooter.printOnFirstPage;
    }
    if (showHeader) {
      for (RDLItem *it in report.pageHeader.items)
        [self placeItem:it originX:mx originY:my scope:scope onPage:page clipTop:0 clipBottom:report.page.pageHeight];
    }
    if (showFooter) {
      CGFloat fy = report.page.pageHeight - report.page.bottomMargin - footerH;
      for (RDLItem *it in report.pageFooter.items)
        [self placeItem:it originX:mx originY:fy scope:scope onPage:page clipTop:0 clipBottom:report.page.pageHeight];
    }

    CGFloat sliceTop = (CGFloat)sliceIdx * bodyAvail;
    if (bodyBG)
      [self placeItem:bodyBG originX:mx originY:bodyTop scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom];
    for (RDLItem *item in report.body.items) {
      if ([item isKindOfClass:[RDLTablix class]])
        continue;
      if (chunkIdx != 0)
        continue;
      CGFloat dy = PicaExtraBelow(item.top, growers, report, measure, bodyAvail);
        CGFloat grownH =
            item.height + MAX(PicaGrownDelta(item, report, measure, bodyAvail), 0);
      CGFloat y0 = item.top + dy;
      dy += PicaBodyItemShift(item, y0, grownH, bodyAvail);
      y0 = item.top + dy;
      CGFloat y1 = y0 + grownH;
      if (y1 <= sliceTop || y0 >= sliceTop + bodyAvail)
        continue;
      CGFloat saved = item.top;
      item.top = item.top + dy;
      [self placeItem:item
              originX:mx
              originY:(bodyTop - sliceTop)
                scope:scope
               onPage:page
              clipTop:bodyTop
           clipBottom:bodyBottom];
      item.top = saved;
    }
    for (RDLTablix *t in tablixes) {
      CGFloat tTop = t.top + PicaExtraBelow(t.top, growers, report, measure, bodyAvail);
      CGFloat tBot = tTop + PicaTablixHeight(t, report, measure, bodyAvail, tTop);
      if (tBot <= sliceTop || tTop >= sliceTop + bodyAvail)
        continue;
      CGFloat cx0 = 0, cx1 = 0, lead = 0;
      NSDictionary *ci = [chunkMap objectForKey:t];
      if (ci) {
        NSArray *chunks = ci[@"chunks"];
        if (chunkIdx >= (NSInteger)[chunks count])
          continue;
        cx0 = [chunks[(NSUInteger)chunkIdx][@"x0"] doubleValue];
        cx1 = [chunks[(NSUInteger)chunkIdx][@"x1"] doubleValue];
        if (chunkIdx > 0 && t.repeatRowHeaders)
          lead = [ci[@"headerW"] doubleValue];
      } else if (chunkIdx != 0) {
        continue;
      }
      BOOL first = (tTop >= sliceTop);
      [self placeTablix:t
                originX:mx
              tablixTop:tTop
               sliceTop:sliceTop
                bodyTop:bodyTop
             bodyBottom:bodyBottom
                  scope:scope
                 onPage:page
              firstPage:first
                chunkX0:cx0
                chunkX1:cx1
                  hLead:lead];
    }

    BOOL anyZ = NO;
    for (RDLLaidOutItem *li in page.items) {
      if (li.zIndex != 0) {
        anyZ = YES;
        break;
      }
    }
    if (anyZ) {
      [page.items sortWithOptions:NSSortStable
                  usingComparator:^NSComparisonResult(RDLLaidOutItem *a, RDLLaidOutItem *b) {
                    if (a.zIndex < b.zIndex)
                      return NSOrderedAscending;
                    if (a.zIndex > b.zIndex)
                      return NSOrderedDescending;
                    return NSOrderedSame;
                  }];
    }
    [pages addObject:page];
  }
  for (RDLDataSet *ds in savedRows)
    ds.rows = [savedRows objectForKey:ds];
  return pages;
}

@end
