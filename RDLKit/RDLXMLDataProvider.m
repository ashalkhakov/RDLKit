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

// What one node is worth as a field: an element with elements inside it is a
// row of its own, anything else is its text -- an attribute, a text node, an
// element holding only words.
static id RDLValueOfNode(NSXMLNode *node) {
  if (node.kind == NSXMLElementKind)
    return RDLRowFromElement((NSXMLElement *)node);
  return [node stringValue] ?: @"";
}

// A field's DataField read as an XPath from the row's own element, which is
// how a column of an XML dataset is written: "@No", "Customer/Name",
// "Line[1]/@Item". nil when it is not an XPath this document understands, or
// when it selects nothing -- the caller then leaves the field alone, so a
// DataField that is a plain child name keeps reading the way it always did.
static id RDLXMLValueForPath(NSXMLElement *el, NSString *path) {
  if ([path length] == 0)
    return nil;
  NSError *pathError = nil;
  NSArray *nodes = [el nodesForXPath:path error:&pathError];
  if ([nodes count] == 0)
    return nil;
  if ([nodes count] == 1)
    return RDLValueOfNode(nodes[0]);
  // Several: a list, which is the shape a nested region binds to.
  NSMutableArray *values = [NSMutableArray array];
  for (NSXMLNode *node in nodes)
    [values addObject:RDLValueOfNode(node)];
  return values;
}

// The columns a dataset declares, as XPaths from the row element. Only the
// ones the row does not already have: a DataField naming a child or an
// attribute is found by reading the element, and asking XPath for it again
// would give the same answer more slowly.
static void RDLAddDeclaredColumns(NSMutableDictionary *row, NSXMLElement *el, RDLDataSet *dataSet) {
  for (RDLField *field in dataSet.fields) {
    NSString *key = [field rowKey];
    if ([key length] == 0 || row[key] != nil)
      continue;
    id value = RDLXMLValueForPath(el, key);
    if (value != nil)
      row[key] = value;
  }
}

- (NSArray *)rowsFromData:(NSData *)documentData
                   query:(NSString *)query
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
  NSString *xpath = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray *nodes = nil;
  if ([xpath length] == 0) {
    // No XPath: the root's element children are the rows, which is what
    // <Orders><Order/><Order/></Orders> means without having to say so.
    NSMutableArray *children = [NSMutableArray array];
    for (NSXMLNode *child in [[doc rootElement] children])
      if (child.kind == NSXMLElementKind)
        [children addObject:child];
    nodes = children;
  } else {
    NSError *pathError = nil;
    nodes = [doc nodesForXPath:xpath error:&pathError];
    if (nodes == nil) {
      if (error)
        *error = pathError ?: RDLDataError(29, [NSString stringWithFormat:
                                                             @"'%@' is not an XPath this "
                                                             @"document understands",
                                                             xpath]);
      return nil;
    }
  }
  NSMutableArray *rows = [NSMutableArray array];
  for (NSXMLNode *node in nodes) {
    if (node.kind == NSXMLElementKind) {
      id read = RDLRowFromElement((NSXMLElement *)node);
      NSMutableDictionary *row =
          [read isKindOfClass:[NSDictionary class]]
              ? [read mutableCopy]
              : [@{([node localName] ?: @"Value") : read} mutableCopy];
      // A column of an XML dataset is an XPath, so a DataField the element
      // does not answer to by name is asked for as one.
      RDLAddDeclaredColumns(row, (NSXMLElement *)node, dataSet);
      [rows addObject:row];
    } else if ([[node stringValue] length]) {
      // An XPath may select attributes or text, and those are rows of one
      // field named after what was selected.
      [rows addObject:@{([node name] ?: @"Value") : [node stringValue]}];
    }
  }
  return rows;
}

@end

