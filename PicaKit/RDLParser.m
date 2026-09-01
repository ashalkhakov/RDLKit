#import "RDLParser.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

static NSXMLElement *PicaChild(NSXMLElement *el, NSString *name) {
  if (el == nil)
    return nil;
  for (NSXMLNode *n in [el children]) {
    if (n.kind == NSXMLElementKind && [n.localName isEqualToString:name])
      return (NSXMLElement *)n;
  }
  return nil;
}

static NSString *PicaText(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             ?: @"";
}

static NSString *PicaParseVisibility(NSXMLElement *el);
static NSString *PicaParseHyperlink(NSXMLElement *el);

static RDLBorder *PicaParseBorder(NSXMLElement *el) {
  if (el == nil)
    return [RDLBorder none];
  RDLBorder *b = [[RDLBorder alloc] init];
  NSString *st = PicaText(PicaChild(el, @"Style"));
  b.style = [st length] ? st : @"None";
  NSString *w = PicaText(PicaChild(el, @"Width"));
  b.width = [w length] ? w : @"1pt";
  NSString *c = PicaText(PicaChild(el, @"Color"));
  b.color = [c length] ? c : @"#1a1916";
  return b;
}

static RDLStyle *PicaParseStyle(NSXMLElement *el) {
  RDLStyle *s = [RDLStyle defaultStyle];
  if (el == nil)
    return s;
  NSString *ff = PicaText(PicaChild(el, @"FontFamily"));
  if ([ff length])
    s.fontFamily = ff;
  NSString *fs = PicaText(PicaChild(el, @"FontSize"));
  if ([fs length])
    s.fontSize = fs;
  NSString *fw = PicaText(PicaChild(el, @"FontWeight"));
  if ([fw length])
    s.fontWeight = fw;
  NSString *fst = PicaText(PicaChild(el, @"FontStyle"));
  if ([fst length])
    s.fontStyle = fst;
  NSString *c = PicaText(PicaChild(el, @"Color"));
  if ([c length])
    s.color = c;
  NSString *ta = PicaText(PicaChild(el, @"TextAlign"));
  if ([ta length])
    s.textAlign = ta;
  NSString *va = PicaText(PicaChild(el, @"VerticalAlign"));
  if ([va length])
    s.verticalAlign = va;
  NSString *td = PicaText(PicaChild(el, @"TextDecoration"));
  if ([td length])
    s.textDecoration = td;
  NSString *fmt = PicaText(PicaChild(el, @"Format"));
  if ([fmt length])
    s.format = fmt;
  NSString *bg = PicaText(PicaChild(el, @"BackgroundColor"));
  if ([bg length])
    s.backgroundColor = bg;
  NSString *pl = PicaText(PicaChild(el, @"PaddingLeft"));
  if ([pl length])
    s.paddingLeft = pl;
  NSString *pr = PicaText(PicaChild(el, @"PaddingRight"));
  if ([pr length])
    s.paddingRight = pr;
  NSString *pt = PicaText(PicaChild(el, @"PaddingTop"));
  if ([pt length])
    s.paddingTop = pt;
  NSString *pb = PicaText(PicaChild(el, @"PaddingBottom"));
  if ([pb length])
    s.paddingBottom = pb;
  NSXMLElement *border = PicaChild(el, @"Border");
  if (border)
    s.border = PicaParseBorder(border);
  NSXMLElement *bt = PicaChild(el, @"TopBorder");
  if (bt)
    s.borderTop = PicaParseBorder(bt);
  NSXMLElement *bb = PicaChild(el, @"BottomBorder");
  if (bb)
    s.borderBottom = PicaParseBorder(bb);
  NSXMLElement *bl = PicaChild(el, @"LeftBorder");
  if (bl)
    s.borderLeft = PicaParseBorder(bl);
  NSXMLElement *br = PicaChild(el, @"RightBorder");
  if (br)
    s.borderRight = PicaParseBorder(br);
  return s;
}

static void PicaBox(NSXMLElement *el, RDLItem *item) {
  item.top = PicaInchesFromString(PicaText(PicaChild(el, @"Top")));
  item.left = PicaInchesFromString(PicaText(PicaChild(el, @"Left")));
  item.width = PicaInchesFromString(PicaText(PicaChild(el, @"Width")));
  item.height = PicaInchesFromString(PicaText(PicaChild(el, @"Height")));
}

static NSArray *PicaParseFilters(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"Filter"])
      continue;
    NSXMLElement *fEl = (NSXMLElement *)n;
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = PicaText(PicaChild(fEl, @"FilterExpression"));
    NSString *op = PicaText(PicaChild(fEl, @"Operator"));
    if ([op length])
      f.oper = op;
    for (NSXMLNode *v in [PicaChild(fEl, @"FilterValues") children]) {
      if (v.kind == NSXMLElementKind)
        [f.values addObject:PicaText((NSXMLElement *)v)];
    }
    [out addObject:f];
  }
  return out;
}

static NSArray *PicaParseSorts(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"SortExpression"])
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLSortExpression *s = [[RDLSortExpression alloc] init];
    s.expression = PicaText(PicaChild(sEl, @"Value"));
    NSString *dir = PicaText(PicaChild(sEl, @"Direction"));
    if ([dir length])
      s.direction = dir;
    [out addObject:s];
  }
  return out;
}

static NSString *PicaParsePageBreak(NSXMLElement *el) {
  NSString *loc = PicaText(PicaChild(el, @"BreakLocation"));
  return [loc length] ? loc : nil;
}

static BOOL PicaParsePageBreakReset(NSXMLElement *el) {
  NSString *r = PicaText(PicaChild(el, @"ResetPageNumber"));
  return [r caseInsensitiveCompare:@"true"] == NSOrderedSame;
}

static NSString *PicaParsePageBreakName(NSXMLElement *el) {
  NSString *n = PicaText(PicaChild(el, @"PageName"));
  return [n length] ? n : nil;
}

static NSString *PicaFindGroupBy(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *mm in members) {
    if ([mm.groupExpressions count]) {
      NSString *ex = mm.groupExpressions[0];
      NSRange r = [ex rangeOfString:@"Fields!"];
      if (r.location != NSNotFound) {
        NSString *rest = [ex substringFromIndex:r.location + 7];
        NSRange dot = [rest rangeOfString:@"."];
        return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
      }
    }
    NSString *nested = PicaFindGroupBy(mm.members);
    if (nested)
      return nested;
  }
  return nil;
}

static RDLItem *PicaParseItem(NSXMLElement *el);

// Collected during a single parse; reportFromXMLString: copies them into
// report.warnings. Elements we knowingly skip should warn, not vanish.
static NSMutableArray *gPicaParseWarnings = nil;

static BOOL PicaIsSupportedItemElement(NSString *localName) {
  static NSArray *known = nil;
  if (known == nil)
    known = @[ @"Textbox", @"Line", @"Rectangle", @"Image", @"Tablix", @"Chart", @"List" ];
  return [known containsObject:localName];
}

