/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Round trip: what a report is when it comes back. Opening a file, saving it
// and opening it again has to give the same report -- including the parts the
// designer never shows, which are the ones nobody notices going missing until
// the file is opened somewhere else.
//
// These are the cases RND-01 to RND-03 of RDL-DESIGNER-USE-CASES.md, which
// were on the hand-checked list.
#import "RDLDesignerTestSupport.h"
#import "RDLGroupsView.h"
#import "RDLTablixStructure.h"
#import "RDLInspectorView.h"

@interface RDLRoundTripTests : RDLDesignerTestCase
@end

@implementation RDLRoundTripTests

// A scratch file of its own for each save, so nothing a test writes is read by
// another.
static NSURL *RDLScratchURL(NSString *name) {
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"rdl-roundtrip-%@", [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
}

// The report a file holds, opened the way the designer opens one.
static RDLDocument *RDLOpen(NSURL *url) {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:nil];
  return [doc openURL:url error:NULL] ? doc : nil;
}

// Saved, then opened again: the document that comes back.
static RDLDocument *RDLSaveAndOpen(RDLDocument *doc, NSString *name) {
  NSURL *url = RDLScratchURL(name);
  if (![doc saveToURL:url error:NULL])
    return nil;
  return RDLOpen(url);
}

// The first table of a report, which is what most of these edit.
static RDLTablix *RDLFirstTablix(RDLReport *report) {
  for (RDLItem *item in [report allItemsIncludingNested])
    if ([item isKindOfClass:[RDLTablix class]])
      return (RDLTablix *)item;
  return nil;
}

// What a report holds, in the terms a person would count it in.
static NSDictionary<NSString *, NSNumber *> *RDLTally(RDLReport *report) {
  NSUInteger cells = 0, groups = 0;
  for (RDLItem *item in [report allItemsIncludingNested]) {
    if (![item isKindOfClass:[RDLTablix class]])
      continue;
    RDLTablix *tablix = (RDLTablix *)item;
    for (RDLTablixRow *row in tablix.tablixBody.rows)
      cells += [row.cells count];
    groups += [[tablix.rowHierarchy leafMembers] count] + [[tablix.columnHierarchy leafMembers] count];
  }
  return @{
    @"items" : @([[report allItemsIncludingNested] count]),
    @"datasets" : @([report.dataSets count]),
    @"sources" : @([report.dataSources count]),
    @"parameters" : @([report.parameters count]),
    @"kept" : @([report.preservedNodes count]),
    @"cells" : @(cells),
    @"members" : @(groups),
  };
}

// RND-01. Every sample, opened and saved with nothing touched: what comes back
// is the same report, and saving it again writes the same file -- so a report
// does not drift a little further from itself each time it is opened.
- (void)testEverySampleSurvivesOpenAndSave {
  for (NSDictionary *entry in [RDLSamples catalog]) {
    NSString *sampleId = entry[@"id"];
    NSURL *url = [RDLSamples URLForSampleWithId:sampleId];
    RDLDocument *first = url ? RDLOpen(url) : nil;
    if (first == nil) {
      XCTFail(@"the %@ sample should open from its own file", sampleId);
      continue;
    }
    NSString *wrote = [first XMLString];
    RDLDocument *again = RDLSaveAndOpen(first, @"same.rdl");
    if (again == nil) {
      XCTFail(@"the %@ sample should save and open again", sampleId);
      continue;
    }
    if (![[again XMLString] isEqualToString:wrote])
      XCTFail(@"%@ is not the same report after a save and an open", sampleId);
    if (![RDLTally(again.report) isEqualToDictionary:RDLTally(first.report)])
      XCTFail(@"%@ lost something: %@ became %@", sampleId, RDLTally(first.report),
              RDLTally(again.report));
    // And a saved file is one the kit is happy with, not merely one it wrote.
    if ([[RDLChecker checkReport:again.report] count] != [[RDLChecker checkReport:first.report] count])
      XCTFail(@"%@ has problems after a round trip that it did not have before", sampleId);
  }
}

