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
  tab.groupBy = @"Finish";
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
