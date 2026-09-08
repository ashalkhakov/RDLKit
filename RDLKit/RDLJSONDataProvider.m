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

