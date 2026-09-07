/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

// What the providers share and nobody outside needs: one way to say what went
// wrong, and the rule for turning what a query selected into rows. Not
// installed as a public header -- a host implementing its own provider works
// through RDLDataProvider.h.
FOUNDATION_EXPORT NSError *RDLDataError(NSInteger code, NSString *message);
// An array of dictionaries, which is the shape RDLDataSet.rows takes: a
// selected array is flattened, and a scalar becomes a one-field row, because a
// report can only bind to a named field.
FOUNDATION_EXPORT NSArray *RDLRowsFromSelection(NSArray *selected);
