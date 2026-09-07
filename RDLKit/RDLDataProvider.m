/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataProvider.h"
#import "RDLDataProviderInternal.h"
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

NSDictionary<NSString *, NSString *> *RDLConnectionProperties(NSString *connectString) {
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  for (NSString *part in [connectString componentsSeparatedByString:@";"]) {
    NSString *token = [part stringByTrimmingCharactersInSet:space];
    if ([token length] == 0)
      continue;
    NSRange eq = [token rangeOfString:@"="];
    // A bare token is the document: "data.csv;HasHeaders=true" names its file
    // that way, and so does a path someone pasted in whole.
    if (eq.location == NSNotFound) {
      if (out[@""] == nil)
        out[@""] = token;
      continue;
    }
    NSString *key = [[[token substringToIndex:eq.location] stringByTrimmingCharactersInSet:space]
        lowercaseString];
    NSString *value =
        [[token substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:space];
    if ([key length])
      out[key] = value;
  }
  return out;
}

NSString *RDLConnectionString(NSDictionary<NSString *, NSString *> *properties) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSString *document = properties[@""];
  if ([document length])
    [parts addObject:document];
  // Everything else in name order, so the same settings always write the same
  // line and a saved report does not churn.
  for (NSString *key in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([key length] == 0)
      continue;
    NSString *value = properties[key];
    if ([value length] == 0)
      continue;
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
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

// A JSON boolean is an NSNumber like any other, and telling it apart matters:
// "true" is a Boolean field, 1 is an Integer one.
static BOOL RDLIsJSONBoolean(id value) {
  return [value isKindOfClass:[NSNumber class]] &&
         CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

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
  if (RDLIsJSONBoolean(value))
    return RDLFieldDataTypeBoolean;
  if ([value isKindOfClass:[NSNumber class]]) {
    const char *kind = [(NSNumber *)value objCType];
    BOOL fractional = kind != NULL && (*kind == 'f' || *kind == 'd');
    return fractional ? RDLFieldDataTypeFloat : RDLFieldDataTypeInteger;
  }
  if ([value isKindOfClass:[NSDate class]])
    return RDLFieldDataTypeDateTime;
  if ([value isKindOfClass:[NSString class]])
    return RDLLooksLikeADate(value) ? RDLFieldDataTypeDateTime : RDLFieldDataTypeString;
  // An object or a list: rows of its own, which RDL has no type name for.
  return RDLFieldDataTypeUnknown;
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
    BOOL bothNumbers = (agreed == RDLFieldDataTypeInteger || agreed == RDLFieldDataTypeFloat) &&
                       (here == RDLFieldDataTypeInteger || here == RDLFieldDataTypeFloat);
    agreed = bothNumbers ? RDLFieldDataTypeFloat : RDLFieldDataTypeString;
    if (!bothNumbers)
      break;
  }
  return agreed;
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
  return nil;
}

// The document a connect string points at. Either it is in the string --
// "jsondata={...}" -- or it names a file beside the report. A URL is only
// fetched when the host has said that is allowed.
- (NSData *)documentForProperties:(NSDictionary<NSString *, NSString *> *)properties
                             kind:(RDLDataProviderKind)kind
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
    url = [NSURL URLWithString:location];
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
  NSDictionary *properties = RDLConnectionProperties(source.connectString);
  NSData *document = [self documentForProperties:properties kind:kind error:error];
  if (document == nil)
    return NO;
  NSArray *rows = [provider rowsFromData:document
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
    for (RDLField *field in dataSet.fields)
      if (field.dataType == RDLFieldDataTypeUnknown)
        field.dataType = RDLInferredFieldType(rows, field.name);
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