// RND-02. One edit of each kind the designer makes, then a save and an open:
// each edit is there, and nothing else moved.
- (void)testAnEditOfEachKindSurvivesSaveAndReopen {
  RDLDocument *doc = RDLOpen([RDLSamples URLForSampleWithId:@"manifest"]);
  if (doc == nil) {
    XCTFail(@"%@", @"the manifest sample should open from its own file");
    return;
  }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithDocument:doc];
  RDLReport *report = doc.report;
  RDLTablix *tablix = nil;
  RDLTextbox *box = nil;
  for (RDLItem *item in [report allItemsIncludingNested]) {
    if (tablix == nil && [item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
    if (box == nil && [item isKindOfClass:[RDLTextbox class]])
      box = (RDLTextbox *)item;
  }
  if (tablix == nil || box == nil) {
    XCTFail(@"%@", @"the manifest has a table and text boxes, which is what this edits");
    return;
  }

  // A property, a measurement, a style, a rename, a new item, a new dataset,
  // a new parameter, and a structural edit of the table.
  [ctx.editor setValue:@"Round tripped" forKeyPath:@"value" ofItem:box];
  [ctx.editor moveItem:box toLeft:1.25 top:0.75];
  [ctx.editor setValue:@"#c0392b" forKeyPath:@"style.backgroundColor" ofItem:box];
  [ctx.editor renameItem:box to:@"TheBox"];

  RDLTextbox *added = [[RDLTextbox alloc] init];
  added.name = @"Added";
  added.value = @"=Globals!PageNumber";
  added.left = 0.5;
  added.top = 2.5;
  added.width = 1.5;
  added.height = 0.3;
  [ctx.editor addItem:added into:report.body.items bandKey:@"body"];

  RDLDataSet *dataSet = [[RDLDataSet alloc] init];
  dataSet.name = @"Extra";
  dataSet.dataSourceName = [[report.dataSources firstObject] name];
  [dataSet setFieldNames:@[ @"One" ]];
  [ctx.editor addDataSet:dataSet];

  RDLParameter *parameter = [[RDLParameter alloc] init];
  parameter.name = @"Since";
  parameter.dataType = RDLParameterDataTypeString;
  parameter.prompt = @"Since when";
  [ctx.editor addParameter:parameter];

  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  RDLGroupsView *groups = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];
  [groups selectAxis:RDLTablixAxisRows];
  NSString *field = [[[report dataSetNamed:tablix.dataSetName] fieldNames] firstObject];
  if (field != nil)
    [groups addGroupWithExpression:[NSString stringWithFormat:@"=Fields!%@.Value", field]
                         placement:RDLGroupPlacementChild];
  NSUInteger groupsMade = [[groups allGroupsOnAxis:RDLTablixAxisRows] count];

  RDLDocument *again = RDLSaveAndOpen(doc, @"edited.rdl");
  if (again == nil) {
    XCTFail(@"%@", @"the edited report should save and open again");
    return;
  }
  RDLReport *back = again.report;
  RDLTextbox *theBox = nil, *theAdded = nil;
  RDLTablix *theTablix = nil;
  for (RDLItem *item in [back allItemsIncludingNested]) {
    if ([item.name isEqualToString:@"TheBox"])
      theBox = (RDLTextbox *)item;
    if ([item.name isEqualToString:@"Added"])
      theAdded = (RDLTextbox *)item;
    if (theTablix == nil && [item isKindOfClass:[RDLTablix class]])
      theTablix = (RDLTablix *)item;
  }
  if (theBox == nil)
    XCTFail(@"%@", @"the renamed text box should be in the file");
  if (![[theBox.value description] isEqualToString:@"Round tripped"])
    XCTFail(@"its value should be what was typed, it is %@", theBox.value);
  if (fabs(theBox.left - 1.25) > 0.001 || fabs(theBox.top - 0.75) > 0.001)
    XCTFail(@"it should be where it was moved to, it is at %.3f, %.3f", theBox.left, theBox.top);
  if (![theBox.style.backgroundColor isEqualToString:@"#c0392b"])
    XCTFail(@"its background should have come back, it is %@", theBox.style.backgroundColor);
  if (theAdded == nil)
    XCTFail(@"%@", @"the text box that was added should be in the file");
  if ([back dataSetNamed:@"Extra"] == nil)
    XCTFail(@"%@", @"the dataset that was added should be in the file");
  BOOL sawParameter = NO;
  for (RDLParameter *p in back.parameters)
    sawParameter = sawParameter || [p.name isEqualToString:@"Since"];
  if (!sawParameter)
    XCTFail(@"%@", @"the parameter that was added should be in the file");
  RDLGroupsView *backGroups = nil;
  if (theTablix != nil) {
    RDLEditingContext *backCtx = [[RDLEditingContext alloc] initWithDocument:again];
    [backCtx.selection selectItem:theTablix inBandWithKey:@"body"];
    backGroups = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:backCtx];
    if ([[backGroups allGroupsOnAxis:RDLTablixAxisRows] count] != groupsMade)
      XCTFail(@"the table should group as it did: %lu groups became %lu",
              (unsigned long)groupsMade,
              (unsigned long)[[backGroups allGroupsOnAxis:RDLTablixAxisRows] count]);
  }
  if ([[theTablix structuralProblems] count])
    XCTFail(@"the table should still be sound: %@", [theTablix structuralProblems]);
}

