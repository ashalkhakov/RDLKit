#import "RDLSamples.h"
#import "RDLKit.h"

static NSString *const kInk = @"#1a1916";
static NSString *const kMuted = @"#5c574e";
static NSString *const kShade = @"#ece6d8";

static void RDLApplyStyle(RDLItem *it, NSString *font, RDLLength *size, RDLFontWeight weight,
                           NSString *color, RDLTextAlign align) {
  if (font)
    it.style.fontFamily = font;
  if (size)
    it.style.fontSize = size;
  if (weight != RDLFontWeightUnspecified)
    it.style.fontWeight = weight;
  if (color)
    it.style.color = color;
  if (align != RDLTextAlignUnspecified)
    it.style.textAlign = align;
}

static RDLItem *RDLTB(NSString *name, NSString *value, CGFloat x, CGFloat y, CGFloat w, CGFloat h,
                       NSString *font, RDLLength *size, RDLFontWeight weight, NSString *color,
                       RDLTextAlign align) {
  RDLTextbox *it = [[RDLTextbox alloc] init];
  it.name = name;
  it.value = value;
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = h;
  RDLApplyStyle(it, font, size, weight, color, align);
  return it;
}

static RDLItem *RDLMakeLine(NSString *name, CGFloat x, CGFloat y, CGFloat w) {
  RDLLine *it = [[RDLLine alloc] init];
  it.name = name;
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = 0.02;
  it.style.color = kInk;
  return it;
}

static RDLItem *RDLRect(NSString *name, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSString *bg) {
  RDLRectangle *it = [[RDLRectangle alloc] init];
  it.name = name;
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = h;
  it.style.backgroundColor = bg ?: kShade;
  return it;
}

static NSDictionary *RDLCol(NSString *header, NSString *value, CGFloat width, NSString *align) {
  return @{
    @"header" : header ?: @"",
    @"value" : value ?: @"",
    @"width" : @(width),
    @"align" : align ?: @"Left"
  };
}

static RDLDataSet *RDLSet(NSString *name, NSArray<NSString *> *fields, NSArray *rows) {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = name;
  ds.dataSourceName = @"Demo";
  // The samples declare fields by name; the types are whatever the rows hold.
  [ds setFieldNames:fields];
  ds.rows = rows;
  return ds;
}

static RDLParameter *RDLPar(NSString *name, NSString *def) {
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = name;
  p.dataType = RDLParameterDataTypeString;
  p.defaultValue = [RDLValue valueWithSource:def];
  return p;
}

static RDLItem *RDLMakeTablix(NSString *name, NSString *ds, CGFloat x, CGFloat y, CGFloat w,
                           CGFloat headerH, CGFloat rowH, NSArray *cols) {
  RDLTablix *it = [[RDLTablix alloc] init];
  it.name = name;
  it.dataSetName = ds;
  it.left = x;
  it.top = y;
  it.width = w;
  it.headerHeight = headerH;
  it.rowHeight = rowH;
  it.height = headerH + rowH;
  it.columnSpecs = cols;
  [it rebuildTablix];
  return it;
}

@implementation RDLSamples

+ (NSArray<NSDictionary *> *)catalog {
  return @[
    @{
      @"id" : @"crosstab",
      @"title" : @"Regional Sales",
      @"kicker" : @"Crosstab",
      @"blurb" : @"Region and city against year and quarter — two groups on each axis, one total where they meet."
    },
    @{
      @"id" : @"finish",
      @"title" : @"Workshop by Finish",
      @"kicker" : @"Groups",
      @"blurb" : @"Tablix grouped by finish — Lookup catalog rate, row header, details, and a subtotal."
    },
    @{
      @"id" : @"invoice",
      @"title" : @"Atelier Invoice",
      @"kicker" : @"Accounts",
      @"blurb" : @"Workshop invoice with bound line items, tax, and a running folio."
    },
    @{
      @"id" : @"packing",
      @"title" : @"Harbor Packing Slip",
      @"kicker" : @"Fulfillment",
      @"blurb" : @"Ship-to block, carton list, and bindery notes on letter stock."
    },
    @{
      @"id" : @"ledger",
      @"title" : @"Quarterly Ledger",
      @"kicker" : @"Figures",
      @"blurb" : @"Column chart of receipts with a monthly tablix and quarter total."
    },
    @{
      @"id" : @"manifest",
      @"title" : @"Harbor Manifest",
      @"kicker" : @"Data sources",
      @"blurb" : @"One report reading a JSON document with JSONPath — nested crates flattened, a filter for the heavy ones — and a second table from XML with an XPath."
    },
    @{
      @"id" : @"kiln",
      @"title" : @"Kiln Log",
      @"kicker" : @"Fields & filters",
      @"blurb" : @"Calculated fields worked out per firing, a dataset filter that drops the empty runs, and a second table filtered to the batches worth a look."
    },
    @{
      @"id" : @"roster",
      @"title" : @"Studio Roster",
      @"kicker" : @"Directory",
      @"blurb" : @"Names, desks, and extensions — a clean personnel listing."
    },
    @{
      @"id" : @"letter",
      @"title" : @"Blank Letter",
      @"kicker" : @"Stationery",
      @"blurb" : @"Empty letter with a named header, body, and centered folio."
    }
  ];
}

+ (RDLReport *)reportWithId:(NSString *)sampleId {
  if ([sampleId isEqualToString:@"invoice"])
    return [self atelierInvoice];
  if ([sampleId isEqualToString:@"packing"])
    return [self packingSlip];
  if ([sampleId isEqualToString:@"ledger"])
    return [self salesLedger];
  if ([sampleId isEqualToString:@"roster"])
    return [self studioRoster];
  if ([sampleId isEqualToString:@"finish"])
    return [self workshopByFinish];
  if ([sampleId isEqualToString:@"crosstab"])
    return [self regionalSales];
  if ([sampleId isEqualToString:@"kiln"])
    return [self kilnLog];
  if ([sampleId isEqualToString:@"manifest"])
    return [self harborManifest];
  return [self blankLetter];
}

