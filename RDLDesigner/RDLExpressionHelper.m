#import "RDLExpressionHelper.h"
#import <ctype.h>

NSArray<NSString *> *RDLExpressionFunctionNames(void) {
  static NSArray *names;
  if (names == nil) {
    names = @[
      @"Sum", @"Avg", @"Min", @"Max", @"Count", @"CountDistinct", @"CountRows",
      @"First", @"Last", @"StDev", @"StDevP", @"Var", @"VarP", @"Aggregate",
      @"RunningValue", @"Lookup", @"LookupSet", @"MultiLookup", @"IIf",
      @"Switch", @"Choose", @"Format", @"FormatCurrency", @"FormatNumber",
      @"FormatPercent", @"FormatDateTime", @"CStr", @"CInt", @"CDbl", @"CDate",
      @"CBool", @"Len", @"Left", @"Right", @"Mid", @"Trim", @"LTrim", @"RTrim",
      @"UCase", @"LCase", @"Replace", @"InStr", @"InStrRev", @"Join", @"Split",
      @"Abs", @"Ceiling", @"Floor", @"Round", @"Sqrt", @"Pow", @"Exp", @"Log",
      @"Int", @"Fix", @"Mod", @"Today", @"Now", @"Year", @"Month", @"Day",
      @"Hour", @"Minute", @"Second", @"Weekday", @"MonthName", @"WeekdayName",
      @"DateAdd", @"DateDiff", @"DatePart", @"DateSerial", @"DateValue",
      @"IsNothing", @"IsNumeric", @"IsDate", @"Level", @"RowNumber", @"Previous",
      @"True", @"False", @"Nothing", @"And", @"Or", @"Not", @"Like"
    ];
  }
  return names;
}

static NSArray<NSString *> *RDLGlobalsMembers(void) {
  return @[
    @"PageNumber", @"TotalPages", @"OverallPageNumber", @"OverallTotalPages",
    @"PageName", @"ExecutionTime", @"ReportName"
  ];
}

static NSArray<NSString *> *RDLUserMembers(void) {
  return @[ @"UserID", @"Language" ];
}

@implementation RDLExpressionScope

+ (instancetype)scopeWithFieldNames:(NSArray<NSString *> *)fieldNames
                     parameterNames:(NSArray<NSString *> *)parameterNames {
  RDLExpressionScope *s = [[RDLExpressionScope alloc] init];
  s->_fieldNames = [fieldNames copy] ?: @[];
  s->_parameterNames = [parameterNames copy] ?: @[];
  return s;
}

+ (instancetype)scopeWithReport:(RDLReport *)report dataSetName:(NSString *)dataSetName {
  RDLDataSet *ds = nil;
  for (RDLDataSet *d in report.dataSets) {
    if ([d.name isEqualToString:dataSetName])
      ds = d;
  }
  // An unnamed or unknown dataset falls back to the report's first, which is
  // what a single-dataset report always wants.
  if (ds == nil)
    ds = report.dataSets.firstObject;
  NSMutableArray *fields = [NSMutableArray array];
  for (id f in ds.fields) {
    if ([f isKindOfClass:[RDLField class]]) {
      if ([((RDLField *)f).name length])
        [fields addObject:((RDLField *)f).name];
    } else if (f != nil) {
      [fields addObject:[f description]];
    }
  }
  NSMutableArray *params = [NSMutableArray array];
  for (RDLParameter *p in report.parameters) {
    if ([p.name length])
      [params addObject:p.name];
  }
  return [self scopeWithFieldNames:fields parameterNames:params];
}

@end

// The collection identifier ending right before `loc` (e.g. "Fields" for
// "…=Fields!"), or nil when the caret is not after a `!` accessor.
static NSString *RDLCollectionBefore(NSString *text, NSUInteger loc) {
  if (loc == 0 || loc > [text length] || [text characterAtIndex:loc - 1] != '!')
    return nil;
  NSInteger start = (NSInteger)loc - 2;
  while (start >= 0) {
    unichar c = [text characterAtIndex:(NSUInteger)start];
    if (!isalnum(c) && c != '_')
      break;
    start--;
  }
  return [text substringWithRange:NSMakeRange((NSUInteger)start + 1,
                                              loc - 1 - (NSUInteger)start - 1)];
}

