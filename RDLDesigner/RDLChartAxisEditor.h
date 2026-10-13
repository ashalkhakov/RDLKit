/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// A chart's axes: the category axis along the bottom, the value axis up the
// side and any further value axes a series is plotted against -- each one's
// title, range, interval, labels, grid lines and tick marks, and which side it
// is on. Report Builder's Axis Properties, with every axis in one panel.
//
// Modal, like the other panels here. The panel edits a copy of the chart, so
// Cancel leaves the chart as it was, and OK sets the axes through the editor
// as one undoable step.
@interface RDLChartAxisEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runForChart:(RDLChart *)chart context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForChart:(RDLChart *)chart context:(RDLEditingContext *)context;

// The copy of the chart the panel edits.
@property (nonatomic, readonly, strong) RDLChart *chart;
// Which axis the panel shows: the category axis, the value axis, then the
// further value axes in the chart's order.
@property (nonatomic, readonly, copy) NSArray<RDLChartAxis *> *axes;
@property (nonatomic, readonly, strong) RDLChartAxis *shownAxis;

// Shows the axis the axis popup names, keeping what was typed for the last.
- (void)selectAxis:(id)sender;
- (void)editTitleExpression:(id)sender;

// What OK does: the axes, as the panel holds them, set on the chart. YES
// unless a value typed is not one -- which the panel then says -- and when
// nothing was changed, nothing is recorded to undo.
- (BOOL)apply;
@end
