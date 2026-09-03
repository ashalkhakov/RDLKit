#import <Foundation/Foundation.h>

// Which Report Definition Language schema a document was written against.
// The numbers are the year in the namespace URI, and they sort, so
// `version < RDLSchemaVersion2010` is a meaningful question to ask.
typedef NS_ENUM(NSInteger, RDLSchemaVersion) {
  RDLSchemaVersionUnknown = 0, // no recognisable namespace; treated as 2005
  RDLSchemaVersion2003 = 2003,
  RDLSchemaVersion2005 = 2005,
  RDLSchemaVersion2008 = 2008,
  RDLSchemaVersion2010 = 2010, // the grammar RDLReport.h models
  RDLSchemaVersion2016 = 2016  // a superset of 2010; read as-is
};

// Brings an older report definition up to the current grammar, in place, the
// way SQL Server Reporting Services does when it opens an older report: the
// XML tree is rewritten before anything reads a model out of it, so RDLParser
// and RDLReport.h only ever have to know one shape.
//
// What that means concretely is that `Table` and `Matrix` become `Tablix` --
// their rows, cells and groupings restructured into TablixBody plus a row and
// column hierarchy -- along with the smaller renamings the older schemas used.
// Documents that are already 2010 or 2016 are left alone.
//
// Nothing here parses; it only moves XML around. Deciding what an element
// means stays in RDLParser.
@interface RDLUpgrader : NSObject

// The schema the document is written against, from its root namespace.
+ (RDLSchemaVersion)versionOfDocument:(NSXMLDocument *)document;

// Rewrites `document` in place. Returns the version it was upgraded *from*,
// so a caller can report what it did; RDLSchemaVersion2010 or 2016 means
// nothing needed doing.
+ (RDLSchemaVersion)upgradeDocument:(NSXMLDocument *)document;

@end
