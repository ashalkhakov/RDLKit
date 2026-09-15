/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataProvider.h"
#import "RDLDataProviderInternal.h"
#import "RDLExpression.h"
// The binder hands out the three the kit implements unless a host replaces them.
#import "RDLCSVDataProvider.h"
#import "RDLJSONDataProvider.h"
#import "RDLXMLDataProvider.h"
#import "RDLCompatibility.h"

static NSString *const kRDLDataErrorDomain = @"RDLKit";

NSError *RDLDataError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:kRDLDataErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message ?: @"data source error"}];
}

RDLDataProviderKind RDLDataProviderKindFromString(NSString *name) {
  NSString *n = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
      lowercaseString];
  if ([n isEqualToString:@"json"])
    return RDLDataProviderKindJSON;
  if ([n isEqualToString:@"xml"])
    return RDLDataProviderKindXML;
  if ([n isEqualToString:@"csv"] || [n isEqualToString:@"text"])
    return RDLDataProviderKindCSV;
  return RDLDataProviderKindUnspecified;
}

NSString *RDLStringFromDataProviderKind(RDLDataProviderKind kind) {
  switch (kind) {
    case RDLDataProviderKindJSON:
      return @"JSON";
    case RDLDataProviderKindXML:
      return @"XML";
    case RDLDataProviderKindCSV:
      return @"CSV";
    case RDLDataProviderKindUnspecified:
      break;
  }
  return @"";
}

// A quoted value starting at `*at`: up to its closing quote, a doubled quote
// being one of it. `*at` ends past the closing quote.
static NSString *RDLConnectionQuoted(NSString *text, NSUInteger *at) {
  NSString *quote = [text substringWithRange:NSMakeRange(*at, 1)];
  NSMutableString *out = [NSMutableString string];
  NSUInteger i = *at + 1, n = [text length];
  while (i < n) {
    NSRange next = [text rangeOfString:quote options:0 range:NSMakeRange(i, n - i)];
    if (next.location == NSNotFound) {
      [out appendString:[text substringFromIndex:i]];
      i = n;
      break;
    }
    [out appendString:[text substringWithRange:NSMakeRange(i, next.location - i)]];
    i = next.location + 1;
    if (i < n && [text characterAtIndex:i] == [quote characterAtIndex:0]) {
      [out appendString:quote];
      i += 1;
      continue;
    }
    break;
  }
  *at = i;
  return out;
}

static BOOL RDLIsQuote(unichar c) {
  return c == '"' || c == '\'';
}

NSDictionary<NSString *, NSString *> *RDLConnectionProperties(NSString *connectString) {
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSString *text = connectString ?: @"";
  NSUInteger n = [text length], i = 0;
  while (i < n) {
    unichar c = [text characterAtIndex:i];
    if ([space characterIsMember:c] || c == ';') {
      i += 1;
      continue;
    }
    // A bare token is the document: "data.csv;HasHeaders=true" names its file
    // that way, and so does a path someone pasted in whole -- quoted, when it
    // holds a ";".
    if (RDLIsQuote(c)) {
      NSString *document = RDLConnectionQuoted(text, &i);
      while (i < n && [text characterAtIndex:i] != ';')
        i += 1;
      if (out[@""] == nil)
        out[@""] = document;
      continue;
    }
    NSMutableString *key = [NSMutableString string];
    BOOL paired = NO;
    while (i < n) {
      unichar k = [text characterAtIndex:i];
      if (k == ';')
        break;
      if (k == '=') {
        if (i + 1 < n && [text characterAtIndex:i + 1] == '=') {
          [key appendString:@"="];
          i += 2;
          continue;
        }
        paired = YES;
        i += 1;
        break;
      }
      [key appendFormat:@"%C", k];
      i += 1;
    }
    NSString *name = [key stringByTrimmingCharactersInSet:space];
    if (!paired) {
      if ([name length] && out[@""] == nil)
        out[@""] = name;
      continue;
    }
    while (i < n && [space characterIsMember:[text characterAtIndex:i]] && [text characterAtIndex:i] != ';')
      i += 1;
    NSString *value = nil;
    if (i < n && RDLIsQuote([text characterAtIndex:i])) {
      value = RDLConnectionQuoted(text, &i);
      while (i < n && [text characterAtIndex:i] != ';')
        i += 1;
    } else {
      NSUInteger start = i;
      while (i < n && [text characterAtIndex:i] != ';')
        i += 1;
      value = [[text substringWithRange:NSMakeRange(start, i - start)] stringByTrimmingCharactersInSet:space];
    }
    if ([name length])
      out[[name lowercaseString]] = value;
  }
  return out;
}

