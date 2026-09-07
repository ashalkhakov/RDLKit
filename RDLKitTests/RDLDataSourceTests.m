/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import "RDLKit.h"

// Datasets read out of documents: JSON with a JSONPath, XML with an XPath, and
// delimited or fixed-width text. The JSONPath language itself is its own
// module and has its own tests; what is checked here is that a document
// becomes rows. This is what a local report viewer binds to --
// files the host already has, or content carried in the report itself.
@interface RDLDataSourceTests : XCTestCase
@end

@implementation RDLDataSourceTests

- (RDLDataSet *)dataSetNamed:(NSString *)name query:(NSString *)query source:(NSString *)source {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = name;
  ds.dataSourceName = source;
  ds.commandText = query;
  return ds;
}

- (NSData *)data:(NSString *)text {
  return [text dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Providers

- (void)testJSONProviderReadsRowsAndKeepsNesting {
  NSString *json = @"{\"Order\":[{\"No\":\"A-1\",\"Total\":42,"
                    "\"Lines\":[{\"Item\":\"Bowl\"},{\"Item\":\"Cup\"}]}]}";
  RDLJSONDataProvider *provider = [[RDLJSONDataProvider alloc] init];
  NSError *err = nil;
  NSArray *rows = [provider rowsFromData:[self data:json]
                                 dataSet:[self dataSetNamed:@"Orders" query:@"$.Order[*]" source:@"S"]
                              properties:@{}
                                   error:&err];
  if ([rows count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"rows: %@ (%@)", rows, err]);
    return;
  }
  if (![rows[0][@"No"] isEqualToString:@"A-1"])
    XCTFail(@"%@", @"the order's own fields should be fields of the row");
  // Nested structure stays in the row: that is what a nested region reads, and
  // what an aggregate over Fields!Lines.Value counts.
  NSArray *lines = rows[0][@"Lines"];
  if ([lines count] != 2 || ![lines[0][@"Item"] isEqualToString:@"Bowl"])
    XCTFail(@"%@", @"the nested lines should have survived");

  // A document that is already an array of objects needs no query at all.
  NSArray *plain = [provider rowsFromData:[self data:@"[{\"A\":1},{\"A\":2}]"]
                                  dataSet:[self dataSetNamed:@"Plain" query:@"" source:@"S"]
                               properties:@{}
                                    error:NULL];
  if ([plain count] != 2)
    XCTFail(@"%@", @"an array of objects is the rows");

  // Bad JSON is an error, not an empty report.
  if ([provider rowsFromData:[self data:@"{oops"]
                     dataSet:[self dataSetNamed:@"Bad" query:@"$" source:@"S"]
                  properties:@{}
                       error:NULL] != nil)
    XCTFail(@"%@", @"unparseable JSON should fail rather than yield no rows");
}

- (void)testXMLProviderReadsElementsAsRows {
  NSString *xml = @"<Orders>"
                   "<Order No=\"A-1\"><Customer>Vale</Customer>"
                   "<Line Item=\"Bowl\"/><Line Item=\"Cup\"/></Order>"
                   "<Order No=\"A-2\"><Customer>Reed</Customer><Line Item=\"Jug\"/></Order>"
                   "</Orders>";
  RDLXMLDataProvider *provider = [[RDLXMLDataProvider alloc] init];
  NSError *err = nil;
  NSArray *rows = [provider rowsFromData:[self data:xml]
                                 dataSet:[self dataSetNamed:@"Orders"
                                                      query:@"//Order"
                                                     source:@"S"]
                              properties:@{}
                                   error:&err];
  if ([rows count] != 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"rows: %@ (%@)", rows, err]);
    return;
  }
  // An attribute and a leaf child are both fields, which is how these files
  // are written and not something a report should have to care about.
  if (![rows[0][@"No"] isEqualToString:@"A-1"] ||
      ![rows[0][@"Customer"] isEqualToString:@"Vale"])
    XCTFail(@"%@", [NSString stringWithFormat:@"first row: %@", rows[0]]);
  // The repeated child is a list, ready for a nested region.
  NSArray *lines = rows[0][@"Line"];
  if (![lines isKindOfClass:[NSArray class]] || [lines count] != 2 ||
      ![lines[0][@"Item"] isEqualToString:@"Bowl"])
    XCTFail(@"%@", [NSString stringWithFormat:@"nested lines: %@", rows[0][@"Line"]]);

  // With no XPath, the root's children are the rows.
  NSArray *implied = [provider rowsFromData:[self data:xml]
                                    dataSet:[self dataSetNamed:@"Orders" query:@"" source:@"S"]
                                 properties:@{}
                                      error:NULL];
  if ([implied count] != 2)
    XCTFail(@"%@", @"without a query the root's element children are the rows");
}

