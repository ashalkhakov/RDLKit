/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// What this kit used to write that no schema has. Its files announced the
// 2010 namespace, so no migration sees these; they are put right on every
// document once it is in the current grammar, where none of them can be
// mistaken for something a schema means.
#import "RDLUpgraderSupport.h"

#pragma mark - Chart names

// Charts from before this kit used the spec's names: a series typed Pie,
// Doughnut or Bubble where RDL says Shape/Pie, Shape/Doughnut and
// Scatter/Bubble; an axis with Hidden, MajorInterval and MajorTickMarks where
// RDL has Visible, Interval and ChartMajorTickMarks/Type; grid lines and data
// labels with Hidden where RDL has Enabled and Visible.

static void RDLUpgradeChartSeriesKind(NSXMLElement *series) {
  NSXMLElement *type = RDLKid(series, @"Type");
  NSXMLElement *subtype = RDLKid(series, @"Subtype");
  NSString *old = RDLTrimmed(type);
  BOOL exploded = [RDLTrimmed(subtype) isEqualToString:@"Exploded"];
  NSString *family = nil, *variant = nil;
  if ([old isEqualToString:@"Pie"]) {
    family = @"Shape";
    variant = exploded ? @"ExplodedPie" : @"Pie";
  } else if ([old isEqualToString:@"Doughnut"]) {
    family = @"Shape";
    variant = exploded ? @"ExplodedDoughnut" : @"Doughnut";
  } else if ([old isEqualToString:@"Bubble"]) {
    family = @"Scatter";
    variant = @"Bubble";
  }
  if (family == nil)
    return;
  [type setStringValue:family];
  if (subtype)
    [subtype setStringValue:variant];
  else
    [series addChild:RDLNewText(@"Subtype", variant)];
}

static void RDLUpgradeChartAxisNames(NSXMLElement *axis) {
  NSXMLElement *hidden = RDLKid(axis, @"Hidden");
  if (hidden && RDLSaysTrue(hidden))
    RDLReplaceKid(axis, hidden, RDLNewText(@"Visible", @"False"));
  else
    [hidden detach];
  NSXMLElement *interval = RDLKid(axis, @"MajorInterval");
  if (interval)
    RDLReplaceKid(axis, interval, RDLNewText(@"Interval", RDLTrimmed(interval)));
  NSXMLElement *ticks = RDLKid(axis, @"MajorTickMarks");
  if (ticks) {
    NSXMLElement *marks = RDLNew(@"ChartMajorTickMarks");
    [marks addChild:RDLNewText(@"Type", RDLTrimmed(ticks))];
    RDLReplaceKid(axis, ticks, marks);
  }
  NSXMLElement *grid = RDLKid(axis, @"ChartMajorGridLines");
  NSXMLElement *gridHidden = RDLKid(grid, @"Hidden");
  if (gridHidden && RDLSaysTrue(gridHidden))
    RDLReplaceKid(grid, gridHidden, RDLNewText(@"Enabled", @"False"));
  else
    [gridHidden detach];
}

static void RDLUpgradeChartDataLabel(NSXMLElement *label) {
  NSXMLElement *hidden = RDLKid(label, @"Hidden");
  if (hidden)
    RDLReplaceKid(label, hidden, RDLNewText(@"Visible", RDLSaysTrue(hidden) ? @"false" : @"true"));
  else if ([RDLElems(label) count] == 0)
    // An empty label element was how this kit said "show the labels"; in the
    // spec a label is hidden unless it says Visible.
    [label addChild:RDLNewText(@"Visible", @"true")];
}

static void RDLUpgradeChartNames(NSXMLElement *el) {
  NSString *name = RDLLN(el);
  if ([name isEqualToString:@"ChartSeries"])
    RDLUpgradeChartSeriesKind(el);
  else if ([name isEqualToString:@"ChartAxis"])
    RDLUpgradeChartAxisNames(el);
  else if ([name isEqualToString:@"ChartDataLabel"])
    RDLUpgradeChartDataLabel(el);
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradeChartNames(child);
}

// PageName inside PageBreak is RDLKit's own invention -- no schema has it
// there -- and files this kit wrote carry it. It belongs to the region or the
// group that owns the break, so that is where it goes.

#pragma mark - Page names

// PageName inside PageBreak is RDLKit's own invention -- no schema has it
// there -- and files this kit wrote carry it. It belongs to the region or the
// group that owns the break, so that is where it goes.
static void RDLUpgradePageNames(NSXMLElement *el) {
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradePageNames(child);
  if (![RDLLN(el) isEqualToString:@"PageBreak"])
    return;
  NSXMLElement *name = RDLKid(el, @"PageName");
  NSXMLElement *owner = (NSXMLElement *)[el parent];
  if (name == nil || owner == nil)
    return;
  if (RDLKid(owner, @"PageName") == nil)
    [owner addChild:RDLTake(name)];
  else
    [name detach];
}

void RDLRepairRDLKitOutput(NSXMLElement *root) {
  // A <Name> child is not in any schema: RDLKit wrote one for years, and the
  // reader wants the name where the current writer puts it.
  NSXMLElement *legacyName = RDLKid(root, @"Name");
  if (legacyName && RDLKid(root, @"ReportName") == nil)
    [legacyName setName:@"ReportName"];
  RDLUpgradePageNames(root);
  RDLUpgradeChartNames(root);
}
