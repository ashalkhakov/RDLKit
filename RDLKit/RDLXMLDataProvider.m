/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLXMLDataProvider.h"
#import "RDLCompatibility.h"
#import "RDLDataProviderInternal.h"

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