// TBL-16, reported as "filters not being saved, no rows message doesn't
// save". What a region's settings do between the inspector and the file:
// typed in, applied through the editor, written, read back.
- (void)testARegionsSettingsSurviveTheInspectorAndTheFile {
  RDLDocument *doc = RDLOpen([RDLSamples URLForSampleWithId:@"manifest"]);
  RDLEditingContext *ctx = doc ? [[RDLEditingContext alloc] initWithDocument:doc] : nil;
  RDLTablix *tablix = doc ? RDLFirstTablix(doc.report) : nil;
  if (tablix == nil) {
    XCTFail(@"%@", @"the manifest sample should open and hold a table");
    return;
  }
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 900)
                                                                context:ctx];
  [inspector reload];

  // The no-rows message, typed where a person types it.
  NSTextField *noRows = [inspector valueForKey:@"noRowsMessageField"];
  [noRows setStringValue:@"Nothing shipped"];
  [inspector changed:noRows];
  if (![tablix.noRowsMessage isEqualToString:@"Nothing shipped"])
    XCTFail(@"the message should reach the table, it is %@", tablix.noRowsMessage);

  // Filters, as the panel hands them back.
  RDLFilter *filter = [[RDLFilter alloc] init];
  filter.expression = [RDLValue valueWithSource:@"=Fields!Port.Value"];
  filter.oper = RDLFilterOperatorEqual;
  [filter.values addObject:[RDLValue literal:@"Dover"]];
  [ctx.editor setValue:[@[ filter ] mutableCopy] forKeyPath:@"filters" ofItem:tablix];
  if ([tablix.filters count] != 1)
    XCTFail(@"%@", @"the filter should reach the table");

  // Sorting, the same way.
  RDLSortExpression *sort = [[RDLSortExpression alloc] init];
  sort.expression = [RDLValue valueWithSource:@"=Fields!Port.Value"];
  sort.direction = RDLSortDirectionDescending;
  [ctx.editor setValue:[@[ sort ] mutableCopy] forKeyPath:@"sortExpressions" ofItem:tablix];

  RDLDocument *again = RDLSaveAndOpen(doc, @"settings.rdl");
  RDLTablix *back = again ? RDLFirstTablix(again.report) : nil;
  if (back == nil) {
    XCTFail(@"%@", @"the report should save and open again");
    return;
  }
  if (![back.noRowsMessage isEqualToString:@"Nothing shipped"])
    XCTFail(@"the no-rows message should be in the file, it is %@", back.noRowsMessage);
  if ([back.filters count] != 1)
    XCTFail(@"the filter should be in the file, there are %lu", (unsigned long)[back.filters count]);
  RDLFilter *backFilter = [back.filters firstObject];
  if (![[backFilter.expression source] isEqualToString:@"=Fields!Port.Value"] ||
      backFilter.oper != RDLFilterOperatorEqual ||
      ![[[backFilter.values firstObject] source] isEqualToString:@"Dover"])
    XCTFail(@"the filter should come back as it was written: %@ %ld %@",
            [backFilter.expression source], (long)backFilter.oper,
            [[backFilter.values firstObject] source]);
  if ([back.sortExpressions count] != 1 ||
      [[back.sortExpressions firstObject] direction] != RDLSortDirectionDescending)
    XCTFail(@"the sort should be in the file, there are %lu",
            (unsigned long)[back.sortExpressions count]);

  // And undo takes each of them off again.
  [[ctx.document undoManager] undo];
  [[ctx.document undoManager] undo];
  [[ctx.document undoManager] undo];
  if ([tablix.filters count] || [tablix.sortExpressions count] || [tablix.noRowsMessage length])
    XCTFail(@"undo should take all three back off: %lu filters, %lu sorts, %@",
            (unsigned long)[tablix.filters count], (unsigned long)[tablix.sortExpressions count],
            tablix.noRowsMessage);
}

