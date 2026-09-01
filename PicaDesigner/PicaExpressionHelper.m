#import "PicaExpressionHelper.h"
#import "PicaController.h"

static NSArray<NSString *> *PicaFunctionNames(void) {
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

static NSArray<NSString *> *PicaGlobalsMembers(void) {
  return @[
    @"PageNumber", @"TotalPages", @"OverallPageNumber", @"OverallTotalPages",
    @"PageName", @"ExecutionTime", @"ReportName"
  ];
}

static NSArray<NSString *> *PicaUserMembers(void) {
  return @[ @"UserID", @"Language" ];
}

static NSArray<NSString *> *PicaFieldNames(NSString *dataSetName) {
  RDLReport *r = [PicaController sharedController].report;
  RDLDataSet *ds = nil;
  for (RDLDataSet *d in r.dataSets)
    if ([d.name isEqualToString:dataSetName])
      ds = d;
  if (ds == nil)
    ds = r.dataSets.firstObject;
  NSMutableArray *names = [NSMutableArray array];
  for (id f in ds.fields) {
    if ([f isKindOfClass:[RDLField class]])
      [names addObject:((RDLField *)f).name ?: @""];
    else
      [names addObject:[f description]];
  }
  return names;
}

static NSArray<NSString *> *PicaParameterNames(void) {
  RDLReport *r = [PicaController sharedController].report;
  NSMutableArray *names = [NSMutableArray array];
  for (RDLParameter *p in r.parameters)
    if ([p.name length])
      [names addObject:p.name];
  return names;
}

// The collection identifier ending right before `loc` (e.g. "Fields" for
// "…=Fields!"), or nil when the caret is not after a `!` accessor.
static NSString *PicaCollectionBefore(NSString *text, NSUInteger loc) {
  if (loc == 0 || loc > [text length] || [text characterAtIndex:loc - 1] != '!')
    return nil;
  NSInteger start = (NSInteger)loc - 2;
  while (start >= 0) {
    unichar c = [text characterAtIndex:(NSUInteger)start];
    if (!isalnum(c) && c != '_')
      break;
    start--;
  }
  return [text substringWithRange:NSMakeRange((NSUInteger)start + 1, loc - 1 - (NSUInteger)start - 1)];
}

NSArray<NSString *> *PicaExpressionCompletions(NSString *text, NSRange charRange,
                                               NSString *dataSetName) {
  if (text == nil)
    return @[];
  NSString *partial = charRange.location + charRange.length <= [text length]
                          ? [text substringWithRange:charRange]
                          : @"";
  NSString *coll = PicaCollectionBefore(text, charRange.location);
  NSArray *pool;
  BOOL memberContext = YES;
  if ([coll isEqualToString:@"Fields"]) {
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *f in PicaFieldNames(dataSetName))
      [m addObject:[f stringByAppendingString:@".Value"]];
    pool = m;
  } else if ([coll isEqualToString:@"Parameters"]) {
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *p in PicaParameterNames())
      [m addObject:[p stringByAppendingString:@".Value"]];
    pool = m;
  } else if ([coll isEqualToString:@"Globals"]) {
    pool = PicaGlobalsMembers();
  } else if ([coll isEqualToString:@"User"]) {
    pool = PicaUserMembers();
  } else {
    memberContext = NO;
    NSMutableArray *m =
        [NSMutableArray arrayWithObjects:@"Fields!", @"Parameters!", @"Globals!", @"User!", nil];
    [m addObjectsFromArray:PicaFunctionNames()];
    pool = m;
  }
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *cand in pool) {
    if ([partial length] == 0 ||
        [cand rangeOfString:partial options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == 0)
      [out addObject:cand];
  }
  // Outside a member context an empty partial word would list everything;
  // that is only helpful right after `!`, so require a prefix elsewhere.
  if (!memberContext && [partial length] == 0)
    return @[];
  return out;
}

BOOL PicaShouldAutoComplete(NSString *text, NSRange selectedRange) {
  if (![text hasPrefix:@"="])
    return NO;
  NSUInteger loc = selectedRange.location;
  if (loc == 0 || loc > [text length])
    return NO;
  return [text characterAtIndex:loc - 1] == '!';
}
