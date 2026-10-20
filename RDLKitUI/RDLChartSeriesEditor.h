/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// A chart's series: what each plots, in the order they are drawn, and for the
// one selected, what it is drawn as -- the chart's own type or one of its own,
// which is how a line goes over columns -- against which value axis, in what
// colour, with which marker and labels, and the further values a scatter, a
// bubble, a range or a stock chart plots. Report Builder's Series Properties,
// with every series in one panel.
//
// Its colour, marker and labels are the data point's, which is what Report
// Builder writes and what wins over the series' own when the chart is drawn.
//
// Modal, like the other panels here. The panel edits a copy of the chart, so
// Cancel leaves the chart as it was, and OK sets the series through the
// editor as one undoable step.
@interface RDLChartSeriesEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runForChart:(RDLChart *)chart context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForChart:(RDLChart *)chart context:(RDLEditingContext *)context;

// The copy of the chart the panel edits, and the series it shows.
@property (nonatomic, readonly, strong) RDLChart *chart;
@property (nonatomic, readonly, strong) RDLChartSeries *shownSeries;

// Shows the series at `index`, keeping what was typed for the last. NO, staying
// where it is, when what was typed cannot be kept.
- (BOOL)showSeriesAtIndex:(NSUInteger)index;

// The buttons' actions, declared so they can be driven without a click.
- (void)addSeries:(id)sender;
- (void)removeSeries:(id)sender;
- (void)moveSeriesUp:(id)sender;
- (void)moveSeriesDown:(id)sender;
- (void)typeChanged:(id)sender;
- (void)editLabelExpression:(id)sender;

// What OK does: the series, as the panel holds them, set on the chart. NO,
// changing nothing, when a series has no name or two share one, or a size is
// not one -- which the panel then says; when nothing was changed, nothing is
// recorded to undo.
- (BOOL)apply;
@end