static void PicaWarnUnsupported(NSXMLElement *el) {
  NSString *name = [el attributeForName:@"Name"].stringValue;
  NSString *msg = name.length
                      ? [NSString stringWithFormat:@"unsupported element %@ '%@' skipped", el.localName, name]
                      : [NSString stringWithFormat:@"unsupported element %@ skipped", el.localName];
  [gPicaParseWarnings addObject:msg];
}

static RDLTablixCell *PicaParseCellContents(NSXMLElement *contents) {
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  for (NSXMLNode *k in [contents children]) {
    if (k.kind != NSXMLElementKind)
      continue;
    NSString *ln = [(NSXMLElement *)k localName];
    if ([ln isEqualToString:@"ColSpan"] || [ln isEqualToString:@"RowSpan"])
      continue;
    cell.item = PicaParseItem((NSXMLElement *)k);
    break;
  }
  NSString *cs = PicaText(PicaChild(contents, @"ColSpan"));
  if ([cs integerValue] > 0)
    cell.colSpan = [cs integerValue];
  NSString *rs = PicaText(PicaChild(contents, @"RowSpan"));
  if ([rs integerValue] > 0)
    cell.rowSpan = [rs integerValue];
  return cell;
}

static RDLTablixMember *PicaParseMember(NSXMLElement *el) {
  RDLTablixMember *m = [[RDLTablixMember alloc] init];
  NSXMLElement *group = PicaChild(el, @"Group");
  if (group) {
    m.groupName = [group attributeForName:@"Name"].stringValue ?: @"Details";
    for (NSXMLNode *n in [PicaChild(group, @"GroupExpressions") children]) {
      if (n.kind == NSXMLElementKind)
        [m.groupExpressions addObject:PicaText((NSXMLElement *)n)];
    }
    NSString *pb = PicaParsePageBreak(PicaChild(group, @"PageBreak"));
    if (pb)
      m.pageBreak = pb;
    m.resetPageNumber = PicaParsePageBreakReset(PicaChild(group, @"PageBreak"));
    NSString *pn = PicaParsePageBreakName(PicaChild(group, @"PageBreak"));
    if (pn)
      m.pageName = pn;
    NSArray *gf = PicaParseFilters(PicaChild(group, @"Filters"));
    if ([gf count])
      [m.filters addObjectsFromArray:gf];
  }
  NSString *rep = PicaText(PicaChild(el, @"RepeatOnNewPage"));
  m.repeatOnNewPage = [rep isEqualToString:@"true"] || [rep isEqualToString:@"True"];
  NSString *kwg = PicaText(PicaChild(el, @"KeepWithGroup"));
  if ([kwg length])
    m.keepWithGroup = kwg;
  NSString *kt = PicaText(PicaChild(el, @"KeepTogether"));
  m.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
  NSString *hid = PicaParseVisibility(el);
  if (hid)
    m.hidden = hid;
  NSXMLElement *headerEl = PicaChild(el, @"TablixHeader");
  if (headerEl) {
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = PicaInchesFromString(PicaText(PicaChild(headerEl, @"Size")));
    RDLTablixCell *cc = PicaParseCellContents(PicaChild(headerEl, @"CellContents"));
    h.item = cc.item;
    m.header = h;
  }
  NSArray *sorts = PicaParseSorts(PicaChild(el, @"SortExpressions"));
  if ([sorts count])
    [m.sortExpressions addObjectsFromArray:sorts];
  NSString *mb = PicaParsePageBreak(PicaChild(el, @"PageBreak"));
  if (mb)
    m.pageBreak = mb;
  if (PicaParsePageBreakReset(PicaChild(el, @"PageBreak")))
    m.resetPageNumber = YES;
  NSString *mpn = PicaParsePageBreakName(PicaChild(el, @"PageBreak"));
  if (mpn)
    m.pageName = mpn;
  NSXMLElement *kids = PicaChild(el, @"TablixMembers");
  for (NSXMLNode *n in [kids children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [m.members addObject:PicaParseMember((NSXMLElement *)n)];
  }
  return m;
}

static NSString *PicaTextboxValue(NSXMLElement *el) {
  NSString *v = PicaText(PicaChild(el, @"Value"));
  if ([v length])
    return v;
  NSXMLElement *paragraphs = PicaChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return @"";
  NSMutableArray *paraTexts = [NSMutableArray array];
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    NSMutableString *para = [NSMutableString string];
    for (NSXMLNode *tn in [PicaChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      NSXMLElement *rv = PicaChild((NSXMLElement *)tn, @"Value");
      [para appendString:[rv stringValue] ?: @""]; // preserve run whitespace
    }
    [paraTexts addObject:para];
  }
  return [paraTexts componentsJoinedByString:@"\n"];
}

static NSString *PicaParseVisibility(NSXMLElement *el) {
  NSXMLElement *vis = PicaChild(el, @"Visibility");
  if (vis == nil)
    return nil;
  NSString *h = PicaText(PicaChild(vis, @"Hidden"));
  return [h length] ? h : nil;
}

static NSString *PicaParseHyperlink(NSXMLElement *el) {
  NSXMLElement *info = PicaChild(el, @"ActionInfo");
  if (info == nil)
    return nil;
  for (NSXMLNode *an in [PicaChild(info, @"Actions") children]) {
    if (an.kind != NSXMLElementKind)
      continue;
    NSString *link = PicaText(PicaChild((NSXMLElement *)an, @"Hyperlink"));
    if ([link length])
      return link;
  }
  return nil;
}

static RDLTablixHierarchy *PicaParseHierarchy(NSXMLElement *el) {
  RDLTablixHierarchy *h = [[RDLTablixHierarchy alloc] init];
  NSXMLElement *members = PicaChild(el, @"TablixMembers");
  for (NSXMLNode *n in [members children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [h.members addObject:PicaParseMember((NSXMLElement *)n)];
  }
  return h;
}

static RDLItem *PicaParseItem(NSXMLElement *el) {
  RDLItem *item = [[RDLItem alloc] init];
  item.name = [el attributeForName:@"Name"].stringValue ?: el.localName;
  item.type = el.localName;
  PicaBox(el, item);
  item.style = PicaParseStyle(PicaChild(el, @"Style"));
  item.hidden = PicaParseVisibility(el);
  NSString *zi = PicaText(PicaChild(el, @"ZIndex"));
  if ([zi length])
    item.zIndex = [zi integerValue];
  NSXMLElement *pbEl = PicaChild(el, @"PageBreak");
  if (pbEl) {
    NSString *pb = PicaParsePageBreak(pbEl);
    if (pb)
      item.pageBreak = pb;
    item.resetPageNumber = PicaParsePageBreakReset(pbEl);
    NSString *pn = PicaParsePageBreakName(pbEl);
    if (pn)
      item.pageName = pn;
  }
  NSString *ktc = PicaText(PicaChild(el, @"KeepTogether"));
  if ([ktc length])
    item.keepTogether = [ktc caseInsensitiveCompare:@"true"] == NSOrderedSame;
  if ([el.localName isEqualToString:@"Textbox"]) {
    item.value = PicaTextboxValue(el);
    item.hyperlink = PicaParseHyperlink(el);
    NSString *cg = PicaText(PicaChild(el, @"CanGrow"));
    item.canGrow = ![cg isEqualToString:@"false"];
  } else if ([el.localName isEqualToString:@"Image"]) {
    item.source = PicaText(PicaChild(el, @"Source"));
    item.value = PicaText(PicaChild(el, @"Value"));
    item.sizing = PicaText(PicaChild(el, @"Sizing"));
    item.hyperlink = PicaParseHyperlink(el);
  } else if ([el.localName isEqualToString:@"Chart"]) {
    // Minimal MS-RDL Chart subset: first series + first category grouping.
    item.type = @"Chart";
    item.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
    item.title = PicaText(PicaChild(PicaChild(PicaChild(el, @"ChartTitles"), @"ChartTitle"),
                                    @"Caption"));
    NSXMLElement *data = PicaChild(el, @"ChartData");
    NSXMLElement *series = nil;
    for (NSXMLNode *n in [PicaChild(data, @"ChartSeriesCollection") children]) {
      if (n.kind == NSXMLElementKind) {
        series = (NSXMLElement *)n;
        break;
      }
    }
    NSString *st = PicaText(PicaChild(series, @"Type"));
    item.chartType = [st length] ? st : @"Column";
    NSXMLElement *point = nil;
    for (NSXMLNode *n in [PicaChild(series, @"ChartDataPoints") children]) {
      if (n.kind == NSXMLElementKind) {
        point = (NSXMLElement *)n;
        break;
      }
    }
    NSXMLElement *values = PicaChild(point, @"ChartDataPointValues");
    item.valueField = PicaText(PicaChild(values, @"Y"));
    NSXMLElement *catH = PicaChild(el, @"ChartCategoryHierarchy");
    NSXMLElement *catMember = nil;
    for (NSXMLNode *n in [PicaChild(catH, @"ChartMembers") children]) {
      if (n.kind == NSXMLElementKind) {
        catMember = (NSXMLElement *)n;
        break;
      }
    }
    NSXMLElement *grp = PicaChild(catMember, @"Group");
    for (NSXMLNode *n in [PicaChild(grp, @"GroupExpressions") children]) {
      if (n.kind == NSXMLElementKind) {
        item.categoryField = PicaText((NSXMLElement *)n);
        break;
      }
    }
  } else if ([el.localName isEqualToString:@"List"]) {
    // RDL 2005 List: single-column, single-details-row Tablix whose cell holds
    // a Rectangle with the list contents; repeats once per data row/group.
    item.type = @"Tablix";
    item.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
    RDLItem *cellRect = [[RDLItem alloc] init];
    cellRect.type = @"Rectangle";
    cellRect.name = [NSString stringWithFormat:@"%@_Contents", item.name];
    cellRect.width = item.width;
    cellRect.height = item.height;
    NSXMLElement *ri = PicaChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      if (!PicaIsSupportedItemElement([(NSXMLElement *)n localName])) {
        PicaWarnUnsupported((NSXMLElement *)n);
        continue;
      }
      [cellRect.items addObject:PicaParseItem((NSXMLElement *)n)];
    }
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
    col.width = item.width;
    [body.columns addObject:col];
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    row.height = item.height > 0 ? item.height : 0.28;
    RDLTablixCell *cell = [[RDLTablixCell alloc] init];
    cell.item = cellRect;
    [row.cells addObject:cell];
    [body.rows addObject:row];
    item.tablixBody = body;
    RDLTablixHierarchy *rh = [[RDLTablixHierarchy alloc] init];
    RDLTablixMember *dm = [[RDLTablixMember alloc] init];
    dm.groupName = [NSString stringWithFormat:@"%@_Details", item.name];
    NSXMLElement *grouping = PicaChild(el, @"Grouping");
    if (grouping) {
      dm.groupName = [grouping attributeForName:@"Name"].stringValue ?: dm.groupName;
      for (NSXMLNode *n in [PicaChild(grouping, @"GroupExpressions") children]) {
        if (n.kind == NSXMLElementKind)
          [dm.groupExpressions addObject:PicaText((NSXMLElement *)n)];
      }
    }
    [rh.members addObject:dm];
    item.rowHierarchy = rh;
    [item.sortExpressions addObjectsFromArray:PicaParseSorts(PicaChild(el, @"Sorting"))];
    [item.filters addObjectsFromArray:PicaParseFilters(PicaChild(el, @"Filters"))];
  } else if ([el.localName isEqualToString:@"Tablix"] || [el.localName isEqualToString:@"Table"]) {
    item.type = @"Tablix";
    item.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
    NSXMLElement *bodyEl = PicaChild(el, @"TablixBody");
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    for (NSXMLNode *n in [PicaChild(bodyEl, @"TablixColumns") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
      col.width = PicaInchesFromString(PicaText(PicaChild((NSXMLElement *)n, @"Width")));
      [body.columns addObject:col];
    }
    for (NSXMLNode *rn in [PicaChild(bodyEl, @"TablixRows") children]) {
      if (rn.kind != NSXMLElementKind)
        continue;
      NSXMLElement *rowEl = (NSXMLElement *)rn;
      RDLTablixRow *row = [[RDLTablixRow alloc] init];
      row.height = PicaInchesFromString(PicaText(PicaChild(rowEl, @"Height")));
      if (row.height <= 0)
        row.height = 0.28;
      for (NSXMLNode *cn in [PicaChild(rowEl, @"TablixCells") children]) {
        if (cn.kind != NSXMLElementKind)
          continue;
        [row.cells addObject:PicaParseCellContents(PicaChild((NSXMLElement *)cn, @"CellContents"))];
      }
      [body.rows addObject:row];
    }
    item.tablixBody = body;
    item.noRowsMessage = PicaText(PicaChild(el, @"NoRowsMessage"));
    NSString *rch = PicaText(PicaChild(el, @"RepeatColumnHeaders"));
    item.repeatColumnHeaders = [rch isEqualToString:@"true"] || [rch isEqualToString:@"True"];
    NSString *rrh = PicaText(PicaChild(el, @"RepeatRowHeaders"));
    item.repeatRowHeaders = [rrh isEqualToString:@"true"] || [rrh isEqualToString:@"True"];
    NSString *kt = PicaText(PicaChild(el, @"KeepTogether"));
    item.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
    NSString *pb = PicaParsePageBreak(PicaChild(el, @"PageBreak"));
    if (pb)
      item.pageBreak = pb;
    [item.filters addObjectsFromArray:PicaParseFilters(PicaChild(el, @"Filters"))];
    [item.sortExpressions addObjectsFromArray:PicaParseSorts(PicaChild(el, @"SortExpressions"))];
    NSXMLElement *corner = PicaChild(el, @"TablixCorner");
    for (NSXMLNode *cr in [PicaChild(corner, @"TablixCornerRows") children]) {
      if (cr.kind != NSXMLElementKind)
        continue;
      NSMutableArray *crow = [NSMutableArray array];
      for (NSXMLNode *cc in [(NSXMLElement *)cr children]) {
        if (cc.kind != NSXMLElementKind)
          continue;
        [crow addObject:PicaParseCellContents(PicaChild((NSXMLElement *)cc, @"CellContents"))];
      }
      if ([crow count])
        [item.cornerRows addObject:crow];
    }
    NSXMLElement *ch = PicaChild(el, @"TablixColumnHierarchy");
    if (ch)
      item.columnHierarchy = PicaParseHierarchy(ch);
    NSXMLElement *rh = PicaChild(el, @"TablixRowHierarchy");
    if (rh)
      item.rowHierarchy = PicaParseHierarchy(rh);
    if ([item.rowHierarchy.members count] == 0 && [body.rows count] >= 2) {
      RDLTablixHierarchy *synth = [[RDLTablixHierarchy alloc] init];
      RDLTablixMember *hMem = [[RDLTablixMember alloc] init];
      hMem.repeatOnNewPage = YES;
      hMem.keepWithGroup = @"After";
      RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
      dMem.groupName = [NSString stringWithFormat:@"%@_Details", item.name];
      [synth.members addObject:hMem];
      [synth.members addObject:dMem];
      item.rowHierarchy = synth;
    }
    NSString *found = PicaFindGroupBy(item.rowHierarchy.members);
    if (found)
      item.groupBy = found;
  } else if ([el.localName isEqualToString:@"Rectangle"]) {
    BOOL chart = NO;
    for (NSXMLNode *n in [PicaChild(el, @"CustomProperties") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      NSXMLElement *p = (NSXMLElement *)n;
      NSString *nm = PicaText(PicaChild(p, @"Name"));
      NSString *val = PicaText(PicaChild(p, @"Value"));
      if ([nm isEqualToString:@"Pica.ChartType"]) {
        item.type = @"Chart";
        item.chartType = val;
        chart = YES;
      } else if ([nm isEqualToString:@"Pica.DataSet"])
        item.dataSetName = val;
      else if ([nm isEqualToString:@"Pica.Category"])
        item.categoryField = val;
      else if ([nm isEqualToString:@"Pica.Value"])
        item.valueField = val;
      else if ([nm isEqualToString:@"Pica.Title"])
        item.title = val;
    }
    if (!chart) {
      NSXMLElement *ri = PicaChild(el, @"ReportItems");
      for (NSXMLNode *n in [ri children]) {
        if (n.kind != NSXMLElementKind)
          continue;
        if (!PicaIsSupportedItemElement([(NSXMLElement *)n localName])) {
          PicaWarnUnsupported((NSXMLElement *)n);
          continue;
        }
        [item.items addObject:PicaParseItem((NSXMLElement *)n)];
      }
    }
  }
  return item;
}

static RDLBand *PicaParseBand(NSXMLElement *el, CGFloat fallback) {
  RDLBand *b = [[RDLBand alloc] init];
  if (el == nil) {
    b.height = fallback;
    return b;
  }
  b.height = PicaInchesFromString(PicaText(PicaChild(el, @"Height")));
  if (b.height <= 0)
    b.height = fallback;
  NSString *p1 = PicaText(PicaChild(el, @"PrintOnFirstPage"));
  if ([p1 length])
    b.printOnFirstPage = ![p1 isEqualToString:@"false"];
  NSString *p2 = PicaText(PicaChild(el, @"PrintOnLastPage"));
  if ([p2 length])
    b.printOnLastPage = ![p2 isEqualToString:@"false"];
  NSXMLElement *ri = PicaChild(el, @"ReportItems");
  for (NSXMLNode *n in [ri children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    if (!PicaIsSupportedItemElement([(NSXMLElement *)n localName])) {
      PicaWarnUnsupported((NSXMLElement *)n);
      continue;
    }
    [b.items addObject:PicaParseItem((NSXMLElement *)n)];
  }
  b.style = PicaChild(el, @"Style") ? PicaParseStyle(PicaChild(el, @"Style")) : nil;
  return b;
}

@implementation RDLParser
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error {
  // gPicaParseWarnings is shared parse state; serialize concurrent parses.
  @synchronized (self) {
    return [self picaParseReportFromXMLString:xml error:error];
  }
}

+ (RDLReport *)picaParseReportFromXMLString:(NSString *)xml error:(NSError **)error {
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:error];
  if (doc == nil)
    return nil;
  NSXMLElement *root = doc.rootElement;
  if (![[root localName] isEqualToString:@"Report"]) {
    if (error)
      *error = [NSError errorWithDomain:@"PicaKit" code:1 userInfo:@{
        NSLocalizedDescriptionKey : @"Root element must be Report"
      }];
    return nil;
  }
  RDLReport *r = [RDLReport emptyReportNamed:@"Report"];
  gPicaParseWarnings = [NSMutableArray array];
  NSString *nm = PicaText(PicaChild(root, @"Name"));
  if ([nm length] == 0)
    nm = PicaText(PicaChild(root, @"ReportName"));
  if ([nm length])
    r.name = nm;
  r.author = PicaText(PicaChild(root, @"Author"));
  r.reportDescription = PicaText(PicaChild(root, @"Description"));
  r.width = PicaInchesFromString(PicaText(PicaChild(root, @"Width")));
  NSXMLElement *pageEl = PicaChild(root, @"Page");
  r.page.pageWidth = PicaInchesFromString(PicaText(PicaChild(pageEl, @"PageWidth")));
  r.page.pageHeight = PicaInchesFromString(PicaText(PicaChild(pageEl, @"PageHeight")));
  r.page.leftMargin = PicaInchesFromString(PicaText(PicaChild(pageEl, @"LeftMargin")));
  r.page.rightMargin = PicaInchesFromString(PicaText(PicaChild(pageEl, @"RightMargin")));
  r.page.topMargin = PicaInchesFromString(PicaText(PicaChild(pageEl, @"TopMargin")));
  r.page.bottomMargin = PicaInchesFromString(PicaText(PicaChild(pageEl, @"BottomMargin")));
  r.pageHeader = PicaParseBand(PicaChild(pageEl, @"PageHeader") ?: PicaChild(root, @"PageHeader"), 0.5);
  r.pageFooter = PicaParseBand(PicaChild(pageEl, @"PageFooter") ?: PicaChild(root, @"PageFooter"), 0.4);
  r.body = PicaParseBand(PicaChild(root, @"Body"), 4.0);

  [r.dataSources removeAllObjects];
  NSXMLElement *sources = PicaChild(root, @"DataSources");
  for (NSXMLNode *n in [sources children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = [sEl attributeForName:@"Name"].stringValue ?: @"Demo";
    NSXMLElement *cp = PicaChild(sEl, @"ConnectionProperties");
    src.dataProvider = PicaText(PicaChild(cp, @"DataProvider"));
    src.connectString = PicaText(PicaChild(cp, @"ConnectString"));
    [r.dataSources addObject:src];
  }
  if ([r.dataSources count] == 0) {
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = @"Demo";
    src.dataProvider = @"JSON";
    [r.dataSources addObject:src];
  }

  [r.dataSets removeAllObjects];
  NSXMLElement *sets = PicaChild(root, @"DataSets");
  for (NSXMLNode *n in [sets children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *dsEl = (NSXMLElement *)n;
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = [dsEl attributeForName:@"Name"].stringValue ?: @"DataSet";
    ds.dataSourceName = PicaText(PicaChild(PicaChild(dsEl, @"Query"), @"DataSourceName"));
    ds.commandText = PicaText(PicaChild(PicaChild(dsEl, @"Query"), @"CommandText"));
    NSData *data = [ds.commandText dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
      id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if ([json isKindOfClass:[NSArray class]])
        ds.rows = json;
    }
    NSMutableArray *fields = [NSMutableArray array];
    for (NSXMLNode *f in [PicaChild(dsEl, @"Fields") children]) {
      if (f.kind != NSXMLElementKind)
        continue;
      NSXMLElement *fe = (NSXMLElement *)f;
      NSString *fn = [fe attributeForName:@"Name"].stringValue;
      if (fn == nil)
        continue;
      NSString *calc = PicaText(PicaChild(fe, @"Value"));
      if ([calc length]) {
        RDLField *fld = [[RDLField alloc] init];
        fld.name = fn;
        fld.value = calc;
        [fields addObject:fld];
      } else {
        [fields addObject:fn];
      }
    }
    ds.fields = fields;
    [ds.filters addObjectsFromArray:PicaParseFilters(PicaChild(dsEl, @"Filters"))];
    [r.dataSets addObject:ds];
  }
  [r.embeddedImages removeAllObjects];
  NSXMLElement *imgs = PicaChild(root, @"EmbeddedImages");
  for (NSXMLNode *n in [imgs children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *iEl = (NSXMLElement *)n;
    RDLEmbeddedImage *img = [[RDLEmbeddedImage alloc] init];
    img.name = [iEl attributeForName:@"Name"].stringValue ?: @"Image";
    img.mimeType = PicaText(PicaChild(iEl, @"MIMEType"));
    NSString *b64 = PicaText(PicaChild(iEl, @"ImageData"));
    if ([b64 length])
      img.imageData = [[NSData alloc] initWithBase64EncodedString:b64
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    [r.embeddedImages addObject:img];
  }
  [r.parameters removeAllObjects];
  NSXMLElement *params = PicaChild(root, @"ReportParameters");
  for (NSXMLNode *n in [params children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *p = (NSXMLElement *)n;
    RDLParameter *rp = [[RDLParameter alloc] init];
    rp.name = [p attributeForName:@"Name"].stringValue ?: @"Param";
    rp.dataType = PicaText(PicaChild(p, @"DataType"));
    rp.prompt = PicaText(PicaChild(p, @"Prompt"));
    if ([rp.prompt length] == 0)
      rp.prompt = rp.name;
    NSString *nullable = PicaText(PicaChild(p, @"Nullable"));
    rp.nullable = [nullable caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *multi = PicaText(PicaChild(p, @"MultiValue"));
    rp.multiValue = [multi caseInsensitiveCompare:@"true"] == NSOrderedSame;
    for (NSXMLNode *vn in [PicaChild(PicaChild(p, @"DefaultValue"), @"Values") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.defaultValues addObject:PicaText((NSXMLElement *)vn)];
    }
    rp.defaultValue = [rp.defaultValues firstObject];
    for (NSXMLNode *vn in [PicaChild(PicaChild(p, @"ValidValues"), @"ParameterValues") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.validValues addObject:PicaText(PicaChild((NSXMLElement *)vn, @"Value"))];
    }
    [r.parameters addObject:rp];
  }
  if ([r.name length] == 0)
    r.name = @"Report";
  [r.warnings setArray:gPicaParseWarnings];
  gPicaParseWarnings = nil;
  return r;
}
@end

static NSString *PicaEsc(NSString *s) {
  if (s == nil)
    return @"";
  NSMutableString *o = [s mutableCopy];
  [o replaceOccurrencesOfString:@"&"
                     withString:[@"&" stringByAppendingString:@"amp;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  [o replaceOccurrencesOfString:@"<"
                     withString:[@"&" stringByAppendingString:@"lt;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  [o replaceOccurrencesOfString:@">"
                     withString:[@"&" stringByAppendingString:@"gt;"]
                        options:0
                          range:NSMakeRange(0, o.length)];
  return o;
}

@implementation RDLWriter

static NSString *PicaIn(CGFloat n) {
  return [NSString stringWithFormat:@"%.5fin", n];
}

static void PicaAppendBorder(NSMutableString *xml, NSString *tag, RDLBorder *b) {
  if (b == nil || [b.style length] == 0 || [b.style isEqualToString:@"None"])
    return;
  [xml appendFormat:@"<%@><Style>%@</Style><Width>%@</Width><Color>%@</Color></%@>", tag,
                    PicaEsc(b.style), PicaEsc(b.width ?: @"1pt"), PicaEsc(b.color ?: @"#1a1916"),
                    tag];
}

static void PicaAppendStyle(NSMutableString *xml, RDLStyle *s) {
  if (s == nil)
    s = [RDLStyle defaultStyle];
  [xml appendString:@"<Style>"];
  [xml appendFormat:@"<FontFamily>%@</FontFamily>", PicaEsc(s.fontFamily ?: @"Georgia")];
  [xml appendFormat:@"<FontSize>%@</FontSize>", PicaEsc(s.fontSize ?: @"10pt")];
  [xml appendFormat:@"<FontWeight>%@</FontWeight>", PicaEsc(s.fontWeight ?: @"Normal")];
  if ([s.fontStyle length] && ![s.fontStyle isEqualToString:@"Normal"])
    [xml appendFormat:@"<FontStyle>%@</FontStyle>", PicaEsc(s.fontStyle)];
  [xml appendFormat:@"<Color>%@</Color>", PicaEsc(s.color ?: @"#1a1916")];
  [xml appendFormat:@"<TextAlign>%@</TextAlign>", PicaEsc(s.textAlign ?: @"Left")];
  if ([s.verticalAlign length])
    [xml appendFormat:@"<VerticalAlign>%@</VerticalAlign>", PicaEsc(s.verticalAlign)];
  if ([s.textDecoration length] && ![s.textDecoration isEqualToString:@"None"])
    [xml appendFormat:@"<TextDecoration>%@</TextDecoration>", PicaEsc(s.textDecoration)];
  if ([s.format length])
    [xml appendFormat:@"<Format>%@</Format>", PicaEsc(s.format)];
  if (s.backgroundColor && ![s.backgroundColor isEqualToString:@"Transparent"])
    [xml appendFormat:@"<BackgroundColor>%@</BackgroundColor>", PicaEsc(s.backgroundColor)];
  if ([s.paddingLeft length])
    [xml appendFormat:@"<PaddingLeft>%@</PaddingLeft>", PicaEsc(s.paddingLeft)];
  if ([s.paddingRight length])
    [xml appendFormat:@"<PaddingRight>%@</PaddingRight>", PicaEsc(s.paddingRight)];
  if ([s.paddingTop length])
    [xml appendFormat:@"<PaddingTop>%@</PaddingTop>", PicaEsc(s.paddingTop)];
  if ([s.paddingBottom length])
    [xml appendFormat:@"<PaddingBottom>%@</PaddingBottom>", PicaEsc(s.paddingBottom)];
  if (s.border && ![s.border.style isEqualToString:@"None"])
    PicaAppendBorder(xml, @"Border", s.border);
  PicaAppendBorder(xml, @"TopBorder", s.borderTop);
  PicaAppendBorder(xml, @"BottomBorder", s.borderBottom);
  PicaAppendBorder(xml, @"LeftBorder", s.borderLeft);
  PicaAppendBorder(xml, @"RightBorder", s.borderRight);
  [xml appendString:@"</Style>"];
}

static void PicaAppendBox(NSMutableString *xml, RDLItem *it) {
  [xml appendFormat:@"<Top>%@</Top><Left>%@</Left><Width>%@</Width><Height>%@</Height>",
                    PicaIn(it.top), PicaIn(it.left), PicaIn(it.width), PicaIn(it.height)];
}

static void PicaAppendItem(NSMutableString *xml, RDLItem *it);

static void PicaAppendFilters(NSMutableString *xml, NSArray<RDLFilter *> *filters) {
  if ([filters count] == 0)
    return;
  [xml appendString:@"<Filters>"];
  for (RDLFilter *f in filters) {
    [xml appendFormat:@"<Filter><FilterExpression>%@</FilterExpression><Operator>%@</Operator><FilterValues>",
                      PicaEsc(f.expression), PicaEsc(f.oper.length ? f.oper : @"Equal")];
    for (NSString *v in f.values)
      [xml appendFormat:@"<FilterValue>%@</FilterValue>", PicaEsc(v)];
    [xml appendString:@"</FilterValues></Filter>"];
  }
  [xml appendString:@"</Filters>"];
}

static void PicaAppendSorts(NSMutableString *xml, NSArray<RDLSortExpression *> *sorts) {
  if ([sorts count] == 0)
    return;
  [xml appendString:@"<SortExpressions>"];
  for (RDLSortExpression *s in sorts) {
    [xml appendFormat:@"<SortExpression><Value>%@</Value>", PicaEsc(s.expression)];
    if ([s.direction length] && ![s.direction isEqualToString:@"Ascending"])
      [xml appendFormat:@"<Direction>%@</Direction>", PicaEsc(s.direction)];
    [xml appendString:@"</SortExpression>"];
  }
  [xml appendString:@"</SortExpressions>"];
}

static void PicaAppendPageBreak(NSMutableString *xml, NSString *loc, BOOL reset, NSString *pageName) {
  if (([loc length] == 0 || [loc isEqualToString:@"None"]) && !reset && [pageName length] == 0)
    return;
  [xml appendString:@"<PageBreak>"];
  if ([loc length] && ![loc isEqualToString:@"None"])
    [xml appendFormat:@"<BreakLocation>%@</BreakLocation>", PicaEsc(loc)];
  if (reset)
    [xml appendString:@"<ResetPageNumber>true</ResetPageNumber>"];
  if ([pageName length])
    [xml appendFormat:@"<PageName>%@</PageName>", PicaEsc(pageName)];
  [xml appendString:@"</PageBreak>"];
}

static void PicaAppendMember(NSMutableString *xml, RDLTablixMember *m) {
  [xml appendString:@"<TablixMember>"];
  if ([m.groupName length]) {
    [xml appendFormat:@"<Group Name=\"%@\">", PicaEsc(m.groupName)];
    if ([m.groupExpressions count]) {
      [xml appendString:@"<GroupExpressions>"];
      for (NSString *e in m.groupExpressions)
        [xml appendFormat:@"<GroupExpression>%@</GroupExpression>", PicaEsc(e)];
      [xml appendString:@"</GroupExpressions>"];
    }
    PicaAppendPageBreak(xml, m.pageBreak, m.resetPageNumber, m.pageName);
    PicaAppendFilters(xml, m.filters);
    [xml appendString:@"</Group>"];
  }
  PicaAppendSorts(xml, m.sortExpressions);
  if (m.header) {
    [xml appendFormat:@"<TablixHeader><Size>%@</Size><CellContents>", PicaIn(m.header.size)];
    if (m.header.item)
      PicaAppendItem(xml, m.header.item);
    [xml appendString:@"</CellContents></TablixHeader>"];
  }
  if (m.repeatOnNewPage)
    [xml appendString:@"<RepeatOnNewPage>true</RepeatOnNewPage>"];
  if ([m.keepWithGroup length] && ![m.keepWithGroup isEqualToString:@"None"])
    [xml appendFormat:@"<KeepWithGroup>%@</KeepWithGroup>", PicaEsc(m.keepWithGroup)];
  if (m.keepTogether)
    [xml appendString:@"<KeepTogether>true</KeepTogether>"];
  if ([m.hidden length])
    [xml appendFormat:@"<Visibility><Hidden>%@</Hidden></Visibility>", PicaEsc(m.hidden)];
  if ([m.members count]) {
    [xml appendString:@"<TablixMembers>"];
    for (RDLTablixMember *c in m.members)
      PicaAppendMember(xml, c);
    [xml appendString:@"</TablixMembers>"];
  }
  [xml appendString:@"</TablixMember>"];
}

static void PicaAppendTablix(NSMutableString *xml, RDLItem *it) {
  if (it.tablixBody == nil || [it.tablixBody.rows count] == 0)
    [it rebuildTableFromColumns];
  [xml appendFormat:@"<Tablix Name=\"%@\">", PicaEsc(it.name)];
  PicaAppendBox(xml, it);
  [xml appendFormat:@"<DataSetName>%@</DataSetName>", PicaEsc(it.dataSetName)];
  if ([it.noRowsMessage length])
    [xml appendFormat:@"<NoRowsMessage>%@</NoRowsMessage>", PicaEsc(it.noRowsMessage)];
  if (it.repeatColumnHeaders)
    [xml appendString:@"<RepeatColumnHeaders>true</RepeatColumnHeaders>"];
  if (it.repeatRowHeaders)
    [xml appendString:@"<RepeatRowHeaders>true</RepeatRowHeaders>"];
  if (it.keepTogether)
    [xml appendString:@"<KeepTogether>true</KeepTogether>"];
  PicaAppendPageBreak(xml, it.pageBreak, it.resetPageNumber, it.pageName);
  PicaAppendFilters(xml, it.filters);
  PicaAppendSorts(xml, it.sortExpressions);
  PicaAppendStyle(xml, it.style);
  if ([it.cornerRows count]) {
    [xml appendString:@"<TablixCorner><TablixCornerRows>"];
    for (NSArray *crow in it.cornerRows) {
      [xml appendString:@"<TablixCornerRow>"];
      for (RDLTablixCell *cell in crow) {
        [xml appendString:@"<TablixCornerCell><CellContents>"];
        if (cell.item)
          PicaAppendItem(xml, cell.item);
        [xml appendString:@"</CellContents></TablixCornerCell>"];
      }
      [xml appendString:@"</TablixCornerRow>"];
    }
    [xml appendString:@"</TablixCornerRows></TablixCorner>"];
  }
  [xml appendString:@"<TablixBody><TablixColumns>"];
  for (RDLTablixColumn *c in it.tablixBody.columns)
    [xml appendFormat:@"<TablixColumn><Width>%@</Width></TablixColumn>", PicaIn(c.width)];
  [xml appendString:@"</TablixColumns><TablixRows>"];
  for (RDLTablixRow *row in it.tablixBody.rows) {
    [xml appendFormat:@"<TablixRow><Height>%@</Height><TablixCells>", PicaIn(row.height)];
    for (RDLTablixCell *cell in row.cells) {
      [xml appendString:@"<TablixCell><CellContents>"];
      if (cell.item)
        PicaAppendItem(xml, cell.item);
      if (cell.colSpan > 1)
        [xml appendFormat:@"<ColSpan>%ld</ColSpan>", (long)cell.colSpan];
      if (cell.rowSpan > 1)
        [xml appendFormat:@"<RowSpan>%ld</RowSpan>", (long)cell.rowSpan];
      [xml appendString:@"</CellContents></TablixCell>"];
    }
    [xml appendString:@"</TablixCells></TablixRow>"];
  }
  [xml appendString:@"</TablixRows></TablixBody>"];
  [xml appendString:@"<TablixColumnHierarchy><TablixMembers>"];
  if ([it.columnHierarchy.members count]) {
    for (RDLTablixMember *m in it.columnHierarchy.members)
      PicaAppendMember(xml, m);
  } else {
    for (NSUInteger i = 0; i < [it.tablixBody.columns count]; i++)
      [xml appendString:@"<TablixMember />"];
  }
  [xml appendString:@"</TablixMembers></TablixColumnHierarchy>"];
  [xml appendString:@"<TablixRowHierarchy><TablixMembers>"];
  if ([it.rowHierarchy.members count]) {
    for (RDLTablixMember *m in it.rowHierarchy.members)
      PicaAppendMember(xml, m);
  } else {
    [xml appendString:@"<TablixMember><RepeatOnNewPage>true</RepeatOnNewPage>"
                    @"<KeepWithGroup>After</KeepWithGroup></TablixMember>"];
    [xml appendFormat:@"<TablixMember><Group Name=\"%@\" /></TablixMember>",
                      PicaEsc([NSString stringWithFormat:@"%@_Details", it.name ?: @"Tablix"])];
  }
  [xml appendString:@"</TablixMembers></TablixRowHierarchy></Tablix>"];
}

static void PicaAppendVisibility(NSMutableString *xml, RDLItem *it) {
  if ([it.hidden length])
    [xml appendFormat:@"<Visibility><Hidden>%@</Hidden></Visibility>", PicaEsc(it.hidden)];
}

static void PicaAppendHyperlink(NSMutableString *xml, RDLItem *it) {
  if ([it.hyperlink length])
    [xml appendFormat:@"<ActionInfo><Actions><Action><Hyperlink>%@</Hyperlink></Action></Actions>"
                      @"</ActionInfo>",
                      PicaEsc(it.hyperlink)];
}

static void PicaAppendItemPagination(NSMutableString *xml, RDLItem *it) {
  if (it.keepTogether)
    [xml appendString:@"<KeepTogether>true</KeepTogether>"];
  PicaAppendPageBreak(xml, it.pageBreak, it.resetPageNumber, it.pageName);
}

static void PicaAppendItem(NSMutableString *xml, RDLItem *it) {
  if ([it.type isEqualToString:@"Line"]) {
    [xml appendFormat:@"<Line Name=\"%@\">", PicaEsc(it.name)];
    PicaAppendBox(xml, it);
    PicaAppendVisibility(xml, it);
    PicaAppendStyle(xml, it.style);
    [xml appendString:@"</Line>"];
    return;
  }
  if ([it.type isEqualToString:@"Image"]) {
    [xml appendFormat:@"<Image Name=\"%@\">", PicaEsc(it.name)];
    PicaAppendBox(xml, it);
    PicaAppendVisibility(xml, it);
    PicaAppendHyperlink(xml, it);
    [xml appendFormat:@"<Source>%@</Source><Value>%@</Value><Sizing>%@</Sizing>",
                      PicaEsc(it.source.length ? it.source : @"External"), PicaEsc(it.value),
                      PicaEsc(it.sizing.length ? it.sizing : @"FitProportional")];
    PicaAppendStyle(xml, it.style);
    [xml appendString:@"</Image>"];
    return;
  }
  if ([it.type isEqualToString:@"Rectangle"]) {
    [xml appendFormat:@"<Rectangle Name=\"%@\">", PicaEsc(it.name)];
    PicaAppendBox(xml, it);
    PicaAppendVisibility(xml, it);
    PicaAppendItemPagination(xml, it);
    PicaAppendStyle(xml, it.style);
    if ([it.items count]) {
      [xml appendString:@"<ReportItems>"];
      for (RDLItem *c in it.items)
        PicaAppendItem(xml, c);
      [xml appendString:@"</ReportItems>"];
    }
    [xml appendString:@"</Rectangle>"];
    return;
  }
  if ([it.type isEqualToString:@"Chart"]) {
    [xml appendFormat:@"<Rectangle Name=\"%@\">", PicaEsc(it.name)];
    PicaAppendBox(xml, it);
    PicaAppendStyle(xml, it.style);
    [xml appendString:@"<CustomProperties>"];
    [xml appendFormat:@"<CustomProperty><Name>Pica.ChartType</Name><Value>%@</Value></CustomProperty>",
                      PicaEsc(it.chartType ?: @"Column")];
    [xml appendFormat:@"<CustomProperty><Name>Pica.DataSet</Name><Value>%@</Value></CustomProperty>",
                      PicaEsc(it.dataSetName)];
    [xml appendFormat:@"<CustomProperty><Name>Pica.Category</Name><Value>%@</Value></CustomProperty>",
                      PicaEsc(it.categoryField)];
    [xml appendFormat:@"<CustomProperty><Name>Pica.Value</Name><Value>%@</Value></CustomProperty>",
                      PicaEsc(it.valueField)];
    [xml appendFormat:@"<CustomProperty><Name>Pica.Title</Name><Value>%@</Value></CustomProperty>",
                      PicaEsc(it.title)];
    [xml appendString:@"</CustomProperties></Rectangle>"];
    return;
  }
  if ([it.type isEqualToString:@"Tablix"] || [it.type isEqualToString:@"Table"]) {
    PicaAppendTablix(xml, it);
    return;
  }
  [xml appendFormat:@"<Textbox Name=\"%@\">", PicaEsc(it.name)];
  PicaAppendBox(xml, it);
  PicaAppendVisibility(xml, it);
  PicaAppendHyperlink(xml, it);
  PicaAppendItemPagination(xml, it);
  [xml appendFormat:@"<CanGrow>%@</CanGrow>", it.canGrow ? @"true" : @"false"];
  PicaAppendStyle(xml, it.style);
  [xml appendFormat:@"<Paragraphs><Paragraph><TextRuns><TextRun><Value>%@</Value>",
                    PicaEsc(it.value)];
  PicaAppendStyle(xml, it.style);
  [xml appendString:@"</TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"];
}

static void PicaAppendBand(NSMutableString *xml, RDLBand *b) {
  [xml appendFormat:@"<Height>%@</Height>", PicaIn(b.height)];
  [xml appendFormat:@"<PrintOnFirstPage>%@</PrintOnFirstPage>", b.printOnFirstPage ? @"true" : @"false"];
  [xml appendFormat:@"<PrintOnLastPage>%@</PrintOnLastPage>", b.printOnLastPage ? @"true" : @"false"];
  if (b.style)
    PicaAppendStyle(xml, b.style);
  [xml appendString:@"<ReportItems>"];
  for (RDLItem *it in b.items)
    PicaAppendItem(xml, it);
  [xml appendString:@"</ReportItems>"];
}

+ (NSString *)XMLStringFromReport:(RDLReport *)report {
  NSMutableString *xml = [NSMutableString string];
  [xml appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"];
  [xml appendString:@"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
                    @"reportdefinition\" xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/"
                    @"reportdesigner\">\n"];
  [xml appendString:@"  <rd:ReportUnitType>Inch</rd:ReportUnitType>\n"];
  [xml appendFormat:@"  <Name>%@</Name>\n", PicaEsc(report.name)];
  [xml appendFormat:@"  <Description>%@</Description>\n", PicaEsc(report.reportDescription)];
  [xml appendFormat:@"  <Author>%@</Author>\n", PicaEsc(report.author)];
  [xml appendFormat:@"  <Width>%@</Width>\n", PicaIn(report.width)];
  [xml appendString:@"  <DataSources>"];
  for (RDLDataSource *src in report.dataSources) {
    [xml appendFormat:@"<DataSource Name=\"%@\"><ConnectionProperties>"
                      @"<DataProvider>%@</DataProvider><ConnectString>%@</ConnectString>"
                      @"</ConnectionProperties></DataSource>",
                      PicaEsc(src.name), PicaEsc(src.dataProvider ?: @"JSON"),
                      PicaEsc(src.connectString)];
  }
  if ([report.dataSources count] == 0)
    [xml appendString:@"<DataSource Name=\"Demo\"><ConnectionProperties>"
                      @"<DataProvider>JSON</DataProvider><ConnectString></ConnectString>"
                      @"</ConnectionProperties></DataSource>"];
  [xml appendString:@"</DataSources>\n  <DataSets>"];
  for (RDLDataSet *ds in report.dataSets) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:(ds.rows ?: @[]) options:0 error:nil];
    NSString *cmd = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    [xml appendFormat:@"<DataSet Name=\"%@\"><Query><DataSourceName>%@</DataSourceName>"
                      @"<CommandText><![CDATA[%@]]></CommandText></Query><Fields>",
                      PicaEsc(ds.name), PicaEsc(ds.dataSourceName ?: @"Demo"), cmd];
    for (id f in ds.fields) {
      if ([f isKindOfClass:[RDLField class]] && [[(RDLField *)f value] length]) {
        RDLField *fld = (RDLField *)f;
        [xml appendFormat:@"<Field Name=\"%@\"><Value>%@</Value></Field>", PicaEsc(fld.name),
                          PicaEsc(fld.value)];
        continue;
      }
      NSString *name = [f isKindOfClass:[RDLField class]] ? [(RDLField *)f name] : [f description];
      NSString *df = [f isKindOfClass:[RDLField class]] ? [(RDLField *)f dataField] : name;
      [xml appendFormat:@"<Field Name=\"%@\"><DataField>%@</DataField></Field>", PicaEsc(name),
                        PicaEsc(df.length ? df : name)];
    }
    [xml appendString:@"</Fields>"];
    PicaAppendFilters(xml, ds.filters);
    [xml appendString:@"</DataSet>"];
  }
  [xml appendString:@"</DataSets>\n  <ReportParameters>"];
  for (RDLParameter *p in report.parameters) {
    [xml appendFormat:@"<ReportParameter Name=\"%@\"><DataType>%@</DataType><Prompt>%@</Prompt>",
                      PicaEsc(p.name), PicaEsc(p.dataType ?: @"String"),
                      PicaEsc(p.prompt.length ? p.prompt : p.name)];
    if (p.nullable)
      [xml appendString:@"<Nullable>true</Nullable>"];
    if (p.multiValue)
      [xml appendString:@"<MultiValue>true</MultiValue>"];
    NSArray *defaults = [p.defaultValues count] ? p.defaultValues
                        : (p.defaultValue ? @[ p.defaultValue ] : @[]);
    [xml appendString:@"<DefaultValue><Values>"];
    for (NSString *v in defaults)
      [xml appendFormat:@"<Value>%@</Value>", PicaEsc(v)];
    [xml appendString:@"</Values></DefaultValue>"];
    if ([p.validValues count]) {
      [xml appendString:@"<ValidValues><ParameterValues>"];
      for (NSString *v in p.validValues)
        [xml appendFormat:@"<ParameterValue><Value>%@</Value></ParameterValue>", PicaEsc(v)];
      [xml appendString:@"</ParameterValues></ValidValues>"];
    }
    [xml appendString:@"</ReportParameter>"];
  }
  [xml appendString:@"</ReportParameters>\n"];
  if ([report.embeddedImages count]) {
    [xml appendString:@"  <EmbeddedImages>"];
    for (RDLEmbeddedImage *img in report.embeddedImages) {
      [xml appendFormat:@"<EmbeddedImage Name=\"%@\"><MIMEType>%@</MIMEType><ImageData>%@</ImageData>"
                        @"</EmbeddedImage>",
                        PicaEsc(img.name), PicaEsc(img.mimeType ?: @"image/png"),
                        [img.imageData base64EncodedStringWithOptions:0] ?: @""];
    }
    [xml appendString:@"</EmbeddedImages>\n"];
  }
  [xml appendString:@"  <Body>"];
  PicaAppendBand(xml, report.body);
  [xml appendString:@"</Body>\n  <Page>"];
  [xml appendFormat:@"<PageHeight>%@</PageHeight><PageWidth>%@</PageWidth>",
                    PicaIn(report.page.pageHeight), PicaIn(report.page.pageWidth)];
  [xml appendFormat:@"<LeftMargin>%@</LeftMargin><RightMargin>%@</RightMargin>"
                    @"<TopMargin>%@</TopMargin><BottomMargin>%@</BottomMargin>",
                    PicaIn(report.page.leftMargin), PicaIn(report.page.rightMargin),
                    PicaIn(report.page.topMargin), PicaIn(report.page.bottomMargin)];
  [xml appendString:@"<PageHeader>"];
  PicaAppendBand(xml, report.pageHeader);
  [xml appendString:@"</PageHeader><PageFooter>"];
  PicaAppendBand(xml, report.pageFooter);
  [xml appendString:@"</PageFooter></Page>\n</Report>\n"];
  return xml;
}
@end
