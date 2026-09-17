/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLUpgrader.h"
#import "RDLUpgraderSupport.h"

// One step up: the version a document must be in, the version it is in after,
// and what gets it there. In order, so an upgrade is the steps from where a
// document starts to the end.
typedef struct {
  RDLSchemaVersion from, to;
  void (*migrate)(NSXMLElement *root);
} RDLMigration;

static const RDLMigration kRDLMigrations[] = {
    {RDLSchemaVersion2003, RDLSchemaVersion2005, RDLMigrate2003To2005},
    {RDLSchemaVersion2005, RDLSchemaVersion2008, RDLMigrate2005To2008},
    {RDLSchemaVersion2008, RDLSchemaVersion2010, RDLMigrate2008To2010},
    {RDLSchemaVersion2010, RDLSchemaVersion2016, RDLMigrate2010To2016},
};
static const NSUInteger kRDLMigrationCount = sizeof(kRDLMigrations) / sizeof(*kRDLMigrations);

// Whether the document holds an element anywhere below `el` that no grammar
// after 2005 has.
static BOOL RDLHolds2005Element(NSXMLElement *el) {
  NSString *name = RDLLN(el);
  if ([name isEqualToString:@"List"] || [name isEqualToString:@"Table"] || [name isEqualToString:@"Matrix"])
    return YES;
  if ([name isEqualToString:@"WritingMode"]) {
    NSString *mode = [RDLTrimmed(el) lowercaseString];
    if ([mode isEqualToString:@"lr-tb"] || [mode isEqualToString:@"tb-rl"] || [mode isEqualToString:@"rl-tb"])
      return YES;
  }
  for (NSXMLElement *child in RDLElems(el))
    if (RDLHolds2005Element(child))
      return YES;
  return NO;
}

// Whether the report says something the way only 2003 did: its margins.
static BOOL RDLHolds2003Element(NSXMLElement *root) {
  for (NSString *name in @[ @"MarginTop", @"MarginBottom", @"MarginLeft", @"MarginRight" ])
    if (RDLKid(root, name) != nil)
      return YES;
  return NO;
}

@implementation RDLUpgrader

+ (RDLSchemaVersion)versionOfDocument:(NSXMLDocument *)document {
  NSXMLElement *root = [document rootElement];
  NSString *uri = [root URI] ?: @"";
  // ".../sqlserver/reporting/<year>/<month>/reportdefinition"
  NSRange r = [uri rangeOfString:@"/reporting/"];
  if (r.location == NSNotFound)
    return RDLSchemaVersionUnknown;
  NSString *rest = [uri substringFromIndex:NSMaxRange(r)];
  NSInteger year = [[[rest componentsSeparatedByString:@"/"] firstObject] integerValue];
  switch (year) {
  case 2003:
    return RDLSchemaVersion2003;
  case 2005:
    return RDLSchemaVersion2005;
  case 2008:
    return RDLSchemaVersion2008;
  case 2010:
    return RDLSchemaVersion2010;
  case 2016:
    return RDLSchemaVersion2016;
  default:
    return RDLSchemaVersionUnknown;
  }
}

// The grammar a document is really in. It is what it declares, unless it
// holds what only an older grammar has -- which files do: this kit's own older
// output announced 2010 while its report had no sections, as 2008's does not;
// files in the wild carry a 2005 List under a later namespace, and 2003's
// margins under 2005's. The
// migrations start from the older grammar then, and each leaves alone what is
// already in its later one.
+ (RDLSchemaVersion)grammarOfDocument:(NSXMLDocument *)document {
  RDLSchemaVersion declared = [self versionOfDocument:document];
  // A document that names no schema is read as the oldest this kit has seen
  // most of: 2005.
  RDLSchemaVersion version = declared == RDLSchemaVersionUnknown ? RDLSchemaVersion2005 : declared;
  NSXMLElement *root = [document rootElement];
  if (version >= RDLSchemaVersion2010 && RDLKid(root, @"ReportSections") == nil &&
      (RDLKid(root, @"Body") || RDLKid(root, @"Width") || RDLKid(root, @"Page")))
    version = RDLSchemaVersion2008;
  if (version >= RDLSchemaVersion2008 && RDLHolds2005Element(root))
    version = RDLSchemaVersion2005;
  if (version >= RDLSchemaVersion2005 && RDLHolds2003Element(root))
    version = RDLSchemaVersion2003;
  return version;
}

+ (RDLSchemaVersion)upgradeDocument:(NSXMLDocument *)document {
  RDLSchemaVersion declared = [self versionOfDocument:document];
  NSXMLElement *root = [document rootElement];
  if (root == nil)
    return declared;
  RDLSchemaVersion version = [self grammarOfDocument:document];
  for (NSUInteger i = 0; i < kRDLMigrationCount; i++) {
    if (kRDLMigrations[i].from != version)
      continue;
    kRDLMigrations[i].migrate(root);
    version = kRDLMigrations[i].to;
  }
  RDLRepairRDLKitOutput(root);
  return declared;
}

@end