- (void)testCSVProviderReadsDelimitedAndFixedWidth {
  RDLCSVDataProvider *provider = [[RDLCSVDataProvider alloc] init];
  RDLDataSet *ds = [self dataSetNamed:@"Rows" query:@"" source:@"S"];

  // Headers, quoted fields, and a comma inside one.
  NSString *csv = @"Item,Qty,Note\nBowl,2,\"Blue, glazed\"\nCup,1,Plain\n";
  NSArray *rows = [provider rowsFromData:[self data:csv] dataSet:ds properties:@{} error:NULL];
  if ([rows count] != 2 || ![rows[0][@"Note"] isEqualToString:@"Blue, glazed"] ||
      ![rows[1][@"Item"] isEqualToString:@"Cup"])
    XCTFail(@"%@", [NSString stringWithFormat:@"csv rows: %@", rows]);

  // Tabs, named because nobody can type one into a connect string.
  NSString *tsv = @"Item\tQty\nBowl\t2\n";
  NSArray *tabbed = [provider rowsFromData:[self data:tsv]
                                   dataSet:ds
                                properties:@{@"delimiter" : @"Tab"}
                                     error:NULL];
  if ([tabbed count] != 1 || ![tabbed[0][@"Qty"] isEqualToString:@"2"])
    XCTFail(@"%@", [NSString stringWithFormat:@"tab-separated: %@", tabbed]);

  // No headers: the columns are named for their position, which is what the
  // designer will show as field names.
  NSArray *headerless = [provider rowsFromData:[self data:@"Bowl,2\nCup,1\n"]
                                       dataSet:ds
                                    properties:@{@"hasheaders" : @"false"}
                                         error:NULL];
  if ([headerless count] != 2 || ![headerless[0][@"Column1"] isEqualToString:@"Bowl"])
    XCTFail(@"%@", [NSString stringWithFormat:@"headerless: %@", headerless]);

  // Fixed width, trimmed.
  NSArray *fixed = [provider rowsFromData:[self data:@"Item      Qty\nBowl      2  \n"]
                                  dataSet:ds
                               properties:@{@"widths" : @"10,3"}
                                    error:NULL];
  if ([fixed count] != 1 || ![fixed[0][@"Item"] isEqualToString:@"Bowl"] ||
      ![fixed[0][@"Qty"] isEqualToString:@"2"])
    XCTFail(@"%@", [NSString stringWithFormat:@"fixed width: %@", fixed]);
}

#pragma mark - Binding a whole report

- (RDLReport *)reportWithProvider:(NSString *)provider connect:(NSString *)connect
                            query:(NSString *)query {
  RDLReport *r = [RDLReport emptyReportNamed:@"Bound"];
  RDLDataSource *src = [[RDLDataSource alloc] init];
  src.name = @"Docs";
  src.dataProvider = provider;
  src.connectString = connect;
  [r.dataSources removeAllObjects];
  [r.dataSources addObject:src];
  [r.dataSets addObject:[self dataSetNamed:@"Rows" query:query source:@"Docs"]];
  return r;
}

