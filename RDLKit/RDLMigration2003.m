/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// RDL 2003 to RDL 2005. The two grammars differ in little that this kit
// reads: 2003 spelled the report's margins the other way round.
#import "RDLUpgraderSupport.h"

void RDLMigrate2003To2005(NSXMLElement *root) {
  NSDictionary<NSString *, NSString *> *renames = @{
    @"MarginTop" : @"TopMargin",
    @"MarginBottom" : @"BottomMargin",
    @"MarginLeft" : @"LeftMargin",
    @"MarginRight" : @"RightMargin"
  };
  for (NSXMLElement *e in RDLElems(root)) {
    NSString *to = renames[RDLLN(e)];
    if (to)
      [e setName:to];
  }
}
