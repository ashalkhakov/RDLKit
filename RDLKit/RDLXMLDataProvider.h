/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLDataProvider.h"

// XML, via XPath. Each selected element is a row: its attributes and its leaf
// children are fields, and a child with children of its own stays as rows of
// its own, for a nested region to bind to.
@interface RDLXMLDataProvider : NSObject <RDLDataProvider>
@end