- (void)testBinderFillsDatasetsFromTheReportsOwnSources {
  // Content carried in the report, which is what jsondata= is for.
  RDLReport *inlineJSON = [self reportWithProvider:@"JSON"
                                           connect:@"jsondata={\"Row\":[{\"A\":1},{\"A\":2}]}"
                                             query:@"$.Row[*]"];
  RDLDataBinder *binder = [[RDLDataBinder alloc] initWithBaseURL:nil];
  NSError *err = nil;
  if (![binder bindReport:inlineJSON error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"inline JSON did not bind: %@", err]);
  RDLDataSet *ds = [inlineJSON dataSetNamed:@"Rows"];
  if ([ds.rows count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"rows: %@", ds.rows]);
  // Fields are inferred only because the dataset declared none.
  if ([[ds fieldNames] count] != 1 || ![[ds fieldNames][0] isEqualToString:@"A"])
    XCTFail(@"%@", [NSString stringWithFormat:@"fields: %@", [ds fieldNames]]);

  // A file beside the report, named relatively -- the ordinary case.
  NSString *dir = NSTemporaryDirectory();
  NSString *file = [dir stringByAppendingPathComponent:@"rdlkit-rows.csv"];
  [@"Item,Qty\nBowl,2\nCup,1\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding
                                      error:NULL];
  RDLReport *csv = [self reportWithProvider:@"CSV" connect:@"rdlkit-rows.csv" query:@""];
  RDLDataBinder *relative =
      [[RDLDataBinder alloc] initWithBaseURL:[NSURL fileURLWithPath:dir isDirectory:YES]];
  if (![relative bindReport:csv error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"csv did not bind: %@", err]);
  if ([[csv dataSetNamed:@"Rows"].rows count] != 2)
    XCTFail(@"%@", @"the csv file should have supplied two rows");
  [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];

  // A remote document is not fetched unless the host says so: a report is a
  // document that may have come from anywhere.
  RDLReport *remote = [self reportWithProvider:@"JSON"
                                       connect:@"jsondoc=https://example.com/rows.json"
                                         query:@"$[*]"];
  RDLDataBinder *careful = [[RDLDataBinder alloc] initWithBaseURL:nil];
  if ([careful bindReport:remote error:NULL])
    XCTFail(@"%@", @"a remote document should not be fetched by default");
  if ([careful.notes count] != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"notes: %@", careful.notes]);

  // A provider nobody implements is left alone rather than failing the report:
  // its rows may be supplied in code, which is how a host binds its own data.
  RDLReport *unknown = [self reportWithProvider:@"SQL" connect:@"server=..." query:@"SELECT 1"];
  RDLDataSet *supplied = [unknown dataSetNamed:@"Rows"];
  supplied.rows = @[ @{@"A" : @1} ];
  RDLDataBinder *skipping = [[RDLDataBinder alloc] initWithBaseURL:nil];
  if (![skipping bindReport:unknown error:NULL])
    XCTFail(@"%@", @"a report with nothing to bind is not a failure");
  if ([supplied.rows count] != 1)
    XCTFail(@"%@", @"rows supplied in code should have been left alone");
}

- (void)testConnectionStringsAreReadIntoTheirParts {
  NSDictionary *json = RDLConnectionProperties(@"jsondoc=films.json");
  if (![json[@"jsondoc"] isEqualToString:@"films.json"])
    XCTFail(@"%@", [NSString stringWithFormat:@"jsondoc: %@", json]);
  NSDictionary *csv = RDLConnectionProperties(@"data.csv;HasHeaders=true;Delimiter=Tab");
  if (![csv[@""] isEqualToString:@"data.csv"] || ![csv[@"hasheaders"] isEqualToString:@"true"] ||
      ![csv[@"delimiter"] isEqualToString:@"Tab"])
    XCTFail(@"%@", [NSString stringWithFormat:@"csv properties: %@", csv]);
  if (RDLDataProviderKindFromString(@"json") != RDLDataProviderKindJSON ||
      RDLDataProviderKindFromString(@"XML") != RDLDataProviderKindXML ||
      RDLDataProviderKindFromString(@"Oracle") != RDLDataProviderKindUnspecified)
    XCTFail(@"%@", @"provider names are matched whatever their case, and only ours are known");
}

// A dataset points at its source by name, the way the file does. The link is
// checked rather than made into a pointer: a name survives a copied item, an
// undone removal and a file that names a source it does not have -- and this
// is what catches the last of those instead of the report quietly rendering
// empty.
- (void)testADatasetNamingAMissingSourceIsReported {
  RDLReport *r = [self reportWithProvider:@"JSON" connect:@"jsondata=[]" query:@"$[*]"];
  if ([[RDLChecker checkReport:r] count] != 0)
    XCTFail(@"%@", @"a dataset naming a source the report has is fine");

  [r dataSetNamed:@"Rows"].dataSourceName = @"Gone";
  BOOL reported = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:r])
    if ([d.rule isEqualToString:@"unknown-data-source"])
      reported = YES;
  if (!reported)
    XCTFail(@"%@", @"a dangling data source name should be reported");

  // Naming none is not an error: that is a dataset whose rows are supplied in
  // code, which is how a host binds its own data.
  [r dataSetNamed:@"Rows"].dataSourceName = @"";
  for (RDLDiagnostic *d in [RDLChecker checkReport:r])
    if ([d.rule isEqualToString:@"unknown-data-source"])
      XCTFail(@"%@", @"a dataset with no source named is not a broken link");

  // And the name is what survives: a dataset carried into another document
  // keeps it, where a pointer into the first report's objects could not.
  RDLReport *elsewhere = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r]
                                                  error:NULL];
  [r dataSetNamed:@"Rows"].dataSourceName = @"Docs";
  RDLReport *carried = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r]
                                                error:NULL];
  if (![[carried dataSetNamed:@"Rows"].dataSourceName isEqualToString:@"Docs"])
    XCTFail(@"%@", @"the link is a name, and a name is what is written and read");
  if ([elsewhere dataSetNamed:@"Rows"] == nil)
    XCTFail(@"%@", @"the dataset should have survived the round trip either way");
}