NSArray<NSString *> *RDLExpressionCompletions(NSString *text, NSRange charRange,
                                              RDLExpressionScope *scope) {
  if (text == nil)
    return @[];
  NSString *partial = charRange.location + charRange.length <= [text length]
                          ? [text substringWithRange:charRange]
                          : @"";
  // With the expression field editor the range covers the whole `Coll!member`
  // accessor, so completions must carry the `Coll!` prefix back.
  NSRange bang = [partial rangeOfString:@"!" options:NSBackwardsSearch];
  NSString *replacePrefix = @"";
  if (bang.location != NSNotFound) {
    replacePrefix = [partial substringToIndex:NSMaxRange(bang)];
    partial = [partial substringFromIndex:NSMaxRange(bang)];
    charRange = NSMakeRange(charRange.location + NSMaxRange(bang), [partial length]);
  }
  NSString *coll = RDLCollectionBefore(text, charRange.location);
  NSArray *pool;
  BOOL memberContext = YES;
  if ([coll isEqualToString:@"Fields"]) {
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *f in scope.fieldNames)
      [m addObject:[f stringByAppendingString:@".Value"]];
    pool = m;
  } else if ([coll isEqualToString:@"Parameters"]) {
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *p in scope.parameterNames)
      [m addObject:[p stringByAppendingString:@".Value"]];
    pool = m;
  } else if ([coll isEqualToString:@"Globals"]) {
    pool = RDLGlobalsMembers();
  } else if ([coll isEqualToString:@"User"]) {
    pool = RDLUserMembers();
  } else {
    memberContext = NO;
    NSMutableArray *m =
        [NSMutableArray arrayWithObjects:@"Fields!", @"Parameters!", @"Globals!", @"User!", nil];
    [m addObjectsFromArray:RDLExpressionFunctionNames()];
    pool = m;
  }
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *cand in pool) {
    if ([partial length] == 0 ||
        [cand rangeOfString:partial
                    options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == 0)
      [out addObject:cand];
  }
  // Outside a member context an empty partial word would list the entire
  // vocabulary; that is only useful right after `!`.
  if (!memberContext && [partial length] == 0)
    return @[];
  if ([replacePrefix length]) {
    NSMutableArray *prefixed = [NSMutableArray arrayWithCapacity:[out count]];
    for (NSString *cand in out)
      [prefixed addObject:[replacePrefix stringByAppendingString:cand]];
    return prefixed;
  }
  return out;
}

BOOL RDLShouldAutoComplete(NSString *text, NSRange selectedRange) {
  if (![text hasPrefix:@"="])
    return NO;
  NSUInteger loc = selectedRange.location;
  if (loc == 0 || loc > [text length])
    return NO;
  if ([text characterAtIndex:loc - 1] == '!')
    return YES;
  // Keep the list up while a member prefix is being typed (`Fields!Na`).
  NSInteger i = (NSInteger)loc - 1;
  while (i >= 0) {
    unichar c = [text characterAtIndex:(NSUInteger)i];
    if (c == '!')
      return YES;
    if (!isalnum(c) && c != '_' && c != '.')
      break;
    i--;
  }
  return NO;
}

NSRange RDLExpressionCompletionRange(NSString *text, NSUInteger caret) {
  if (![text hasPrefix:@"="] || caret > [text length])
    return NSMakeRange(NSNotFound, 0);
  NSInteger start = (NSInteger)caret - 1;
  while (start >= 0) {
    unichar c = [text characterAtIndex:(NSUInteger)start];
    if (!isalnum(c) && c != '_' && c != '.')
      break;
    start--;
  }
  // A leading `Coll!` accessor joins the range so it is never empty right
  // after the `!`.
  if (start >= 0 && [text characterAtIndex:(NSUInteger)start] == '!') {
    start--;
    while (start >= 0) {
      unichar c = [text characterAtIndex:(NSUInteger)start];
      if (!isalnum(c) && c != '_')
        break;
      start--;
    }
  }
  NSUInteger loc = (NSUInteger)(start + 1);
  if (loc >= caret)
    return NSMakeRange(NSNotFound, 0);
  return NSMakeRange(loc, caret - loc);
}

BOOL RDLIsTypingEvent(void) {
  NSEvent *ev = [NSApp currentEvent];
  if (ev == nil || [ev type] != NSKeyDown)
    return NO;
  NSString *chars = [ev characters];
  if ([chars length] == 0)
    return NO;
  unichar c = [chars characterAtIndex:0];
  if (c == 0x7f || c == '\b' || c == 27) // delete, backspace, escape
    return NO;
  if (c >= 0xF700 && c <= 0xF8FF) // function/arrow keys
    return NO;
  return YES;
}

@implementation RDLExpressionFieldEditor {
  NSUndoManager *_typingUndoManager;
}

// Never the window's (see the header): that one belongs to the document.
- (NSUndoManager *)undoManager {
  if (_typingUndoManager == nil)
    _typingUndoManager = [[NSUndoManager alloc] init];
  return _typingUndoManager;
}

- (void)resetTypingUndo {
  [_typingUndoManager removeAllActions];
}

- (NSRange)rangeForUserCompletion {
  NSRange r = RDLExpressionCompletionRange([self string], [self selectedRange].location);
  if (r.location != NSNotFound)
    return r;
  return [super rangeForUserCompletion];
}

@end
