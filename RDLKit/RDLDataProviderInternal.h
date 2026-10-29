/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* RDLKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef RDLKIT_EXPORT
#define RDLKIT_EXPORT FOUNDATION_EXPORT
#endif

// What the providers share and nobody outside needs: one way to say what went
// wrong, and the rule for turning what a query selected into rows. Not
// installed as a public header -- a host implementing its own provider works
// through RDLDataProvider.h.
RDLKIT_EXPORT NSError *RDLDataError(NSInteger code, NSString *message);
// An array of dictionaries, which is the shape RDLDataSet.rows takes: a
// selected array is flattened, and a scalar becomes a one-field row, because a
// report can only bind to a named field.
RDLKIT_EXPORT NSArray *RDLRowsFromSelection(NSArray *selected);
