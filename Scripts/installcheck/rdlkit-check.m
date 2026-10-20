/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What an application does with an installed RDLKit, compiled against what
// `make install` installed and nothing else (Scripts/installcheck.sh): a report
// parsed from a string, rows bound from JSON, laid out, shown in an RDLView,
// and rendered to PDF and HTML.
#import <AppKit/AppKit.h>
#import <RDLKit/RDLKit.h>

static NSString *const kReport =
    @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
     "<Width>6in</Width>"
     "<DataSets><DataSet Name=\"Items\"><Fields>"
     "<Field Name=\"Name\"><DataField>Name</DataField></Field>"
     "<Field Name=\"Qty\"><DataField>Qty</DataField></Field></Fields></DataSet></DataSets>"
     "<Body><Height>2in</Height><ReportItems>"
     "<Textbox Name=\"Total\"><Top>0in</Top><Left>0in</Left><Width>4in</Width><Height>0.3in</Height>"
     "<Paragraphs><Paragraph><TextRuns><TextRun><Value>=\"Total: \" &amp; Sum(Fields!Qty.Value, \"Items\")"
     "</Value></TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"
     "<List Name=\"Lines\"><Top>0.4in</Top><Left>0in</Left><Width>4in</Width><Height>0.3in</Height>"
     "<DataSetName>Items</DataSetName><ReportItems>"
     "<Textbox Name=\"Line\"><Top>0in</Top><Left>0in</Left><Width>4in</Width><Height>0.25in</Height>"
     "<Paragraphs><Paragraph><TextRuns><TextRun><Value>=Fields!Name.Value</Value></TextRun></TextRuns>"
     "</Paragraph></Paragraphs></Textbox></ReportItems></List>"
     "</ReportItems></Body>"
     "<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth></Page></Report>";

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSError *error = nil;
    RDLReport *report = [RDLParser reportFromXMLString:kReport error:&error];
    if (report == nil) {
      fprintf(stderr, "rdlkit-check: the report did not parse: %s\n", [[error description] UTF8String]);
      return 1;
    }
    if (![RDLGenerator bindJSONString:@"[{\"Name\":\"Bolts\",\"Qty\":3},{\"Name\":\"Nuts\",\"Qty\":4}]"
                            toDataSet:@"Items"
                             inReport:report
                                error:&error]) {
      fprintf(stderr, "rdlkit-check: the rows did not bind: %s\n", [[error description] UTF8String]);
      return 1;
    }
    NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:report parameters:@{}];
    RDLView *view = [[RDLView alloc] initWithFrame:NSMakeRect(0, 0, 612, 792)];
    [view applyPages:pages];
    NSData *pdf = [RDLGenerator PDFForReport:report parameters:@{}];
    NSString *html = [RDLGenerator HTMLStringForReport:report parameters:@{}];
    BOOL ok = [pages count] == 1 && [view.pages count] == 1 && [pdf length] > 4 &&
              memcmp([pdf bytes], "%PDF", 4) == 0 && [html rangeOfString:@"Total: 7"].location != NSNotFound &&
              [html rangeOfString:@"Nuts"].location != NSNotFound;
    printf("rdlkit-check: %lu page(s), a PDF of %lu bytes, HTML %s\n", (unsigned long)[pages count],
           (unsigned long)[pdf length], ok ? "with the rows" : "WITHOUT the rows");
    return ok ? 0 : 1;
  }
}