// RND-03. What the designer cannot show is what a round trip loses most
// quietly: an element from someone else's namespace, which this kit keeps as
// written rather than reading. It has to survive a save, an edit somewhere
// else entirely, and the save after that.
- (void)testWhatTheDesignerDoesNotShowSurvivesAnEdit {
  NSURL *url = [RDLSamples URLForSampleWithId:@"letter"];
  NSString *xml = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL] : nil;
  if ([xml length] == 0) {
    XCTFail(@"%@", @"the letter sample should be readable as a file");
    return;
  }
  // A namespace of its own and a piece under the report: what a tool that
  // writes more than this kit reads would leave in the file.
  xml = [xml stringByReplacingOccurrencesOfString:@"<Report "
                                       withString:@"<Report xmlns:am=\"urn:rdlkit:test\" "
                                          options:0
                                            range:NSMakeRange(0, MIN((NSUInteger)400, [xml length]))];
  xml = [xml stringByReplacingOccurrencesOfString:@"</Report>"
                                       withString:@"<am:Kept Who=\"theirs\">not ours to read</am:Kept></Report>"];
  NSURL *seeded = RDLScratchURL(@"seeded.rdl");
  [xml writeToURL:seeded atomically:YES encoding:NSUTF8StringEncoding error:NULL];

  RDLDocument *doc = RDLOpen(seeded);
  if (doc == nil) {
    XCTFail(@"%@", @"a report with a piece this kit does not read should still open");
    return;
  }
  NSUInteger kept = [doc.report.preservedNodes count];
  if (kept == 0) {
    XCTFail(@"%@", @"the piece from another namespace should have been kept");
    return;
  }
  if ([[doc XMLString] rangeOfString:@"<am:Kept"].location == NSNotFound)
    XCTFail(@"the kept piece should be written back: %@",
            [[doc XMLString] substringToIndex:MIN((NSUInteger)200, [[doc XMLString] length])]);

  // An edit somewhere else: the kept pieces are found again by where they sit,
  // so an edit that moves nothing must not move them either.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithDocument:doc];
  RDLTextbox *box = nil;
  for (RDLItem *item in [doc.report allItemsIncludingNested])
    if (box == nil && [item isKindOfClass:[RDLTextbox class]])
      box = (RDLTextbox *)item;
  [ctx.editor setValue:@"Edited elsewhere" forKeyPath:@"value" ofItem:box];

  RDLDocument *again = RDLSaveAndOpen(doc, @"kept.rdl");
  if (again == nil) {
    XCTFail(@"%@", @"the report should save and open again");
    return;
  }
  if ([again.report.preservedNodes count] != kept)
    XCTFail(@"%lu kept parts became %lu", (unsigned long)kept,
            (unsigned long)[again.report.preservedNodes count]);
  NSString *written = [again XMLString];
  if ([written rangeOfString:@"<am:Kept"].location == NSNotFound ||
      [written rangeOfString:@"not ours to read"].location == NSNotFound ||
      [written rangeOfString:@"Who=\"theirs\""].location == NSNotFound)
    XCTFail(@"%@", @"the kept piece, its attribute and its text should all still be there");
  // Kept once, not once per save: this is how a file grows a copy of itself.
  NSUInteger copies = 0;
  NSRange from = NSMakeRange(0, [written length]);
  while (from.length > 0) {
    NSRange hit = [written rangeOfString:@"<am:Kept" options:0 range:from];
    if (hit.location == NSNotFound)
      break;
    copies += 1;
    from = NSMakeRange(NSMaxRange(hit), [written length] - NSMaxRange(hit));
  }
  if (copies != 1)
    XCTFail(@"the kept piece should be written once, it is written %lu times", (unsigned long)copies);

  // And what is kept is data, not a node borrowed from a document that has
  // since gone: reading it after the parse is over is what used to be unsafe.
  for (RDLPreservedNode *piece in again.report.preservedNodes) {
    if (piece.kind != NSXMLElementKind)
      continue;
    if ([piece.name length] == 0)
      XCTFail(@"%@", @"a kept element should know its own name");
    if ([piece.children count] == 0 && [piece.attributes count] == 0 && [piece.value length] == 0)
      XCTFail(@"%@ was kept with nothing in it", piece.name);
  }
}

@end
