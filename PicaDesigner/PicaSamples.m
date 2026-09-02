#import "PicaSamples.h"
#import "PicaKit.h"

static NSString *const kInk = @"#1a1916";
static NSString *const kMuted = @"#5c574e";
static NSString *const kShade = @"#ece6d8";

static void PicaApplyStyle(RDLItem *it, NSString *font, NSString *size, NSString *weight,
                           NSString *color, NSString *align) {
  if (font)
    it.style.fontFamily = font;
  if (size)
    it.style.fontSize = size;
  if (weight)
    it.style.fontWeight = weight;
  if (color)
    it.style.color = color;
  if (align)
    it.style.textAlign = align;
}

static RDLItem *PicaTB(NSString *name, NSString *value, CGFloat x, CGFloat y, CGFloat w, CGFloat h,
                       NSString *font, NSString *size, NSString *weight, NSString *color,
                       NSString *align) {
  RDLItem *it = [[RDLItem alloc] init];
  it.name = name;
  it.type = @"Textbox";
  it.value = value;
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = h;
  PicaApplyStyle(it, font, size, weight, color, align);
  return it;
}

static RDLItem *PicaLine(NSString *name, CGFloat x, CGFloat y, CGFloat w) {
  RDLItem *it = [[RDLItem alloc] init];
  it.name = name;
  it.type = @"Line";
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = 0.02;
  it.style.color = kInk;
  return it;
}

static RDLItem *PicaRect(NSString *name, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSString *bg) {
  RDLItem *it = [[RDLItem alloc] init];
  it.name = name;
  it.type = @"Rectangle";
  it.left = x;
  it.top = y;
  it.width = w;
  it.height = h;
  it.style.backgroundColor = bg ?: kShade;
  return it;
}

static NSDictionary *PicaCol(NSString *header, NSString *value, CGFloat width, NSString *align) {
  return @{
    @"header" : header ?: @"",
    @"value" : value ?: @"",
    @"width" : @(width),
    @"align" : align ?: @"Left"
  };
}

static RDLDataSet *PicaSet(NSString *name, NSArray *fields, NSArray *rows) {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = name;
  ds.dataSourceName = @"Demo";
  ds.fields = fields;
  ds.rows = rows;
  return ds;
}

static RDLParameter *PicaPar(NSString *name, NSString *def) {
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = name;
  p.dataType = @"String";
  p.defaultValue = def ?: @"";
  return p;
}

static RDLItem *PicaTablix(NSString *name, NSString *ds, CGFloat x, CGFloat y, CGFloat w,
                           CGFloat headerH, CGFloat rowH, NSArray *cols) {
  RDLItem *it = [[RDLItem alloc] init];
  it.name = name;
  it.type = @"Tablix";
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

@implementation PicaSamples

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
  r.author = @"Pica";
  [r.pageHeader.items addObject:PicaTB(@"Brand", @"PICA", 0, 0.08, 2.2, 0.28, @"Georgia", @"11pt",
                                       @"Bold", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"DocTitle", @"=Parameters!Title.Value", 2.2, 0.1, 5.3, 0.24,
                                       @"Helvetica", @"9pt", @"Normal", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.42, 7.5)];
  [r.body.items addObject:PicaTB(@"Salutation", @"Dear reader,", 0, 0.2, 7.5, 0.3, @"Georgia",
                                 @"12pt", @"Normal", kInk, @"Left")];
  [r.body.items
      addObject:PicaTB(@"BodyCopy",
                       @"Set the type. Bind a field. The page is a measure of 51 picas — enough "
                       @"room for a proper letter, an invoice, or a ledger.",
                       0, 0.6, 7.5, 0.8, @"Georgia", @"11pt", @"Normal", kInk, @"Left")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.02, 7.5)];
  [r.pageFooter.items
      addObject:PicaTB(@"Folio", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages",
                       0, 0.1, 7.5, 0.22, @"Helvetica", @"8pt", @"Normal", kMuted, @"Center")];
  [r.parameters addObject:PicaPar(@"Title", @"Untitled letter")];
  return r;
}