// A value as DbConnectionStringBuilder writes it: as it is, unless it holds a
// ";" or a control character, or starts or ends with a space or a quote.
static NSString *RDLConnectionValue(NSString *value) {
  NSUInteger n = [value length];
  if (n == 0)
    return value;
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  unichar first = [value characterAtIndex:0], last = [value characterAtIndex:n - 1];
  BOOL quoted = [value rangeOfString:@";"].location != NSNotFound ||
                [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound ||
                [space characterIsMember:first] || [space characterIsMember:last] || RDLIsQuote(first) ||
                RDLIsQuote(last);
  if (!quoted)
    return value;
  if ([value rangeOfString:@"\""].location != NSNotFound && [value rangeOfString:@"'"].location == NSNotFound)
    return [NSString stringWithFormat:@"'%@'", value];
  return [NSString stringWithFormat:@"\"%@\"", [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

NSString *RDLConnectionString(NSDictionary<NSString *, NSString *> *properties) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSString *document = properties[@""];
  if ([document length])
    [parts addObject:RDLConnectionValue(document)];
  // Everything else in name order, so the same settings always write the same
  // line and a saved report does not churn.
  for (NSString *key in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([key length] == 0)
      continue;
    NSString *value = properties[key];
    if ([value length] == 0)
      continue;
    [parts addObject:[NSString stringWithFormat:@"%@=%@", [key stringByReplacingOccurrencesOfString:@"=" withString:@"=="],
                                                RDLConnectionValue(value)]];
  }
  return [parts componentsJoinedByString:@";"];
}

// Which key names the document: a file to read, or content carried in the
// report. An editor asks for these rather than knowing the vocabulary itself.
NSString *RDLDocumentKeyForProviderKind(RDLDataProviderKind kind) {
  if (kind == RDLDataProviderKindJSON)
    return @"jsondoc";
  if (kind == RDLDataProviderKindXML)
    return @"xmldoc";
  // A text file is named on its own: "stock.csv;HasHeaders=true".
  return @"";
}

NSString *RDLInlineKeyForProviderKind(RDLDataProviderKind kind) {
  if (kind == RDLDataProviderKindJSON)
    return @"jsondata";
  if (kind == RDLDataProviderKindXML)
    return @"xmldata";
  return @"data";
}


// What every provider hands back: an array of dictionaries. A selected value
// that is an array is flattened, so "$.Movie" and "$.Movie[*]" agree; a scalar
// becomes a one-field row, because a report can only bind to a named field.
NSArray *RDLRowsFromSelection(NSArray *selected) {
  NSMutableArray *rows = [NSMutableArray array];
  for (id node in selected) {
    if ([node isKindOfClass:[NSArray class]]) {
      [rows addObjectsFromArray:RDLRowsFromSelection(node)];
    } else if ([node isKindOfClass:[NSDictionary class]]) {
      [rows addObject:node];
    } else if (node != nil && node != [NSNull null]) {
      [rows addObject:@{@"Value" : node}];
    }
  }
  return rows;
}

#pragma mark - Reading the types off the values

// A date, only when the text is written the way a date is written -- the ISO
// forms JSON documents use. Anything looser and a product code or a version
// number becomes a date, which is worse than calling it a string.
static BOOL RDLLooksLikeADate(NSString *text) {
  static NSArray<NSString *> *formats = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    formats = @[ @"yyyy-MM-dd", @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd'T'HH:mm:ssZ",
                 @"yyyy-MM-dd HH:mm:ss" ];
  });
  if ([text length] < 10)
    return NO;
  NSDateFormatter *f = [[NSDateFormatter alloc] init];
  f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  for (NSString *format in formats) {
    f.dateFormat = format;
    if ([f dateFromString:text] != nil)
      return YES;
  }
  return NO;
}

static RDLFieldDataType RDLTypeOfValue(id value) {
  if (value == nil || value == [NSNull null])
    return RDLFieldDataTypeUnknown;
  // "true" is a Boolean field; 1 is an Integer one.
  if (RDLNumberIsBoolean(value))
    return RDLFieldDataTypeBoolean;
  if ([value isKindOfClass:[NSNumber class]]) {
    const char *kind = [(NSNumber *)value objCType];
    if (kind != NULL && (*kind == 'f' || *kind == 'd'))
      return RDLFieldDataTypeFloat;
    long long whole = [(NSNumber *)value longLongValue];
    return whole < INT_MIN || whole > INT_MAX ? RDLFieldDataTypeLong : RDLFieldDataTypeInteger;
  }
  if ([value isKindOfClass:[NSDate class]])
    return RDLFieldDataTypeDateTime;
  if ([value isKindOfClass:[NSString class]])
    return RDLLooksLikeADate(value) ? RDLFieldDataTypeDateTime : RDLFieldDataTypeString;
  // An object or a list: rows of its own, which RDL has no type name for.
  return RDLFieldDataTypeUnknown;
}

static BOOL RDLIsInferredNumber(RDLFieldDataType type) {
  return type == RDLFieldDataTypeInteger || type == RDLFieldDataTypeLong || type == RDLFieldDataTypeFloat;
}

RDLFieldDataType RDLInferredFieldType(NSArray *rows, NSString *field) {
  RDLFieldDataType agreed = RDLFieldDataTypeUnknown;
  for (id row in rows) {
    if (![row isKindOfClass:[NSDictionary class]])
      continue;
    RDLFieldDataType here = RDLTypeOfValue([(NSDictionary *)row objectForKey:field]);
    if (here == RDLFieldDataTypeUnknown)
      continue;  // a null says nothing about the column
    if (agreed == RDLFieldDataTypeUnknown) {
      agreed = here;
      continue;
    }
    if (agreed == here)
      continue;
    // Whole numbers among fractional ones are still numbers; anything else
    // disagreeing means the column holds more than one kind of thing.
    // Whole numbers too large for an Integer make the column Long.
    BOOL bothNumbers = RDLIsInferredNumber(agreed) && RDLIsInferredNumber(here);
    agreed = !bothNumbers                                                           ? RDLFieldDataTypeString
             : (agreed == RDLFieldDataTypeFloat || here == RDLFieldDataTypeFloat) ? RDLFieldDataTypeFloat
                                                                                    : RDLFieldDataTypeLong;
    if (!bothNumbers)
      break;
  }
  return agreed;
}

NSURL *RDLURLAddingQueryItems(NSURL *url, NSArray<NSURLQueryItem *> *queryItems) {
  if (url == nil || [queryItems count] == 0)
    return url;
  NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
  components.queryItems = [(components.queryItems ?: @[]) arrayByAddingObjectsFromArray:queryItems];
  return components.URL ?: url;
}

#pragma mark - Binding

@implementation RDLDataBinder {
  NSMutableArray<NSString *> *_notes;
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
  if ((self = [super init])) {
    _baseURL = [baseURL copy];
    _providers = @[
      [[RDLJSONDataProvider alloc] init], [[RDLXMLDataProvider alloc] init],
      [[RDLCSVDataProvider alloc] init]
    ];
    _notes = [NSMutableArray array];
  }
  return self;
}

- (instancetype)init {
  return [self initWithBaseURL:nil];
}

- (NSArray<NSString *> *)notes {
  return [_notes copy];
}

- (id<RDLDataProvider>)providerNamed:(NSString *)name {
  for (id<RDLDataProvider> provider in _providers)
    if ([[provider name] caseInsensitiveCompare:name] == NSOrderedSame)
      return provider;
  // Another name the same kind goes by: Text, as Report Builder writes a
  // delimited-text source, is the CSV provider.
  RDLDataProviderKind kind = RDLDataProviderKindFromString(name);
  if (kind != RDLDataProviderKindUnspecified)
    for (id<RDLDataProvider> provider in _providers)
      if (RDLDataProviderKindFromString([provider name]) == kind)
        return provider;
  return nil;
}

// The document a connect string points at. Either it is in the string --
// "jsondata={...}" -- or it names a file beside the report. A URL is only
// fetched when the host has said that is allowed.
- (NSData *)documentForProperties:(NSDictionary<NSString *, NSString *> *)properties
                             kind:(RDLDataProviderKind)kind
                       queryItems:(NSArray<NSURLQueryItem *> *)queryItems
                            error:(NSError **)error {
  NSString *inlineKey = kind == RDLDataProviderKindXML ? @"xmldata" : @"jsondata";
  NSString *inlineText = properties[inlineKey] ?: properties[@"data"];
  if ([inlineText length])
    return [inlineText dataUsingEncoding:NSUTF8StringEncoding];

  NSString *docKey = kind == RDLDataProviderKindXML ? @"xmldoc" : @"jsondoc";
  NSString *location = properties[docKey] ?: properties[@"file"] ?: properties[@"path"] ?:
                       properties[@""];
  if ([location length] == 0) {
    if (error)
      *error = RDLDataError(32, @"the connect string names no document");
    return nil;
  }
  return [self dataAtLocation:location queryItems:queryItems error:error];
}

- (NSData *)dataAtLocation:(NSString *)location error:(NSError **)error {
  return [self dataAtLocation:location queryItems:nil error:error];
}

- (NSData *)dataAtLocation:(NSString *)location
                queryItems:(NSArray<NSURLQueryItem *> *)queryItems
                     error:(NSError **)error {
  NSURL *url = nil;
  if ([location hasPrefix:@"http://"] || [location hasPrefix:@"https://"]) {
    if (!_allowsRemoteDocuments) {
      if (error)
        *error = RDLDataError(
            33, [NSString stringWithFormat:@"'%@' is remote, and this viewer was not "
                                           @"asked to fetch remote data",
                                           location]);
      return nil;
    }
    url = RDLURLAddingQueryItems([NSURL URLWithString:location], queryItems);
  } else if ([location hasPrefix:@"file://"]) {
    url = [NSURL URLWithString:location];
  } else {
    NSString *expanded = [location stringByExpandingTildeInPath];
    url = [expanded isAbsolutePath] ? [NSURL fileURLWithPath:expanded]
                                    : [NSURL URLWithString:[expanded
                                          stringByAddingPercentEncodingWithAllowedCharacters:
                                              [NSCharacterSet URLPathAllowedCharacterSet]]
                                          relativeToURL:_baseURL];
    if (url == nil)
      url = [NSURL fileURLWithPath:expanded];
  }
  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
  if (data == nil && error)
    *error = readError ?: RDLDataError(34, [NSString stringWithFormat:@"could not read %@",
                                                                      location]);
  return data;
}

- (BOOL)bindDataSet:(RDLDataSet *)dataSet inReport:(RDLReport *)report error:(NSError **)error {
  return [self bindDataSet:dataSet inReport:report scope:nil error:error];
}

- (BOOL)dataSetReadsParameters:(RDLDataSet *)dataSet inReport:(RDLReport *)report {
  [report resolveDataSources];
  return [[RDLValue valueWithSource:dataSet.dataSource.connectString] isExpression] ||
         [[RDLValue valueWithSource:dataSet.commandText] isExpression] || [dataSet.queryParameters count] > 0;
}

- (BOOL)bindDataSet:(RDLDataSet *)dataSet
           inReport:(RDLReport *)report
              scope:(RDLEvalScope *)scope
              error:(NSError **)error {
  // Cheap and idempotent: a report built in code has never been resolved, and
  // one whose sources were edited may be out of date.
  [report resolveDataSources];
  RDLDataSource *source = dataSet.dataSource;
  if (source == nil) {
    if (error)
      *error = RDLDataError(35, [NSString stringWithFormat:@"dataset '%@' names no data source "
                                                           @"this report has",
                                                           dataSet.name ?: @""]);
    return NO;
  }
  RDLDataProviderKind kind = RDLDataProviderKindFromString(source.dataProvider);
  id<RDLDataProvider> provider = [self providerNamed:source.dataProvider];
  if (provider == nil) {
    if (error)
      *error = RDLDataError(36, [NSString stringWithFormat:@"no provider for '%@'",
                                                           source.dataProvider ?: @""]);
    return NO;
  }
  // A ConnectString and a CommandText may be expressions, and a QueryParameter's
  // value is one: evaluated here, in the scope of the parameters.
  RDLEvalScope *evaluating = scope ?: [[RDLEvalScope alloc] init];
  NSString *connectString = [[RDLValue valueWithSource:source.connectString] evaluateTextInScope:evaluating] ?: @"";
  NSString *query = [[RDLValue valueWithSource:dataSet.commandText] evaluateTextInScope:evaluating] ?: @"";
  NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
  for (RDLQueryParameter *parameter in dataSet.queryParameters) {
    id value = [parameter.value evaluateInScope:evaluating];
    // A MultiValue parameter's values are each one.
    for (id one in ([value isKindOfClass:[NSArray class]] ? value : @[ value ?: [NSNull null] ]))
      [queryItems addObject:[NSURLQueryItem queryItemWithName:parameter.name ?: @""
                                                        value:one == [NSNull null]
                                                                  ? nil
                                                                  : [RDLExpression formatValue:one format:nil language:nil]]];
  }
  NSDictionary *properties = RDLConnectionProperties(connectString);
  NSData *document = [self documentForProperties:properties kind:kind queryItems:queryItems error:error];
  if (document == nil)
    return NO;
  NSArray *rows = [provider rowsFromData:document
                                   query:query
                                 dataSet:dataSet
                              properties:properties
                                   error:error];
  if (rows == nil)
    return NO;
  dataSet.rows = rows;
  // Only when the report declares none: allKeys is unordered, so inferring over
  // a declared schema would scramble the columns a report was built around.
  // What the values are is read off them -- a JSON number is a number -- so a
  // dataset that discovered its fields knows their types as well as their
  // names.
  NSDictionary *first = [rows firstObject];
  if ([dataSet.fields count] == 0 && [first isKindOfClass:[NSDictionary class]]) {
    NSMutableArray<RDLField *> *fields = [NSMutableArray array];
    for (NSString *name in [first allKeys]) {
      RDLField *field = [[RDLField alloc] init];
      field.name = name;
      field.dataField = name;
      field.dataType = RDLInferredFieldType(rows, name);
      [fields addObject:field];
    }
    dataSet.fields = fields;
  } else {
    // Names may be declared while the types are not -- a dataset written by
    // hand, or one whose fields were named before there was a document to read.
    // A field that says what it holds is left alone; one that says nothing has
    // nothing to lose by being told.
    // Read off the field's own column -- its DataField -- not a column that
    // happens to share the field's name. A calculated field has no column.
    for (RDLField *field in dataSet.fields)
      if (field.dataType == RDLFieldDataTypeUnknown && [field rowKey] != nil)
        field.dataType = RDLInferredFieldType(rows, [field rowKey]);
  }
  return YES;
}

- (BOOL)bindReport:(RDLReport *)report error:(NSError **)error {
  [_notes removeAllObjects];
  [report resolveDataSources];
  NSUInteger bound = 0, attempted = 0;
  NSError *first = nil;
  for (RDLDataSet *dataSet in report.dataSets) {
    RDLDataSource *source = dataSet.dataSource;
    // A dataset with rows already, or with no source to read them from, is
    // somebody else's: rows set in code stay set.
    if (source == nil || [self providerNamed:source.dataProvider] == nil)
      continue;
    if ([source.connectString length] == 0)
      continue;
    // Its data waits for the parameters: RDLDataEvaluation binds it.
    if ([self dataSetReadsParameters:dataSet inReport:report])
      continue;
    attempted += 1;
    NSError *one = nil;
    if ([self bindDataSet:dataSet inReport:report error:&one]) {
      bound += 1;
    } else {
      first = first ?: one;
      [_notes addObject:[NSString stringWithFormat:@"%@: %@", dataSet.name ?: @"dataset",
                                                   [one localizedDescription] ?: @"could not bind"]];
    }
  }
  if (attempted > 0 && bound == 0) {
    if (error)
      *error = first;
    return NO;
  }
  return YES;
}

@end
