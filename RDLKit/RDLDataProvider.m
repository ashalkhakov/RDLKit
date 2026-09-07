/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataProvider.h"
#import "RDLCompatibility.h"

static NSString *const kRDLDataErrorDomain = @"RDLKit";

static NSError *RDLDataError(NSInteger code, NSString *message) {
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

#pragma mark - Rows

// What every provider hands back: an array of dictionaries. A selected value
// that is an array is flattened, so "$.Movie" and "$.Movie[*]" agree; a scalar
// becomes a one-field row, because a report can only bind to a named field.
static NSArray *RDLRowsFromSelection(NSArray *selected) {
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

#pragma mark - JSON

@implementation RDLJSONDataProvider

- (NSString *)name {
  return @"JSON";
}

- (NSArray *)rowsFromData:(NSData *)documentData
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error {
  RDL_UNUSED(properties);
  if (documentData == nil) {
    if (error)
      *error = RDLDataError(25, @"there is no JSON to read");
    return nil;
  }
  NSError *jsonError = nil;
  id root = [NSJSONSerialization JSONObjectWithData:documentData options:0 error:&jsonError];
  if (root == nil) {
    if (error)
      *error = jsonError ?: RDLDataError(26, @"the document is not JSON");
    return nil;
  }
  // No query at all means the document itself is the rows, which is what a
  // plain array of objects is.
  NSString *query = [dataSet.commandText
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([query length] == 0)
    return RDLRowsFromSelection(@[ root ]);
  RDLJSONPath *path = [RDLJSONPath pathWithString:query error:error];
  if (path == nil)
    return nil;
  return RDLRowsFromSelection([path selectFrom:root]);
}

@end

#pragma mark - XML

@implementation RDLXMLDataProvider

- (NSString *)name {
  return @"XML";
}

// One element as a row. Attributes and leaf children are fields; a child that
// has children of its own stays as rows, which is how a nested region reads
// <Order><Lines><Line/><Line/></Lines></Order>.
static id RDLRowFromElement(NSXMLElement *el) {
  NSMutableDictionary *row = [NSMutableDictionary dictionary];
  for (NSXMLNode *attr in [el attributes]) {
    NSString *name = [attr name];
    if ([name length])
      row[name] = [attr stringValue] ?: @"";
  }
  NSMutableDictionary<NSString *, NSMutableArray *> *repeated = [NSMutableDictionary dictionary];
  for (NSXMLNode *child in [el children]) {
    if (child.kind != NSXMLElementKind)
      continue;
    NSXMLElement *ce = (NSXMLElement *)child;
    NSString *name = [ce localName] ?: [ce name];
    if ([name length] == 0)
      continue;
    BOOL isLeaf = YES;
    for (NSXMLNode *grand in [ce children])
      if (grand.kind == NSXMLElementKind)
        isLeaf = NO;
    id value = (isLeaf && [[ce attributes] count] == 0) ? (id)([ce stringValue] ?: @"")
                                                        : (id)RDLRowFromElement(ce);
    // The same element twice is a list, which is the shape a nested region
    // wants -- and the shape the file already had.
    if (row[name] == nil && repeated[name] == nil) {
      row[name] = value;
    } else {
      NSMutableArray *list = repeated[name];
      if (list == nil) {
        list = [NSMutableArray arrayWithObject:row[name]];
        repeated[name] = list;
      }
      [list addObject:value];
      row[name] = list;
    }
  }
  // An element with nothing but text is that text.
  if ([row count] == 0)
    return [el stringValue] ?: @"";
  return row;
}

- (NSArray *)rowsFromData:(NSData *)documentData
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error {
  RDL_UNUSED(properties);
  if (documentData == nil) {
    if (error)
      *error = RDLDataError(27, @"there is no XML to read");
    return nil;
  }
  NSError *xmlError = nil;
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:documentData
                                                  options:NSXMLNodePreserveWhitespace
                                                    error:&xmlError];
  if (doc == nil) {
    if (error)
      *error = xmlError ?: RDLDataError(28, @"the document is not XML");
    return nil;
  }
  NSString *query = [dataSet.commandText
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray *nodes = nil;
  if ([query length] == 0) {
    // No XPath: the root's element children are the rows, which is what
    // <Orders><Order/><Order/></Orders> means without having to say so.
    NSMutableArray *children = [NSMutableArray array];
    for (NSXMLNode *child in [[doc rootElement] children])
      if (child.kind == NSXMLElementKind)
        [children addObject:child];
    nodes = children;
  } else {
    NSError *pathError = nil;
    nodes = [doc nodesForXPath:query error:&pathError];
    if (nodes == nil) {
      if (error)
        *error = pathError ?: RDLDataError(29, [NSString stringWithFormat:
                                                             @"'%@' is not an XPath this "
                                                             @"document understands",
                                                             query]);
      return nil;
    }
  }
  NSMutableArray *rows = [NSMutableArray array];
  for (NSXMLNode *node in nodes) {
    if (node.kind == NSXMLElementKind) {
      id row = RDLRowFromElement((NSXMLElement *)node);
      [rows addObject:[row isKindOfClass:[NSDictionary class]]
                          ? row
                          : @{([node localName] ?: @"Value") : row}];
    } else if ([[node stringValue] length]) {
      // An XPath may select attributes or text, and those are rows of one
      // field named after what was selected.
      [rows addObject:@{([node name] ?: @"Value") : [node stringValue]}];
    }
  }
  return rows;
}

@end

#pragma mark - CSV

@implementation RDLCSVDataProvider

- (NSString *)name {
  return @"CSV";
}

// The delimiter a connect string names. Written as a character, or by name for
// the two nobody can type into a properties list.
static NSString *RDLCSVDelimiter(NSDictionary<NSString *, NSString *> *properties) {
  NSString *named = properties[@"delimiter"] ?: properties[@"separator"];
  if ([named length] == 0)
    return @",";
  NSString *low = [named lowercaseString];
  if ([low isEqualToString:@"tab"] || [low isEqualToString:@"\\t"])
    return @"\t";
  if ([low isEqualToString:@"space"])
    return @" ";
  if ([low isEqualToString:@"semicolon"])
    return @";";
  if ([low isEqualToString:@"pipe"])
    return @"|";
  return [named substringToIndex:1];
}

// One line, split on the delimiter, honouring quotes: a quoted field may hold
// the delimiter, and "" inside one is a quote.
static NSArray<NSString *> *RDLCSVSplit(NSString *line, NSString *delimiter) {
  NSMutableArray *out = [NSMutableArray array];
  NSMutableString *field = [NSMutableString string];
  unichar delim = [delimiter characterAtIndex:0];
  BOOL quoted = NO;
  NSUInteger n = [line length];
  for (NSUInteger i = 0; i < n; i++) {
    unichar c = [line characterAtIndex:i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < n && [line characterAtIndex:i + 1] == '"') {
          [field appendString:@"\""];
          i += 1;
        } else {
          quoted = NO;
        }
      } else {
        [field appendFormat:@"%C", c];
      }
      continue;
    }
    if (c == '"') {
      quoted = YES;
    } else if (c == delim) {
      [out addObject:[field copy]];
      [field setString:@""];
    } else {
      [field appendFormat:@"%C", c];
    }
  }
  [out addObject:[field copy]];
  return out;
}

// Fixed-width: "Widths=10,20,8" says where the columns are. A short line is
// padded rather than dropped, because a trailing blank column is normal in
// these files.
static NSArray<NSString *> *RDLFixedWidthSplit(NSString *line, NSArray<NSNumber *> *widths) {
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger at = 0;
  NSUInteger n = [line length];
  for (NSNumber *width in widths) {
    NSUInteger w = (NSUInteger)MAX(0, [width integerValue]);
    NSString *piece = @"";
    if (at < n)
      piece = [line substringWithRange:NSMakeRange(at, MIN(w, n - at))];
    at += w;
    [out addObject:[piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
  }
  return out;
}

- (NSArray *)rowsFromData:(NSData *)documentData
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error {
  RDL_UNUSED(dataSet);
  if (documentData == nil) {
    if (error)
      *error = RDLDataError(30, @"there is no text to read");
    return nil;
  }
  NSString *text = [[NSString alloc] initWithData:documentData encoding:NSUTF8StringEncoding];
  if (text == nil)
    text = [[NSString alloc] initWithData:documentData encoding:NSISOLatin1StringEncoding];
  if (text == nil) {
    if (error)
      *error = RDLDataError(31, @"the file is not text this can read");
    return nil;
  }
  NSMutableArray<NSNumber *> *widths = nil;
  NSString *widthSpec = properties[@"widths"] ?: properties[@"fixedwidth"];
  if ([widthSpec length]) {
    widths = [NSMutableArray array];
    for (NSString *piece in [widthSpec componentsSeparatedByString:@","]) {
      NSInteger w = [[piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
          integerValue];
      if (w > 0)
        [widths addObject:@(w)];
    }
  }
  NSString *delimiter = RDLCSVDelimiter(properties);
  // Headers unless the file says otherwise: a first line of column names is
  // what nearly every one of these files has.
  NSString *headerSpec = properties[@"hasheaders"] ?: properties[@"headers"];
  BOOL hasHeaders = headerSpec == nil || [headerSpec boolValue] ||
                    [[headerSpec lowercaseString] isEqualToString:@"yes"];

  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
    RDL_UNUSED(stop);
    if ([[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length])
      [lines addObject:line];
  }];
  if ([lines count] == 0)
    return @[];

  NSArray<NSString *> *(^split)(NSString *) = ^NSArray<NSString *> *(NSString *line) {
    return widths ? RDLFixedWidthSplit(line, widths) : RDLCSVSplit(line, delimiter);
  };

  NSArray<NSString *> *headers = nil;
  NSUInteger firstRow = 0;
  if (hasHeaders) {
    headers = split(lines[0]);
    firstRow = 1;
  } else {
    NSUInteger count = [split(lines[0]) count];
    NSMutableArray *made = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++)
      [made addObject:[NSString stringWithFormat:@"Column%lu", (unsigned long)i + 1]];
    headers = made;
  }

  NSMutableArray *rows = [NSMutableArray array];
  for (NSUInteger i = firstRow; i < [lines count]; i++) {
    NSArray<NSString *> *values = split(lines[i]);
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSUInteger c = 0; c < [headers count]; c++) {
      NSString *name = [headers[c] stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceCharacterSet]];
      if ([name length] == 0)
        name = [NSString stringWithFormat:@"Column%lu", (unsigned long)c + 1];
      row[name] = c < [values count] ? values[c] : @"";
    }
    [rows addObject:row];
  }
  return rows;
}

@end

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
  NSDictionary *first = [rows firstObject];
  if ([dataSet.fields count] == 0 && [first isKindOfClass:[NSDictionary class]])
    [dataSet setFieldNames:[first allKeys]];
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