// The link is a name in the file and a pointer in memory, and the two are kept
// honest about each other: whichever is set, the other follows or is dropped.
// Nothing is allowed to hold a pointer that disagrees with the name, because
// the name is what gets written.
- (void)testTheResolvedDataSourcePointerAgreesWithTheName {
  RDLReport *r = [self reportWithProvider:@"JSON" connect:@"jsondata=[]" query:@"$[*]"];
  RDLDataSet *ds = [r dataSetNamed:@"Rows"];
  RDLDataSource *docs = [r dataSourceNamed:@"Docs"];

  // Nothing has resolved it yet: a report built in code is just names.
  if (ds.dataSource != nil)
    XCTFail(@"%@", @"the pointer is filled in by resolving, not by wishing");
  [r resolveDataSources];
  if (ds.dataSource != docs)
    XCTFail(@"%@", @"resolving should point the dataset at the source it names");

  // Setting the pointer sets the name.
  RDLDataSource *other = [[RDLDataSource alloc] init];
  other.name = @"Other";
  other.dataProvider = @"CSV";
  [r.dataSources addObject:other];
  ds.dataSource = other;
  if (![ds.dataSourceName isEqualToString:@"Other"])
    XCTFail(@"%@", [NSString stringWithFormat:@"name after pointing elsewhere: %@",
                                              ds.dataSourceName]);

  // Setting the name to something else drops the pointer rather than leaving
  // it pointing at the old source.
  ds.dataSourceName = @"Docs";
  if (ds.dataSource != nil)
    XCTFail(@"%@", @"a pointer that disagrees with the name is a lie");
  [r resolveDataSources];
  if (ds.dataSource != docs)
    XCTFail(@"%@", @"and resolving puts it back");
  // Setting the name it already has leaves the pointer alone.
  ds.dataSourceName = @"Docs";
  if (ds.dataSource != docs)
    XCTFail(@"%@", @"the same name is not a change");

  // A source that is no longer in the report resolves to nothing, and the name
  // stays -- which is what gets written, and what an undone removal restores.
  [r.dataSources removeObject:docs];
  [r resolveDataSources];
  if (ds.dataSource != nil || ![ds.dataSourceName isEqualToString:@"Docs"])
    XCTFail(@"%@", @"a removed source leaves the name behind and no pointer");
  [r.dataSources addObject:docs];
  [r resolveDataSources];
  if (ds.dataSource != docs)
    XCTFail(@"%@", @"putting the source back reconnects the dataset");

  // Reading a file resolves it, so a parsed report arrives connected.
  RDLReport *parsed = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLDataSet *parsedSet = [parsed dataSetNamed:@"Rows"];
  if (parsedSet.dataSource == nil ||
      ![parsedSet.dataSource.name isEqualToString:parsedSet.dataSourceName])
    XCTFail(@"%@", @"a report read from a file arrives with its links resolved");
  // And binding works through the pointer, resolving first for a report that
  // was built in code.
  RDLReport *fresh = [self reportWithProvider:@"JSON"
                                      connect:@"jsondata=[{\"A\":1}]"
                                        query:@"$[*]"];
  if (![[[RDLDataBinder alloc] init] bindReport:fresh error:NULL] ||
      [[fresh dataSetNamed:@"Rows"].rows count] != 1)
    XCTFail(@"%@", @"binding should resolve the link itself");
  if ([fresh dataSetNamed:@"Rows"].dataSource == nil)
    XCTFail(@"%@", @"and leave it resolved");
}

@end
