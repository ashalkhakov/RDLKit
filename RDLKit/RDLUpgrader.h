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
// The upgrade is a sequence of migrations, each from one schema to the next,
// each in a file of its own (RDLMigration<year>.m): 2005 to 2008 is where
// `Table`, `Matrix` and `List` become `Tablix` and the chart is redesigned,
// 2008 to 2010 where a report grows sections. What this kit's own older files
// said that no schema has is put right afterwards (RDLUpgraderRepairs.m).
//
// Nothing here parses; it only moves XML around. Deciding what an element
// means stays in RDLParser.
@interface RDLUpgrader : NSObject

// The schema the document is written against, from its root namespace.
+ (RDLSchemaVersion)versionOfDocument:(NSXMLDocument *)document;

// The grammar the document is really written in: what it declares, or older
// where it holds what only an older grammar has. What the upgrade starts from.
+ (RDLSchemaVersion)grammarOfDocument:(NSXMLDocument *)document;

// Rewrites `document` in place, one schema to the next -- 2003 to 2005, 2005
// to 2008, 2008 to 2010, 2010 to 2016 -- from the grammar it is in. Returns the
// version it declared, so a caller can report what it did;
// RDLSchemaVersion2010 or 2016 means it claimed to need nothing.
+ (RDLSchemaVersion)upgradeDocument:(NSXMLDocument *)document;

@end
