/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// What the schema migrations share: NSXML conveniences that match on local
// names, and the few rules more than one migration needs. Internal to RDLKit.
#import <Foundation/Foundation.h>
#import "RDLUpgrader.h"

// Everything here matches on local names, because the older documents carry
// their own namespace (and some carry none at all) and the distinction never
// matters to what a migration does.
FOUNDATION_EXPORT NSString *RDLLN(NSXMLNode *n);
FOUNDATION_EXPORT NSArray<NSXMLElement *> *RDLElems(NSXMLElement *el);
FOUNDATION_EXPORT NSXMLElement *RDLKid(NSXMLElement *el, NSString *name);
FOUNDATION_EXPORT NSArray<NSXMLElement *> *RDLKids(NSXMLElement *el, NSString *name);
FOUNDATION_EXPORT NSString *RDLTrimmed(NSXMLElement *el);
FOUNDATION_EXPORT NSXMLElement *RDLNew(NSString *name);
FOUNDATION_EXPORT NSXMLElement *RDLNewText(NSString *name, NSString *text);
// Take an element out of its parent so it can be put somewhere else.
FOUNDATION_EXPORT NSXMLElement *RDLTake(NSXMLElement *el);
FOUNDATION_EXPORT void RDLReplaceKid(NSXMLElement *parent, NSXMLElement *old, NSXMLElement *replacement);
FOUNDATION_EXPORT BOOL RDLSaysTrue(NSXMLElement *el);
// The summed <Width> or <Height> of a run of elements, as a length.
FOUNDATION_EXPORT NSString *RDLSumExtent(NSArray<NSXMLElement *> *elements, NSString *name);
// A data region's DataSetName, where the report has one dataset and the
// region leaves it to be understood.
FOUNDATION_EXPORT void RDLFillDataSetName(NSXMLElement *region, NSXMLElement *root);
// The element the whole document hangs off.
FOUNDATION_EXPORT NSXMLElement *RDLRootOf(NSXMLElement *el);

// The migrations, one schema to the next, each taking a document that is in
// the grammar of the first and leaving it in the grammar of the second. The
// root is the <Report> element.
FOUNDATION_EXPORT void RDLMigrate2003To2005(NSXMLElement *root);
FOUNDATION_EXPORT void RDLMigrate2005To2008(NSXMLElement *root);
FOUNDATION_EXPORT void RDLMigrate2008To2010(NSXMLElement *root);
FOUNDATION_EXPORT void RDLMigrate2010To2016(NSXMLElement *root);

// What this kit itself used to write that is in no schema -- a <Name> on the
// report, chart names of its own, a PageName inside PageBreak -- put the way
// the schema says. Run on every document once it is in the current grammar.
FOUNDATION_EXPORT void RDLRepairRDLKitOutput(NSXMLElement *root);
