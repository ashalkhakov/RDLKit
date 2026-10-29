/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// What the schema migrations share: NSXML conveniences that match on local
// names, and the few rules more than one migration needs. Internal to RDLKit.
#import <Foundation/Foundation.h>
#import "RDLUpgrader.h"

/* RDLKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef RDLKIT_EXPORT
#define RDLKIT_EXPORT FOUNDATION_EXPORT
#endif

// Everything here matches on local names, because the older documents carry
// their own namespace (and some carry none at all) and the distinction never
// matters to what a migration does.
RDLKIT_EXPORT NSString *RDLLN(NSXMLNode *n);
RDLKIT_EXPORT NSArray<NSXMLElement *> *RDLElems(NSXMLElement *el);
RDLKIT_EXPORT NSXMLElement *RDLKid(NSXMLElement *el, NSString *name);
RDLKIT_EXPORT NSArray<NSXMLElement *> *RDLKids(NSXMLElement *el, NSString *name);
RDLKIT_EXPORT NSString *RDLTrimmed(NSXMLElement *el);
RDLKIT_EXPORT NSXMLElement *RDLNew(NSString *name);
RDLKIT_EXPORT NSXMLElement *RDLNewText(NSString *name, NSString *text);
// Take an element out of its parent so it can be put somewhere else.
RDLKIT_EXPORT NSXMLElement *RDLTake(NSXMLElement *el);
RDLKIT_EXPORT void RDLReplaceKid(NSXMLElement *parent, NSXMLElement *old, NSXMLElement *replacement);
RDLKIT_EXPORT BOOL RDLSaysTrue(NSXMLElement *el);
// The summed <Width> or <Height> of a run of elements, as a length.
RDLKIT_EXPORT NSString *RDLSumExtent(NSArray<NSXMLElement *> *elements, NSString *name);
// A data region's DataSetName, where the report has one dataset and the
// region leaves it to be understood.
RDLKIT_EXPORT void RDLFillDataSetName(NSXMLElement *region, NSXMLElement *root);
// The element the whole document hangs off.
RDLKIT_EXPORT NSXMLElement *RDLRootOf(NSXMLElement *el);

// The migrations, one schema to the next, each taking a document that is in
// the grammar of the first and leaving it in the grammar of the second. The
// root is the <Report> element.
RDLKIT_EXPORT void RDLMigrate2003To2005(NSXMLElement *root);
RDLKIT_EXPORT void RDLMigrate2005To2008(NSXMLElement *root);
RDLKIT_EXPORT void RDLMigrate2008To2010(NSXMLElement *root);
RDLKIT_EXPORT void RDLMigrate2010To2016(NSXMLElement *root);

// What this kit itself used to write that is in no schema -- a <Name> on the
// report, chart names of its own, a PageName inside PageBreak -- put the way
// the schema says. Run on every document once it is in the current grammar.
RDLKIT_EXPORT void RDLRepairRDLKitOutput(NSXMLElement *root);