+ (RDLReport *)atelierInvoice {
  RDLReport *r = [RDLReport emptyReportNamed:@"Atelier Invoice"];
  r.reportDescription = @"Workshop invoice for Merrick & Vale cabinetmakers.";
  r.author = @"Pica";
  [r.parameters addObject:PicaPar(@"InvoiceNo", @"MV-1842")];
  [r.parameters addObject:PicaPar(@"InvoiceDate", @"26 Aug 2026")];
  [r.parameters addObject:PicaPar(@"BillTo", @"Northlight Editorial")];
  [r.parameters addObject:PicaPar(@"BillAddr", @"14 Reed Street, Portland")];
  [r.dataSets addObject:PicaSet(@"Items", @[ @"Sku", @"Description", @"Qty", @"Unit", @"Amount" ], @[
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
  [r.pageHeader.items addObject:PicaTB(@"Studio", @"MERRICK & VALE", 0, 0.02, 4.6, 0.28, @"Georgia",
                                       @"13pt", @"Bold", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"Tag", @"Cabinetmakers · Est. 1978", 0, 0.28, 4.6, 0.18,
                                       @"Helvetica", @"8pt", @"Normal", kMuted, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"InvLabel", @"INVOICE", 4.6, 0.02, 2.9, 0.28, @"Helvetica",
                                       @"11pt", @"Bold", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaTB(@"InvNo", @"=Parameters!InvoiceNo.Value", 4.6, 0.26, 2.9, 0.2,
                                       @"Helvetica", @"9pt", @"Normal", kInk, @"Right")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 5.4;
  [r.body.items addObject:PicaTB(@"BillLbl", @"Bill to", 0, 0.12, 3.6, 0.18, @"Helvetica", @"8pt",
                                 @"Bold", kMuted, @"Left")];
  [r.body.items addObject:PicaTB(@"BillName", @"=Parameters!BillTo.Value", 0, 0.3, 3.6, 0.22,
                                 @"Georgia", @"12pt", @"Normal", kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"BillAddr", @"=Parameters!BillAddr.Value", 0, 0.52, 3.6, 0.2,
                                 @"Helvetica", @"9pt", @"Normal", kMuted, @"Left")];
  [r.body.items addObject:PicaTB(@"DateLbl", @"Date", 5.2, 0.12, 2.3, 0.18, @"Helvetica", @"8pt",
                                 @"Bold", kMuted, @"Right")];
  [r.body.items addObject:PicaTB(@"DateVal", @"=Parameters!InvoiceDate.Value", 5.2, 0.3, 2.3, 0.22,
                                 @"Georgia", @"12pt", @"Normal", kInk, @"Right")];
  [r.body.items addObject:PicaTablix(@"LineItems", @"Items", 0, 1.0, 7.5, 0.32, 0.3, @[
                 PicaCol(@"SKU", @"=Fields!Sku.Value", 0.9, @"Left"),
                 PicaCol(@"Description", @"=Fields!Description.Value", 3.5, @"Left"),
                 PicaCol(@"Qty", @"=Fields!Qty.Value", 0.7, @"Right"),
                 PicaCol(@"Unit", @"=Fields!Unit.Value", 1.1, @"Right"),
                 PicaCol(@"Amount", @"=Fields!Amount.Value", 1.3, @"Right")
               ])];
  [r.body.items addObject:PicaTB(@"SubLbl", @"Subtotal", 4.6, 2.55, 1.4, 0.24, @"Helvetica", @"9pt",
                                 @"Normal", kMuted, @"Right")];
  [r.body.items addObject:PicaTB(@"SubVal", @"=Format(Sum(Fields!Amount.Value), \"C\")", 6.0, 2.55,
                                 1.5, 0.24, @"Helvetica", @"9pt", @"Normal", kInk, @"Right")];
  [r.body.items addObject:PicaTB(@"TaxLbl", @"Tax 8%", 4.6, 2.8, 1.4, 0.24, @"Helvetica", @"9pt",
                                 @"Normal", kMuted, @"Right")];
  [r.body.items addObject:PicaTB(@"TaxVal", @"=Format(Sum(Fields!Amount.Value) * 0.08, \"C\")", 6.0,
                                 2.8, 1.5, 0.24, @"Helvetica", @"9pt", @"Normal", kInk, @"Right")];
  [r.body.items addObject:PicaLine(@"TotRule", 4.6, 3.1, 2.9)];
  [r.body.items addObject:PicaTB(@"TotLbl", @"Amount due", 4.6, 3.18, 1.4, 0.3, @"Georgia", @"11pt",
                                 @"Bold", kInk, @"Right")];
  [r.body.items addObject:PicaTB(@"TotVal", @"=Format(Sum(Fields!Amount.Value) * 1.08, \"C\")", 6.0,
                                 3.18, 1.5, 0.3, @"Georgia", @"11pt", @"Bold", kInk, @"Right")];
  [r.body.items
      addObject:PicaTB(@"Note",
                       @"Payable within 14 days. Pieces are made to order in the East End "
                       @"workshop. Thank you.",
                       0, 3.7, 5.4, 0.5, @"Georgia", @"9pt", @"Normal", kMuted, @"Left")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:PicaTB(@"Addr", @"Merrick & Vale  ·  88 Binder Lane  ·  Almaty", 0,
                                       0.12, 4.8, 0.2, @"Helvetica", @"8pt", @"Normal", kMuted,
                                       @"Left")];
  [r.pageFooter.items
      addObject:PicaTB(@"Folio", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages",
                       4.8, 0.12, 2.7, 0.2, @"Helvetica", @"8pt", @"Normal", kMuted, @"Right")];
  return r;
}

+ (RDLReport *)packingSlip {
  RDLReport *r = [RDLReport emptyReportNamed:@"Harbor Packing Slip"];
  r.reportDescription = @"North Wharf packing slip with ship-to block and carton list.";
  r.author = @"Pica";
  [r.parameters addObject:PicaPar(@"OrderNo", @"NW-2209")];
  [r.parameters addObject:PicaPar(@"ShipTo", @"The Reed Bindery")];
  [r.parameters addObject:PicaPar(@"ShipAddr", @"6 Dock Road, Astoria")];
  [r.dataSets addObject:PicaSet(@"Carton", @[ @"Item", @"Finish", @"Qty", @"Carton" ], @[
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
  [r.pageHeader.items addObject:PicaTB(@"Brand", @"NORTH WHARF", 0, 0.04, 4, 0.26, @"Georgia",
                                       @"13pt", @"Bold", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"Kind", @"PACKING SLIP", 4, 0.08, 3.5, 0.22, @"Helvetica",
                                       @"10pt", @"Bold", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.42, 7.5)];
  [r.body.items addObject:PicaRect(@"ShipBox", 0, 0.15, 3.6, 1.15, kShade)];
  [r.body.items addObject:PicaTB(@"ShipLbl", @"Ship to", 0.12, 0.22, 3.3, 0.18, @"Helvetica", @"8pt",
                                 @"Bold", kMuted, @"Left")];
  [r.body.items addObject:PicaTB(@"ShipName", @"=Parameters!ShipTo.Value", 0.12, 0.42, 3.3, 0.28,
                                 @"Georgia", @"13pt", @"Normal", kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"ShipAddr", @"=Parameters!ShipAddr.Value", 0.12, 0.72, 3.3, 0.4,
                                 @"Helvetica", @"9pt", @"Normal", kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"OrdLbl", @"Order", 4.2, 0.22, 3.3, 0.18, @"Helvetica", @"8pt",
                                 @"Bold", kMuted, @"Left")];
  [r.body.items addObject:PicaTB(@"OrdVal", @"=Parameters!OrderNo.Value", 4.2, 0.42, 3.3, 0.28,
                                 @"Georgia", @"13pt", @"Normal", kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"ShipDate", @"=Globals!ExecutionTime", 4.2, 0.72, 3.3, 0.22,
                                 @"Helvetica", @"9pt", @"Normal", kMuted, @"Left")];
  [r.body.items addObject:PicaTablix(@"CartonTable", @"Carton", 0, 1.55, 7.5, 0.3, 0.28, @[
                 PicaCol(@"Item", @"=Fields!Item.Value", 3.0, @"Left"),
                 PicaCol(@"Finish", @"=Fields!Finish.Value", 2.2, @"Left"),
                 PicaCol(@"Qty", @"=Fields!Qty.Value", 1.0, @"Right"),
                 PicaCol(@"Ctn", @"=Fields!Carton.Value", 1.3, @"Center")
               ])];
  [r.body.items addObject:PicaTB(@"Note",
                                 @"Inspect on arrival. Shortages must be noted on the carrier's "
                                 @"copy. Cases ship standing, spines to the left.",
                                 0, 3.1, 7.5, 0.5, @"Georgia", @"9pt", @"Normal", kMuted, @"Left")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items
      addObject:PicaTB(@"F", @"=\"North Wharf Bindery  ·  slip \" & Parameters!OrderNo.Value", 0,
                       0.12, 7.5, 0.2, @"Helvetica", @"8pt", @"Normal", kMuted, @"Left")];
  return r;
}

+ (RDLReport *)salesLedger {
  RDLReport *r = [RDLReport emptyReportNamed:@"Quarterly Ledger"];
  r.reportDescription = @"Q3 sales by month with a column chart and totals.";
  r.author = @"Pica";
  [r.parameters addObject:PicaPar(@"Quarter", @"Q3 2026")];
  [r.parameters addObject:PicaPar(@"House", @"Pica Press")];
  [r.dataSets addObject:PicaSet(@"Months", @[ @"Month", @"Orders", @"Total" ], @[
               @{@"Month" : @"July", @"Orders" : @42, @"Total" : @18640},
               @{@"Month" : @"August", @"Orders" : @51, @"Total" : @22410},
               @{@"Month" : @"September", @"Orders" : @47, @"Total" : @20115}
             ])];
  [r.pageHeader.items addObject:PicaTB(@"House", @"=Parameters!House.Value", 0, 0.02, 4.5, 0.24,
                                       @"Georgia", @"12pt", @"Bold", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"Qtr", @"=Parameters!Quarter.Value", 4.5, 0.04, 3, 0.22,
                                       @"Helvetica", @"10pt", @"Normal", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaTB(@"Kicker", @"Sales ledger", 0, 0.26, 7.5, 0.18, @"Helvetica",
                                       @"8pt", @"Normal", kMuted, @"Left")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 4.6;
  RDLItem *chart = [[RDLItem alloc] init];
  chart.name = @"ByMonth";
  chart.type = @"Chart";
  chart.left = 0;
  chart.top = 0.15;
  chart.width = 7.5;
  chart.height = 2.4;
  chart.dataSetName = @"Months";
  chart.chartType = @"Column";
  chart.categoryField = @"Month";
  chart.valueField = @"Total";
  chart.title = @"Net receipts";
  [r.body.items addObject:chart];
  [r.body.items addObject:PicaTablix(@"MonthTable", @"Months", 0, 2.7, 7.5, 0.3, 0.28, @[
                 PicaCol(@"Month", @"=Fields!Month.Value", 2.5, @"Left"),
                 PicaCol(@"Orders", @"=Fields!Orders.Value", 2.5, @"Right"),
                 PicaCol(@"Net", @"=Fields!Total.Value", 2.5, @"Right")
               ])];
  [r.body.items addObject:PicaTB(@"SumLbl", @"Quarter total", 0, 4.05, 4, 0.3, @"Georgia", @"12pt",
                                 @"Bold", kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"SumVal", @"=Format(Sum(Fields!Total.Value), \"C\")", 4, 4.05, 3.5,
                                 0.3, @"Georgia", @"12pt", @"Bold", kInk, @"Right")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:PicaTB(@"F", @"=\"Confidential  ·  \" & Globals!ReportName", 0, 0.12,
                                       7.5, 0.2, @"Helvetica", @"8pt", @"Normal", kMuted, @"Left")];
  return r;
}

+ (RDLReport *)studioRoster {
  RDLReport *r = [RDLReport emptyReportNamed:@"Studio Roster"];
  r.reportDescription = @"Directory of the press — names, desks, and extensions.";
  r.author = @"Pica";
  [r.dataSets addObject:PicaSet(@"People", @[ @"Name", @"Desk", @"Ext", @"City" ], @[
               @{@"Name" : @"A. Merrick", @"Desk" : @"Type", @"Ext" : @"12", @"City" : @"Almaty"},
               @{@"Name" : @"L. Vale", @"Desk" : @"Case", @"Ext" : @"14", @"City" : @"Almaty"},
               @{@"Name" : @"S. Reed", @"Desk" : @"Bindery", @"Ext" : @"21", @"City" : @"Astoria"},
               @{@"Name" : @"N. Harbor", @"Desk" : @"Ledger", @"Ext" : @"18", @"City" : @"Portland"},
               @{@"Name" : @"C. Folio", @"Desk" : @"Proof", @"Ext" : @"09", @"City" : @"Almaty"},
               @{@"Name" : @"J. Pica", @"Desk" : @"Press", @"Ext" : @"04", @"City" : @"Astoria"}
             ])];
  [r.pageHeader.items addObject:PicaTB(@"Title", @"Studio roster", 0, 0.04, 5, 0.3, @"Georgia",
                                       @"16pt", @"Normal", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"When", @"=Globals!ExecutionTime", 5, 0.1, 2.5, 0.22,
                                       @"Helvetica", @"9pt", @"Normal", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.46, 7.5)];
  [r.body.items addObject:PicaTablix(@"PeopleTable", @"People", 0, 0.15, 7.5, 0.3, 0.32, @[
                 PicaCol(@"Name", @"=Fields!Name.Value", 2.4, @"Left"),
                 PicaCol(@"Desk", @"=Fields!Desk.Value", 2.0, @"Left"),
                 PicaCol(@"Ext", @"=Fields!Ext.Value", 1.2, @"Right"),
                 PicaCol(@"City", @"=Fields!City.Value", 1.9, @"Left")
               ])];
  [r.body.items addObject:PicaTB(@"Count", @"=Count(Fields!Name.Value) & \" names on the floor\"", 0,
                                 2.4, 7.5, 0.24, @"Georgia", @"10pt", @"Normal", kMuted, @"Left")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items addObject:PicaTB(@"F", @"=\"Page \" & Globals!PageNumber", 0, 0.12, 7.5, 0.2,
                                       @"Helvetica", @"8pt", @"Normal", kMuted, @"Center")];
  return r;
}

+ (RDLReport *)workshopByFinish {
  RDLReport *r = [RDLReport emptyReportNamed:@"Workshop by Finish"];
  r.reportDescription = @"Jobs grouped by finish, with a group header, details, and subtotal footer.";
  r.author = @"Pica";
  [r.parameters addObject:PicaPar(@"Shop", @"Merrick & Vale")];
  [r.dataSets addObject:PicaSet(@"Jobs", @[ @"Job", @"Finish", @"Hours", @"Amount" ], @[
                    @{@"Job" : @"Walnut writing desk", @"Finish" : @"Oil", @"Hours" : @12, @"Amount" : @1840},
                    @{@"Job" : @"White oak side chair", @"Finish" : @"Oil", @"Hours" : @6, @"Amount" : @420},
                    @{@"Job" : @"Turned brass lamp", @"Finish" : @"Lacquer", @"Hours" : @4, @"Amount" : @265},
                    @{@"Job" : @"Linen shade", @"Finish" : @"Lacquer", @"Hours" : @1, @"Amount" : @48},
                    @{@"Job" : @"Open shelf", @"Finish" : @"Wax", @"Hours" : @8, @"Amount" : @610},
                    @{@"Job" : @"Shop stool", @"Finish" : @"Wax", @"Hours" : @3, @"Amount" : @190},
                    @{@"Job" : @"Picture frame", @"Finish" : @"Oil", @"Hours" : @2, @"Amount" : @95}
                  ])];
  [r.dataSets addObject:PicaSet(@"Finishes", @[ @"Finish", @"Rate" ], @[
                    @{@"Finish" : @"Oil", @"Rate" : @40},
                    @{@"Finish" : @"Lacquer", @"Rate" : @55},
                    @{@"Finish" : @"Wax", @"Rate" : @28}
                  ])];
  r.pageHeader.height = 0.62;
  [r.pageHeader.items addObject:PicaTB(@"Studio", @"=Parameters!Shop.Value", 0, 0.02, 4.6, 0.28, @"Georgia",
                                       @"13pt", @"Bold", kInk, @"Left")];
  [r.pageHeader.items addObject:PicaTB(@"Kind", @"WORKSHOP BY FINISH", 4.6, 0.04, 2.9, 0.24, @"Helvetica",
                                       @"10pt", @"Bold", kMuted, @"Right")];
  [r.pageHeader.items addObject:PicaTB(@"Tag", @"Group header, details, subtotal, and catalog rate via Lookup.", 0,
                                       0.28, 7.5, 0.18, @"Helvetica", @"8pt", @"Normal", kMuted, @"Left")];
  [r.pageHeader.items addObject:PicaLine(@"HRule", 0, 0.5, 7.5)];
  r.body.height = 5.2;
  RDLItem *tab = [[RDLItem alloc] init];
  tab.name = @"JobsByFinish";
  tab.type = @"Tablix";
  tab.dataSetName = @"Jobs";
  tab.left = 0;
  tab.top = 0.12;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.groupBy = @"Finish";
  tab.noRowsMessage = @"No jobs in this run.";
  tab.columnSpecs = @[
    PicaCol(@"Job", @"=Fields!Job.Value", 2.8, @"Left"),
    PicaCol(@"Hours", @"=Fields!Hours.Value", 1.2, @"Right"),
    PicaCol(@"Rate", @"=Lookup(Fields!Finish.Value, Fields!Finish.Value, Fields!Rate.Value, \"Finishes\")", 1.4,
            @"Right"),
    PicaCol(@"Amount", @"=Fields!Amount.Value", 2.1, @"Right")
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  [r.body.items addObject:PicaTB(@"GrandLbl", @"Shop total", 0, 1.2, 4.2, 0.28, @"Georgia", @"12pt", @"Bold",
                                 kInk, @"Left")];
  [r.body.items addObject:PicaTB(@"GrandVal", @"=Format(Sum(Fields!Amount.Value), \"C\")", 4.2, 1.2, 3.3, 0.28,
                                 @"Georgia", @"12pt", @"Bold", kInk, @"Right")];
  [r.body.items
      addObject:PicaTB(@"Tally",
                       @"=IIf(CountRows() = 0, \"No jobs\", CountRows() & \" jobs in \" & "
                       @"CountDistinct(Fields!Finish.Value) & \" finishes\")",
                       0, 1.55, 7.5, 0.22, @"Helvetica", @"9pt", @"Normal", kMuted, @"Left")];
  [r.pageFooter.items addObject:PicaLine(@"FRule", 0, 0.04, 7.5)];
  [r.pageFooter.items
      addObject:PicaTB(@"F", @"=\"Page \" & Globals!PageNumber & \" of \" & Globals!TotalPages", 0, 0.12, 7.5,
                       0.2, @"Helvetica", @"8pt", @"Normal", kMuted, @"Center")];
  return r;
}

@end
