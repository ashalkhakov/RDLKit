/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLJSONDataProvider.h"
#import "RDLCompatibility.h"
#import "RDLDataProviderInternal.h"
#import "RDLJSONPath.h"

@implementation RDLJSONDataProvider

- (NSString *)name {
  return @"JSON";
}

- (NSArray *)rowsFromData:(NSData *)documentData
                   query:(NSString *)query
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error {
  RDL_UNUSED(properties);
  RDL_UNUSED(dataSet);
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
  NSString *path = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([path length] == 0)
    return RDLRowsFromSelection(@[ root ]);
  RDLJSONPath *compiled = [RDLJSONPath pathWithString:path error:error];
  if (compiled == nil)
    return nil;
  return RDLRowsFromSelection([compiled selectFrom:root]);
}

@end

