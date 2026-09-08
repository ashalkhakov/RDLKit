/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLDataProvider.h"

// Delimited or fixed-width text. Options ride in the connect string:
//
//   data.csv;HasHeaders=true;Delimiter=Tab
//   data.txt;Widths=10,20,8;HasHeaders=false
//
// Without headers the fields are Column1, Column2 … , which is also what the
// designer shows. CSV is flat: there is nothing here for a nested region.
@interface RDLCSVDataProvider : NSObject <RDLDataProvider>
@end