+ (RDLReport *)blankLetter {
  RDLReport *r = [RDLReport emptyReportNamed:@"Letter"];
  r.reportDescription = @"Blank letter with running header and folio.";
  r.author = @"RDLDesigner";
  [r.pageHeader.items addObject:RDLTB(@"Brand", @"RDL", 0, 0.08, 2.2, 0.28, @"Georgia", [RDLLength points:11],
                                       RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"DocTitle", @"=Parameters!Title.Value", 2.2, 0.1, 5.3, 0.24,
                                       @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.42, 7.5)];
  [r.body.items addObject:RDLTB(@"Salutation", @"Dear reader,", 0, 0.2, 7.5, 0.3, @"Georgia",
                                 [RDLLength points:12], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.body.items
      addObject:RDLTB(@"BodyCopy",
                       @"Set the type. Bind a field. The page is a measure of 51 picas — enough "
                       @"room for a proper letter, an invoice, or a ledger.",
                       0, 0.6, 7.5, 0.8, @"Georgia", [RDLLength points:11], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.02, 7.5)];
  [r.pageFooter.items
      addObject:RDLTB(@"Folio", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages",
                       0, 0.1, 7.5, 0.22, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];
  [r.parameters addObject:RDLPar(@"Title", @"Untitled letter")];
  return r;
}

+ (RDLReport *)atelierInvoice {
  RDLReport *r = [RDLReport emptyReportNamed:@"Atelier Invoice"];
  r.reportDescription = @"Workshop invoice for Merrick & Vale cabinetmakers.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"InvoiceNo", @"MV-1842")];
  [r.parameters addObject:RDLPar(@"InvoiceDate", @"26 Aug 2026")];
  [r.parameters addObject:RDLPar(@"BillTo", @"Northlight Editorial")];
  [r.parameters addObject:RDLPar(@"BillAddr", @"14 Reed Street, Portland")];
  [r.dataSets addObject:RDLSet(@"Items", @[ @"Sku", @"Description", @"Qty", @"Unit", @"Amount" ], @[
               @{
                 @"Sku" : @"WV-12",
                 @"Description" : @"Walnut writing desk, oil finish",
                 @"Qty" : @1,
                 @"Unit" : @1840,
                 @"Amount" : @1840
               },
               @{
                 @"Sku" : @"CH-04",
                 @"Description" : @"White oak side chair",
                 @"Qty" : @2,
                 @"Unit" : @420,
                 @"Amount" : @840
               },
               @{
                 @"Sku" : @"LT-09",
                 @"Description" : @"Turned brass desk lamp",
                 @"Qty" : @1,
                 @"Unit" : @265,
                 @"Amount" : @265
               },
               @{
                 @"Sku" : @"SH-02",
                 @"Description" : @"Linen shade, natural",
                 @"Qty" : @1,
                 @"Unit" : @48,
                 @"Amount" : @48
               }
             ])];
  r.pageHeader.height = 0.62;
  [r.pageHeader.items addObject:RDLTB(@"Studio", @"MERRICK & VALE", 0, 0.02, 4.6, 0.28, @"Georgia",
                                       [RDLLength points:13], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Tag", @"Cabinetmakers · Est. 1978", 0, 0.28, 4.6, 0.18,
                                       @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"InvLabel", @"INVOICE", 4.6, 0.02, 2.9, 0.28, @"Helvetica",
                                       [RDLLength points:11], RDLFontWeightBold, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLTB(@"InvNo", @"=Parameters!InvoiceNo.Value", 4.6, 0.26, 2.9, 0.2,
                                       @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kInk, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 5.4;
  [r.body.items addObject:RDLTB(@"BillLbl", @"Bill to", 0, 0.12, 3.6, 0.18, @"Helvetica", [RDLLength points:8],
                                 RDLFontWeightBold, kMuted, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"BillName", @"=Parameters!BillTo.Value", 0, 0.3, 3.6, 0.22,
                                 @"Georgia", [RDLLength points:12], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"BillAddr", @"=Parameters!BillAddr.Value", 0, 0.52, 3.6, 0.2,
                                 @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"DateLbl", @"Date", 5.2, 0.12, 2.3, 0.18, @"Helvetica", [RDLLength points:8],
                                 RDLFontWeightBold, kMuted, RDLTextAlignRight)];
  [r.body.items addObject:RDLTB(@"DateVal", @"=Parameters!InvoiceDate.Value", 5.2, 0.3, 2.3, 0.22,
                                 @"Georgia", [RDLLength points:12], RDLFontWeightNormal, kInk, RDLTextAlignRight)];
  [r.body.items addObject:RDLMakeTablix(@"LineItems", @"Items", 0, 1.0, 7.5, 0.32, 0.3, @[
                 RDLCol(@"SKU", @"=Fields!Sku.Value", 0.9, @"Left"),
                 RDLCol(@"Description", @"=Fields!Description.Value", 3.5, @"Left"),
                 RDLCol(@"Qty", @"=Fields!Qty.Value", 0.7, @"Right"),
                 RDLCol(@"Unit", @"=Fields!Unit.Value", 1.1, @"Right"),
                 RDLCol(@"Amount", @"=Fields!Amount.Value", 1.3, @"Right")
               ])];
  [r.body.items addObject:RDLTB(@"SubLbl", @"Subtotal", 4.6, 2.55, 1.4, 0.24, @"Helvetica", [RDLLength points:9],
                                 RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.body.items addObject:RDLTB(@"SubVal", @"=Format(Sum(Fields!Amount.Value), \"C\")", 6.0, 2.55,
                                 1.5, 0.24, @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kInk, RDLTextAlignRight)];
  [r.body.items addObject:RDLTB(@"TaxLbl", @"Tax 8%", 4.6, 2.8, 1.4, 0.24, @"Helvetica", [RDLLength points:9],
                                 RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.body.items addObject:RDLTB(@"TaxVal", @"=Format(Sum(Fields!Amount.Value) * 0.08, \"C\")", 6.0,
                                 2.8, 1.5, 0.24, @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kInk, RDLTextAlignRight)];
  [r.body.items addObject:RDLMakeLine(@"TotRule", 4.6, 3.1, 2.9)];
  [r.body.items addObject:RDLTB(@"TotLbl", @"Amount due", 4.6, 3.18, 1.4, 0.3, @"Georgia", [RDLLength points:11],
                                 RDLFontWeightBold, kInk, RDLTextAlignRight)];
  [r.body.items addObject:RDLTB(@"TotVal", @"=Format(Sum(Fields!Amount.Value) * 1.08, \"C\")", 6.0,
                                 3.18, 1.5, 0.3, @"Georgia", [RDLLength points:11], RDLFontWeightBold, kInk, RDLTextAlignRight)];
  [r.body.items
      addObject:RDLTB(@"Note",
                       @"Payable within 14 days. Pieces are made to order in the East End "
                       @"workshop. Thank you.",
                       0, 3.7, 5.4, 0.5, @"Georgia", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"Addr", @"Merrick & Vale  ·  88 Binder Lane  ·  Almaty", 0,
                                       0.12, 4.8, 0.2, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted,
                                       RDLTextAlignLeft)];
  [r.pageFooter.items
      addObject:RDLTB(@"Folio", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages",
                       4.8, 0.12, 2.7, 0.2, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  return r;
}

+ (RDLReport *)packingSlip {
  RDLReport *r = [RDLReport emptyReportNamed:@"Harbor Packing Slip"];
  r.reportDescription = @"North Wharf packing slip with ship-to block and carton list.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"OrderNo", @"NW-2209")];
  [r.parameters addObject:RDLPar(@"ShipTo", @"The Reed Bindery")];
  [r.parameters addObject:RDLPar(@"ShipAddr", @"6 Dock Road, Astoria")];
  [r.dataSets addObject:RDLSet(@"Carton", @[ @"Item", @"Finish", @"Qty", @"Carton" ], @[
               @{
                 @"Item" : @"Octavo cloth case",
                 @"Finish" : @"Sage buckram",
                 @"Qty" : @12,
                 @"Carton" : @"A"
               },
               @{
                 @"Item" : @"Endsheet packet",
                 @"Finish" : @"Laid ivory",
                 @"Qty" : @12,
                 @"Carton" : @"A"
               },
               @{
                 @"Item" : @"Spine ribbon",
                 @"Finish" : @"Navy",
                 @"Qty" : @12,
                 @"Carton" : @"B"
               },
               @{
                 @"Item" : @"Title foil",
                 @"Finish" : @"Blind stamp",
                 @"Qty" : @1,
                 @"Carton" : @"B"
               }
             ])];
  [r.pageHeader.items addObject:RDLTB(@"Brand", @"NORTH WHARF", 0, 0.04, 4, 0.26, @"Georgia",
                                       [RDLLength points:13], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Kind", @"PACKING SLIP", 4, 0.08, 3.5, 0.22, @"Helvetica",
                                       [RDLLength points:10], RDLFontWeightBold, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.42, 7.5)];
  [r.body.items addObject:RDLRect(@"ShipBox", 0, 0.15, 3.6, 1.15, kShade)];
  [r.body.items addObject:RDLTB(@"ShipLbl", @"Ship to", 0.12, 0.22, 3.3, 0.18, @"Helvetica", [RDLLength points:8],
                                 RDLFontWeightBold, kMuted, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"ShipName", @"=Parameters!ShipTo.Value", 0.12, 0.42, 3.3, 0.28,
                                 @"Georgia", [RDLLength points:13], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"ShipAddr", @"=Parameters!ShipAddr.Value", 0.12, 0.72, 3.3, 0.4,
                                 @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"OrdLbl", @"Order", 4.2, 0.22, 3.3, 0.18, @"Helvetica", [RDLLength points:8],
                                 RDLFontWeightBold, kMuted, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"OrdVal", @"=Parameters!OrderNo.Value", 4.2, 0.42, 3.3, 0.28,
                                 @"Georgia", [RDLLength points:13], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"ShipDate", @"=Globals!ExecutionTime", 4.2, 0.72, 3.3, 0.22,
                                 @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.body.items addObject:RDLMakeTablix(@"CartonTable", @"Carton", 0, 1.55, 7.5, 0.3, 0.28, @[
                 RDLCol(@"Item", @"=Fields!Item.Value", 3.0, @"Left"),
                 RDLCol(@"Finish", @"=Fields!Finish.Value", 2.2, @"Left"),
                 RDLCol(@"Qty", @"=Fields!Qty.Value", 1.0, @"Right"),
                 RDLCol(@"Ctn", @"=Fields!Carton.Value", 1.3, @"Center")
               ])];
  [r.body.items addObject:RDLTB(@"Note",
                                 @"Inspect on arrival. Shortages must be noted on the carrier's "
                                 @"copy. Cases ship standing, spines to the left.",
                                 0, 3.1, 7.5, 0.5, @"Georgia", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items
      addObject:RDLTB(@"F", @"=\"North Wharf Bindery  ·  slip \" & Parameters!OrderNo.Value", 0,
                       0.12, 7.5, 0.2, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  return r;
}

+ (RDLReport *)salesLedger {
  RDLReport *r = [RDLReport emptyReportNamed:@"Quarterly Ledger"];
  r.reportDescription = @"Q3 sales by month with a column chart and totals.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"Quarter", @"Q3 2026")];
  [r.parameters addObject:RDLPar(@"House", @"RDLDesigner Press")];
  [r.dataSets addObject:RDLSet(@"Months", @[ @"Month", @"Orders", @"Total" ], @[
               @{@"Month" : @"July", @"Orders" : @42, @"Total" : @18640},
               @{@"Month" : @"August", @"Orders" : @51, @"Total" : @22410},
               @{@"Month" : @"September", @"Orders" : @47, @"Total" : @20115}
             ])];
  [r.pageHeader.items addObject:RDLTB(@"House", @"=Parameters!House.Value", 0, 0.02, 4.5, 0.24,
                                       @"Georgia", [RDLLength points:12], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Qtr", @"=Parameters!Quarter.Value", 4.5, 0.04, 3, 0.22,
                                       @"Helvetica", [RDLLength points:10], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLTB(@"Kicker", @"Sales ledger", 0, 0.26, 7.5, 0.18, @"Helvetica",
                                       [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 4.6;
  RDLChart *chart = [[RDLChart alloc] init];
  chart.name = @"ByMonth";
  chart.left = 0;
  chart.top = 0.15;
  chart.width = 7.5;
  chart.height = 2.4;
  chart.dataSetName = @"Months";
  chart.chartType = RDLChartTypeColumn;
  chart.categoryField = @"Month";
  chart.valueField = @"Total";
  chart.title = @"Net receipts";
  [r.body.items addObject:chart];
  [r.body.items addObject:RDLMakeTablix(@"MonthTable", @"Months", 0, 2.7, 7.5, 0.3, 0.28, @[
                 RDLCol(@"Month", @"=Fields!Month.Value", 2.5, @"Left"),
                 RDLCol(@"Orders", @"=Fields!Orders.Value", 2.5, @"Right"),
                 RDLCol(@"Net", @"=Fields!Total.Value", 2.5, @"Right")
               ])];
  [r.body.items addObject:RDLTB(@"SumLbl", @"Quarter total", 0, 4.05, 4, 0.3, @"Georgia", [RDLLength points:12],
                                 RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"SumVal", @"=Format(Sum(Fields!Total.Value), \"C\")", 4, 4.05, 3.5,
                                 0.3, @"Georgia", [RDLLength points:12], RDLFontWeightBold, kInk, RDLTextAlignRight)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"F", @"=\"Confidential  ·  \" & Globals!ReportName", 0, 0.12,
                                       7.5, 0.2, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  return r;
}

+ (RDLReport *)studioRoster {
  RDLReport *r = [RDLReport emptyReportNamed:@"Studio Roster"];
  r.reportDescription = @"Directory of the press — names, desks, and extensions.";
  r.author = @"RDLDesigner";
  [r.dataSets addObject:RDLSet(@"People", @[ @"Name", @"Desk", @"Ext", @"City" ], @[
               @{@"Name" : @"A. Merrick", @"Desk" : @"Type", @"Ext" : @"12", @"City" : @"Almaty"},
               @{@"Name" : @"L. Vale", @"Desk" : @"Case", @"Ext" : @"14", @"City" : @"Almaty"},
               @{@"Name" : @"S. Reed", @"Desk" : @"Bindery", @"Ext" : @"21", @"City" : @"Astoria"},
               @{@"Name" : @"N. Harbor", @"Desk" : @"Ledger", @"Ext" : @"18", @"City" : @"Portland"},
               @{@"Name" : @"C. Folio", @"Desk" : @"Proof", @"Ext" : @"09", @"City" : @"Almaty"},
               @{@"Name" : @"J. RDLDesigner", @"Desk" : @"Press", @"Ext" : @"04", @"City" : @"Astoria"}
             ])];
  [r.pageHeader.items addObject:RDLTB(@"Title", @"Studio roster", 0, 0.04, 5, 0.3, @"Georgia",
                                       [RDLLength points:16], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"When", @"=Globals!ExecutionTime", 5, 0.1, 2.5, 0.22,
                                       @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.46, 7.5)];
  [r.body.items addObject:RDLMakeTablix(@"PeopleTable", @"People", 0, 0.15, 7.5, 0.3, 0.32, @[
                 RDLCol(@"Name", @"=Fields!Name.Value", 2.4, @"Left"),
                 RDLCol(@"Desk", @"=Fields!Desk.Value", 2.0, @"Left"),
                 RDLCol(@"Ext", @"=Fields!Ext.Value", 1.2, @"Right"),
                 RDLCol(@"City", @"=Fields!City.Value", 1.9, @"Left")
               ])];
  [r.body.items addObject:RDLTB(@"Count", @"=Count(Fields!Name.Value) & \" names on the floor\"", 0,
                                 2.4, 7.5, 0.24, @"Georgia", [RDLLength points:10], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"F", @"=\"Page \" & Globals!PageNumber", 0, 0.12, 7.5, 0.2,
                                       @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];
  return r;
}

// A field the report works out rather than reads, for the samples: the two
// kinds of field are a thing the designer now names, so at least one sample
// has both.
static RDLField *RDLCalc(NSString *name, NSString *expression, RDLFieldDataType type) {
  RDLField *f = [[RDLField alloc] init];
  f.name = name;
  f.value = [RDLValue valueWithSource:expression];
  f.dataType = type;
  return f;
}

// One filter, written the way the panel writes them.
static RDLFilter *RDLKeep(NSString *expression, RDLFilterOperator oper, NSString *value) {
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:expression];
  f.oper = oper;
  [f.values addObject:[RDLValue literal:value]];
  return f;
}

// The sample for the data side of a report rather than the drawing side: a
// dataset whose fields are of both kinds, a filter on the dataset itself, and
// a second table over the same dataset that filters again.
//
// The two filters are at the two levels on purpose. The dataset filter throws
// out the empty test firing before anything sees it -- which is also what
// keeps Yield from dividing by zero, and is why a filter belongs on the
// dataset and not on each table. The table filter is a question asked of one
// table only: the same rows, narrowed to the batches that cracked.
+ (RDLReport *)kilnLog {
  RDLReport *r = [RDLReport emptyReportNamed:@"Kiln Log"];
  r.reportDescription = @"Firings with calculated yield, a dataset filter, and a table filtered "
                         "to the losses.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"Season", @"Summer 2026")];

  RDLDataSet *ds = RDLSet(@"Firings", @[ @"Batch", @"Kiln", @"FiredOn", @"Pieces", @"Cracked" ], @[
    @{@"Batch" : @"B-101", @"Kiln" : @"North", @"FiredOn" : @"2026-06-03", @"Pieces" : @24, @"Cracked" : @2},
    @{@"Batch" : @"B-102", @"Kiln" : @"North", @"FiredOn" : @"2026-06-05", @"Pieces" : @30, @"Cracked" : @0},
    @{@"Batch" : @"B-103", @"Kiln" : @"South", @"FiredOn" : @"2026-06-09", @"Pieces" : @18, @"Cracked" : @5},
    @{@"Batch" : @"B-104", @"Kiln" : @"South", @"FiredOn" : @"2026-06-12", @"Pieces" : @26, @"Cracked" : @1},
    @{@"Batch" : @"B-105", @"Kiln" : @"North", @"FiredOn" : @"2026-06-16", @"Pieces" : @33, @"Cracked" : @4},
    // The kiln was run empty to test the new elements. It is in the data, and
    // the dataset filter is what keeps it out of the report.
    @{@"Batch" : @"B-000", @"Kiln" : @"North", @"FiredOn" : @"2026-06-01", @"Pieces" : @0, @"Cracked" : @0}
  ]);
  ds.fields = [ds.fields arrayByAddingObjectsFromArray:@[
    RDLCalc(@"Sound", @"=Fields!Pieces.Value - Fields!Cracked.Value", RDLFieldDataTypeInteger),
    RDLCalc(@"Yield",
            @"=Round(100 * (Fields!Pieces.Value - Fields!Cracked.Value) / Fields!Pieces.Value, 1)",
            RDLFieldDataTypeFloat)
  ]];
  [ds.filters addObject:RDLKeep(@"=Fields!Pieces.Value", RDLFilterOperatorGreaterThan, @"0")];
  [r.dataSets addObject:ds];

  [r.pageHeader.items addObject:RDLTB(@"Title", @"Kiln log", 0, 0.04, 4.5, 0.3, @"Georgia",
                                       [RDLLength points:16], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Season", @"=Parameters!Season.Value", 4.5, 0.1, 3, 0.22,
                                       @"Helvetica", [RDLLength points:10], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.46, 7.5)];

  r.body.height = 4.4;
  [r.body.items addObject:RDLMakeTablix(@"Firings", @"Firings", 0, 0.15, 7.5, 0.3, 0.28, @[
                 RDLCol(@"Batch", @"=Fields!Batch.Value", 1.3, @"Left"),
                 RDLCol(@"Kiln", @"=Fields!Kiln.Value", 1.2, @"Left"),
                 RDLCol(@"Fired", @"=Fields!FiredOn.Value", 1.5, @"Left"),
                 RDLCol(@"Pieces", @"=Fields!Pieces.Value", 1.1, @"Right"),
                 RDLCol(@"Sound", @"=Fields!Sound.Value", 1.1, @"Right"),
                 RDLCol(@"Yield %", @"=Fields!Yield.Value", 1.3, @"Right")
               ])];
  [r.body.items addObject:RDLTB(@"SoundLbl", @"Sound pieces this season", 0, 1.95, 4.5, 0.26,
                                 @"Georgia", [RDLLength points:11], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"SoundVal", @"=Sum(Fields!Sound.Value)", 4.5, 1.95, 3, 0.26,
                                 @"Georgia", [RDLLength points:11], RDLFontWeightBold, kInk, RDLTextAlignRight)];

  [r.body.items addObject:RDLTB(@"WatchLbl", @"Batches that cracked", 0, 2.4, 7.5, 0.24, @"Georgia",
                                 [RDLLength points:11], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  RDLTablix *watch = (RDLTablix *)RDLMakeTablix(@"Watch", @"Firings", 0, 2.72, 7.5, 0.3, 0.28, @[
                 RDLCol(@"Batch", @"=Fields!Batch.Value", 1.5, @"Left"),
                 RDLCol(@"Kiln", @"=Fields!Kiln.Value", 1.5, @"Left"),
                 RDLCol(@"Pieces", @"=Fields!Pieces.Value", 1.5, @"Right"),
                 RDLCol(@"Cracked", @"=Fields!Cracked.Value", 1.5, @"Right"),
                 RDLCol(@"Yield %", @"=Fields!Yield.Value", 1.5, @"Right")
               ]);
  [watch.filters addObject:RDLKeep(@"=Fields!Cracked.Value", RDLFilterOperatorGreaterThanOrEqual, @"2")];
  [r.body.items addObject:watch];

  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"F", @"=\"Page \" & Globals!PageNumber", 0, 0.12, 7.5, 0.2,
                                       @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];
  return r;
}

// A dataset that reads a document rather than carrying its rows: the source
// says where and what kind, the query says which part of it. Fields are
// declared rather than discovered, because a discovered order is whatever
// -allKeys happens to give and a report's columns should not depend on that.
static RDLDataSet *RDLReading(NSString *name, NSString *source, NSString *query,
                              NSArray<NSString *> *fields) {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = name;
  ds.dataSourceName = source;
  ds.commandText = query;
  [ds setFieldNames:fields];
  return ds;
}

static RDLDataSource *RDLDocumentSource(NSString *name, NSString *provider, NSString *connect) {
  RDLDataSource *src = [[RDLDataSource alloc] init];
  src.name = name;
  src.dataProvider = provider;
  src.connectString = connect;
  return src;
}

// A caption above a table, naming the query that produced what is under it.
// The sample is a demonstration, so it says what it is doing.
static RDLItem *RDLCaption(NSString *name, NSString *text, CGFloat y) {
  return RDLTB(name, text, 0, y, 7.5, 0.2, @"Helvetica", [RDLLength points:9],
               RDLFontWeightBold, kMuted, RDLTextAlignLeft);
}

// The data-source sample: one report, three datasets, two documents, and no
// files to go missing -- the documents are carried in the report itself, the
// way jsondata= and xmldata= are meant to be used for content that belongs
// with it.
//
// What it demonstrates, in the order it appears:
//   * a JSON document read with a JSONPath ($.Shipment[*]),
//   * the same document flattened a level deeper ($.Shipment[*].Crates[*]),
//     which is how a hierarchy becomes rows a flat table can bind to,
//   * a filter in the path ([?(@.Qty >= 10)]) rather than in the report,
//   * an XML document read with an XPath (//Port),
//   * and aggregates over a dataset the report never declared rows for.
+ (RDLReport *)harborManifest {
  RDLReport *r = [RDLReport emptyReportNamed:@"Harbor Manifest"];
  r.reportDescription = @"Shipments from a JSON document and ports from an XML one.";
  r.author = @"RDLDesigner";

  // The manifest. Crates sit inside their shipment, which is how the file
  // would arrive and what JSONPath is for.
  NSString *manifest =
      @"jsondata={\"Shipment\":["
      @"{\"No\":\"S-101\",\"Port\":\"AST\",\"Sailed\":\"2026-06-02\","
      @"\"Master\":\"A. Merrick\",\"Crates\":["
      @"{\"Item\":\"Stoneware bowls\",\"Qty\":12,\"Kg\":38},"
      @"{\"Item\":\"Glaze, cobalt\",\"Qty\":4,\"Kg\":22}]},"
      @"{\"No\":\"S-102\",\"Port\":\"PDX\",\"Sailed\":\"2026-06-05\","
      @"\"Master\":\"L. Vale\",\"Crates\":["
      @"{\"Item\":\"Kiln shelves\",\"Qty\":18,\"Kg\":96},"
      @"{\"Item\":\"Firebrick\",\"Qty\":40,\"Kg\":210},"
      @"{\"Item\":\"Pyrometric cones\",\"Qty\":6,\"Kg\":3}]},"
      @"{\"No\":\"S-103\",\"Port\":\"AST\",\"Sailed\":\"2026-06-11\","
      @"\"Master\":\"S. Reed\",\"Crates\":["
      @"{\"Item\":\"Porcelain clay\",\"Qty\":25,\"Kg\":500},"
      @"{\"Item\":\"Brushes\",\"Qty\":9,\"Kg\":2}]}]}";
  // The port register, which arrives as XML because the harbour authority
  // publishes it that way. An attribute and a child element are both fields.
  NSString *ports =
      @"xmldata=<Ports>"
      @"<Port Code=\"AST\"><Name>Astoria</Name><Country>United States</Country></Port>"
      @"<Port Code=\"PDX\"><Name>Portland</Name><Country>United States</Country></Port>"
      @"<Port Code=\"HFX\"><Name>Halifax</Name><Country>Canada</Country></Port>"
      @"</Ports>";

  [r.dataSources removeAllObjects];
  [r.dataSources addObject:RDLDocumentSource(@"Manifest", @"JSON", manifest)];
  [r.dataSources addObject:RDLDocumentSource(@"Register", @"XML", ports)];

  [r.dataSets removeAllObjects];
  [r.dataSets addObject:RDLReading(@"Shipments", @"Manifest", @"$.Shipment[*]",
                                   @[ @"No", @"Port", @"Sailed", @"Master" ])];
  [r.dataSets addObject:RDLReading(@"Crates", @"Manifest", @"$.Shipment[*].Crates[*]",
                                   @[ @"Item", @"Qty", @"Kg" ])];
  [r.dataSets addObject:RDLReading(@"Heavy", @"Manifest",
                                   @"$.Shipment[*].Crates[?(@.Qty >= 10)]",
                                   @[ @"Item", @"Qty", @"Kg" ])];
  [r.dataSets addObject:RDLReading(@"Ports", @"Register", @"//Port",
                                   @[ @"Code", @"Name", @"Country" ])];

  [r.pageHeader.items addObject:RDLTB(@"Title", @"Harbor manifest", 0, 0.04, 5, 0.3, @"Georgia",
                                       [RDLLength points:16], RDLFontWeightNormal, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"When", @"=Globals!ExecutionTime", 5, 0.1, 2.5, 0.22,
                                       @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.46, 7.5)];

  r.body.height = 7.0;
  [r.body.items addObject:RDLCaption(@"ShipLbl", @"Shipments  ·  JSON  ·  $.Shipment[*]", 0.1)];
  [r.body.items addObject:RDLMakeTablix(@"ShipTable", @"Shipments", 0, 0.35, 7.5, 0.28, 0.26, @[
                 RDLCol(@"Shipment", @"=Fields!No.Value", 1.6, @"Left"),
                 RDLCol(@"Port", @"=Fields!Port.Value", 1.2, @"Left"),
                 RDLCol(@"Sailed", @"=Fields!Sailed.Value", 2.1, @"Left"),
                 RDLCol(@"Master", @"=Fields!Master.Value", 2.6, @"Left")
               ])];

  [r.body.items addObject:RDLCaption(@"CrateLbl",
                                     @"Crates  ·  the same document, a level deeper  ·  "
                                     @"$.Shipment[*].Crates[*]", 1.65)];
  [r.body.items addObject:RDLMakeTablix(@"CrateTable", @"Crates", 0, 1.9, 7.5, 0.28, 0.26, @[
                 RDLCol(@"Item", @"=Fields!Item.Value", 3.9, @"Left"),
                 RDLCol(@"Qty", @"=Fields!Qty.Value", 1.6, @"Right"),
                 RDLCol(@"Kg", @"=Fields!Kg.Value", 2.0, @"Right")
               ])];

  [r.body.items addObject:RDLCaption(@"HeavyLbl",
                                     @"Ten or more to a crate  ·  the filter is in the path  ·  "
                                     @"[?(@.Qty >= 10)]", 4.15)];
  [r.body.items addObject:RDLMakeTablix(@"HeavyTable", @"Heavy", 0, 4.4, 7.5, 0.28, 0.26, @[
                 RDLCol(@"Item", @"=Fields!Item.Value", 3.9, @"Left"),
                 RDLCol(@"Qty", @"=Fields!Qty.Value", 1.6, @"Right"),
                 RDLCol(@"Kg", @"=Fields!Kg.Value", 2.0, @"Right")
               ])];

  [r.body.items addObject:RDLCaption(@"PortLbl", @"Ports  ·  XML  ·  //Port", 5.75)];
  [r.body.items addObject:RDLMakeTablix(@"PortTable", @"Ports", 0, 6.0, 7.5, 0.28, 0.26, @[
                 RDLCol(@"Code", @"=Fields!Code.Value", 1.4, @"Left"),
                 RDLCol(@"Port", @"=Fields!Name.Value", 3.1, @"Left"),
                 RDLCol(@"Country", @"=Fields!Country.Value", 3.0, @"Left")
               ])];

  // Aggregates over a dataset whose rows the report never wrote down.
  [r.body.items addObject:RDLTB(@"TotalLbl", @"Manifest total", 0, 6.9, 3.5, 0.26, @"Georgia",
                                 [RDLLength points:11], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"TotalVal",
                                 @"=Sum(Fields!Qty.Value, \"Crates\") & \" items in \" & "
                                 @"Count(Fields!Item.Value, \"Crates\") & \" crates, \" & "
                                 @"Sum(Fields!Kg.Value, \"Crates\") & \" kg\"",
                                 3.5, 6.9, 4.0, 0.26, @"Georgia", [RDLLength points:11],
                                 RDLFontWeightBold, kInk, RDLTextAlignRight)];

  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"F", @"=\"Page \" & Globals!PageNumber", 0, 0.12, 7.5, 0.2,
                                       @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];

  // Read now, so the sample opens with its rows in it. The documents are in
  // the report, so this touches no files and asks nobody's permission -- a
  // sample that opened empty would demonstrate nothing.
  [[[RDLDataBinder alloc] init] bindReport:r error:NULL];
  return r;
}

// A crosstab: two row groups against two column groups, with one measure at
// their intersection. It is here to show the shape the tablix editor's two
// lists produce -- and because a matrix is the one arrangement where every
// measure cell has to aggregate, having no details row to hold a raw value.
+ (RDLReport *)regionalSales {
  RDLReport *r = [RDLReport emptyReportNamed:@"Regional Sales"];
  r.reportDescription = @"Sales by region and city against year and quarter — a crosstab with "
                        @"two groups on each axis.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"Shop", @"Merrick & Vale")];
  [r.dataSets addObject:RDLSet(@"Sales", @[ @"Region", @"City", @"Year", @"Quarter", @"Amount" ], @[
      @{@"Region" : @"North", @"City" : @"Aberdene", @"Year" : @"2025", @"Quarter" : @"Q1", @"Amount" : @1840},
      @{@"Region" : @"North", @"City" : @"Aberdene", @"Year" : @"2025", @"Quarter" : @"Q2", @"Amount" : @2110},
      @{@"Region" : @"North", @"City" : @"Kirkwall", @"Year" : @"2025", @"Quarter" : @"Q1", @"Amount" : @960},
      @{@"Region" : @"North", @"City" : @"Kirkwall", @"Year" : @"2026", @"Quarter" : @"Q1", @"Amount" : @1240},
      @{@"Region" : @"South", @"City" : @"Marlow", @"Year" : @"2025", @"Quarter" : @"Q1", @"Amount" : @3020},
      @{@"Region" : @"South", @"City" : @"Marlow", @"Year" : @"2025", @"Quarter" : @"Q2", @"Amount" : @2760},
      @{@"Region" : @"South", @"City" : @"Thornbury", @"Year" : @"2026", @"Quarter" : @"Q1", @"Amount" : @1490},
      @{@"Region" : @"South", @"City" : @"Thornbury", @"Year" : @"2026", @"Quarter" : @"Q2", @"Amount" : @1875}
    ])];

  r.pageHeader.height = 0.62;
  [r.pageHeader.items addObject:RDLTB(@"Studio", @"=Parameters!Shop.Value", 0, 0.02, 4.6, 0.28,
                                       @"Georgia", [RDLLength points:13], RDLFontWeightBold, kInk,
                                       RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Kind", @"REGIONAL SALES", 4.6, 0.04, 2.9, 0.24, @"Helvetica",
                                       [RDLLength points:10], RDLFontWeightBold, kMuted,
                                       RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLTB(@"Tag",
                                       @"Region and city down the side, year and quarter across the "
                                       @"top; the cell is the total where they meet.",
                                       0, 0.28, 7.5, 0.18, @"Helvetica", [RDLLength points:8],
                                       RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.5, 7.5)];

  r.body.height = 4.0;
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"SalesMatrix";
  tab.dataSetName = @"Sales";
  tab.left = 0;
  tab.top = 0.12;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.rowGroups = @[ @"Region", @"City" ];
  tab.columnGroups = @[ @"Year", @"Quarter" ];
  tab.showGrandTotal = YES;
  tab.noRowsMessage = @"No sales in this period.";
  // One measure, aggregated: in a crosstab there is no details row for a bare
  // field to be read on.
  tab.columnSpecs = @[ @{ @"width" : @1.2, @"header" : @"Amount",
                          @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum",
                          @"align" : @"Right" } ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];

  r.pageFooter.height = 0.3;
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.02, 7.5)];
  [r.pageFooter.items addObject:RDLTB(@"Page", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages",
                                       0, 0.08, 7.5, 0.16, @"Helvetica", [RDLLength points:8],
                                       RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];
  return r;
}

+ (RDLReport *)workshopByFinish {
  RDLReport *r = [RDLReport emptyReportNamed:@"Workshop by Finish"];
  r.reportDescription = @"Jobs grouped by finish, with a group header, details, and subtotal footer.";
  r.author = @"RDLDesigner";
  [r.parameters addObject:RDLPar(@"Shop", @"Merrick & Vale")];
  [r.dataSets addObject:RDLSet(@"Jobs", @[ @"Job", @"Finish", @"Hours", @"Amount" ], @[
                    @{@"Job" : @"Walnut writing desk", @"Finish" : @"Oil", @"Hours" : @12, @"Amount" : @1840},
                    @{@"Job" : @"White oak side chair", @"Finish" : @"Oil", @"Hours" : @6, @"Amount" : @420},
                    @{@"Job" : @"Turned brass lamp", @"Finish" : @"Lacquer", @"Hours" : @4, @"Amount" : @265},
                    @{@"Job" : @"Linen shade", @"Finish" : @"Lacquer", @"Hours" : @1, @"Amount" : @48},
                    @{@"Job" : @"Open shelf", @"Finish" : @"Wax", @"Hours" : @8, @"Amount" : @610},
                    @{@"Job" : @"Shop stool", @"Finish" : @"Wax", @"Hours" : @3, @"Amount" : @190},
                    @{@"Job" : @"Picture frame", @"Finish" : @"Oil", @"Hours" : @2, @"Amount" : @95}
                  ])];
  [r.dataSets addObject:RDLSet(@"Finishes", @[ @"Finish", @"Rate" ], @[
                    @{@"Finish" : @"Oil", @"Rate" : @40},
                    @{@"Finish" : @"Lacquer", @"Rate" : @55},
                    @{@"Finish" : @"Wax", @"Rate" : @28}
                  ])];
  r.pageHeader.height = 0.62;
  [r.pageHeader.items addObject:RDLTB(@"Studio", @"=Parameters!Shop.Value", 0, 0.02, 4.6, 0.28, @"Georgia",
                                       [RDLLength points:13], RDLFontWeightBold, kInk, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLTB(@"Kind", @"WORKSHOP BY FINISH", 4.6, 0.04, 2.9, 0.24, @"Helvetica",
                                       [RDLLength points:10], RDLFontWeightBold, kMuted, RDLTextAlignRight)];
  [r.pageHeader.items addObject:RDLTB(@"Tag", @"Group header, details, subtotal, and catalog rate via Lookup.", 0,
                                       0.28, 7.5, 0.18, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageHeader.items addObject:RDLMakeLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 5.2;
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"JobsByFinish";
  tab.dataSetName = @"Jobs";
  tab.left = 0;
  tab.top = 0.12;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.rowGroups = @[ @"Finish" ];
  tab.noRowsMessage = @"No jobs in this run.";
  // 6.3in of columns, because grouping adds a 1.2in row-header column in front
  // of them: 1.2 + 6.3 is the 7.5in body width the tablix is given above.
  tab.columnSpecs = @[
    RDLCol(@"Job", @"=Fields!Job.Value", 2.4, @"Left"),
    RDLCol(@"Hours", @"=Fields!Hours.Value", 1.0, @"Right"),
    RDLCol(@"Rate", @"=Lookup(Fields!Finish.Value, Fields!Finish.Value, Fields!Rate.Value, \"Finishes\")", 1.1,
            @"Right"),
    RDLCol(@"Amount", @"=Fields!Amount.Value", 1.8, @"Right")
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  [r.body.items addObject:RDLTB(@"GrandLbl", @"Shop total", 0, 1.2, 4.2, 0.28, @"Georgia", [RDLLength points:12], RDLFontWeightBold,
                                 kInk, RDLTextAlignLeft)];
  [r.body.items addObject:RDLTB(@"GrandVal", @"=Format(Sum(Fields!Amount.Value), \"C\")", 4.2, 1.2, 3.3, 0.28,
                                 @"Georgia", [RDLLength points:12], RDLFontWeightBold, kInk, RDLTextAlignRight)];
  [r.body.items
      addObject:RDLTB(@"Tally",
                       @"=IIf(CountRows() = 0, \"No jobs\", CountRows() & \" jobs in \" & "
                       @"CountDistinct(Fields!Finish.Value) & \" finishes\")",
                       0, 1.55, 7.5, 0.22, @"Helvetica", [RDLLength points:9], RDLFontWeightNormal, kMuted, RDLTextAlignLeft)];
  [r.pageFooter.items addObject:RDLMakeLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items
      addObject:RDLTB(@"F", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages", 0, 0.12, 7.5,
                       0.2, @"Helvetica", [RDLLength points:8], RDLFontWeightNormal, kMuted, RDLTextAlignCenter)];
  return r;
}

@end
