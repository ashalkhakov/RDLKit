/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSource;

// One data source: what kind of document it is, where that document is, and
// whatever else that kind needs -- for delimited text, whether the first row
// names the columns and what separates them.
//
// The connect string itself is not edited here. It is a serialisation
// ("stock.csv;HasHeaders=true"), and a person configuring a source should be
// choosing a kind and answering its questions, not writing one out; the pane
// shows the line it will write, so anyone who does know RDL can see it.
@interface RDLDataSourceView : NSView
@property (nonatomic, strong) RDLDataSource *dataSource;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
// The XIB's actions. Declared because they are what the pane does, and so that
// they can be driven without a click.
- (void)changed:(id)sender;
- (void)rename:(id)sender;
@end
