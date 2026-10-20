/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLUpgraderSupport.h"
#import "RDLReport.h" // RDLLength, so measurements are parsed in one place

NSString *RDLLN(NSXMLNode *n) {
  return [n localName] ?: [n name] ?: @"";
}

NSArray<NSXMLElement *> *RDLElems(NSXMLElement *el) {
  if (el == nil)
    return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [el children])
    if (n.kind == NSXMLElementKind)
      [out addObject:(NSXMLElement *)n];
  return out;
}

NSXMLElement *RDLKid(NSXMLElement *el, NSString *name) {
  for (NSXMLElement *e in RDLElems(el))
    if ([RDLLN(e) isEqualToString:name])
      return e;
  return nil;
}

NSArray<NSXMLElement *> *RDLKids(NSXMLElement *el, NSString *name) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLElement *e in RDLElems(el))
    if ([RDLLN(e) isEqualToString:name])
      [out addObject:e];
  return out;
}

NSString *RDLTrimmed(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

NSXMLElement *RDLNew(NSString *name) {
  return [NSXMLElement elementWithName:name];
}

NSXMLElement *RDLNewText(NSString *name, NSString *text) {
  NSXMLElement *el = [NSXMLElement elementWithName:name];
  [el setStringValue:text ?: @""];
  return el;
}

// Take an element out of its parent so it can be put somewhere else. The
// subtree, including its namespace, comes with it.
NSXMLElement *RDLTake(NSXMLElement *el) {
  [el detach];
  return el;
}

// Sum the <Width>/<Height> of a run of elements, in inches. Used to give a
// converted data region the Width and Height that 2005 left implicit and 2010
// requires -- an item with no size lays out as nothing.
NSString *RDLSumExtent(NSArray<NSXMLElement *> *elements, NSString *name) {
  CGFloat total = 0;
  for (NSXMLElement *e in elements) {
    NSXMLElement *m = RDLKid(e, name);
    RDLLength *len = m ? [RDLLength lengthFromString:RDLTrimmed(m)] : nil;
    total += len ? [len inches] : 0;
  }
  return [NSString stringWithFormat:@"%.5gin", (double)total];
}

// 2005 lets a data region leave DataSetName out when the report has exactly
// one dataset; from 2008 the element is required. Materialise it, or the
// region finds no rows and renders only its no-rows message.
void RDLFillDataSetName(NSXMLElement *region, NSXMLElement *root) {
  if (RDLKid(region, @"DataSetName") != nil)
    return;
  NSArray *sets = RDLKids(RDLKid(root, @"DataSets"), @"DataSet");
  if ([sets count] != 1)
    return;
  NSString *name = [[sets[0] attributeForName:@"Name"] stringValue];
  if ([name length])
    [region addChild:RDLNewText(@"DataSetName", name)];
}

// The element the whole document hangs off, for the rules that need to see it.
NSXMLElement *RDLRootOf(NSXMLElement *el) {
  NSXMLNode *n = el;
  while ([n parent] != nil && [[n parent] kind] == NSXMLElementKind)
    n = [n parent];
  return (NSXMLElement *)n;
}

void RDLReplaceKid(NSXMLElement *parent, NSXMLElement *old, NSXMLElement *replacement) {
  NSUInteger index = [old index];
  [old detach];
  [parent insertChild:replacement atIndex:index];
}

BOOL RDLSaysTrue(NSXMLElement *el) {
  return [[RDLTrimmed(el) lowercaseString] isEqualToString:@"true"];
}
