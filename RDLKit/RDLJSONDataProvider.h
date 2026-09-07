/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLDataProvider.h"

// JSON, via JSONPath. Objects become rows; a selected array is flattened one
// level, so "$.Movie" and "$.Movie[*]" both give the films rather than one row
// holding all of them. Values that are themselves objects or arrays stay in the
// row: that is what a nested data region reads.
@interface RDLJSONDataProvider : NSObject <RDLDataProvider>
@end
