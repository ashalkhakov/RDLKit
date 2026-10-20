/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// RDL 2008 to RDL 2010: a report became a list of sections, each with its own
// body, width and page.
#import "RDLUpgraderSupport.h"

// Body, Width and Page belong to a ReportSection in 2010 and later; 2008 and
// earlier put them straight under Report, as did this kit's own writer. The
// page bands go under Page, where 2008 already put them and 2003 did not.
// Everything is moved rather than copied, so nothing is read twice.
void RDLMigrate2008To2010(NSXMLElement *root) {
  if (RDLKid(root, @"ReportSections") != nil)
    return;

  NSXMLElement *body = RDLKid(root, @"Body");
  NSXMLElement *width = RDLKid(root, @"Width");
  NSXMLElement *page = RDLKid(root, @"Page");
  NSXMLElement *header = RDLKid(root, @"PageHeader");
  NSXMLElement *footer = RDLKid(root, @"PageFooter");
  if (body == nil && width == nil && page == nil)
    return;  // nothing that belongs in a section; leave the file as it is

  // Columns and ColumnSpacing were the Body's in 2005; 2008 made them the Page's.
  NSXMLElement *columns = RDLKid(body, @"Columns");
  NSXMLElement *columnSpacing = RDLKid(body, @"ColumnSpacing");
  if ((header || footer || columns || columnSpacing) && page == nil)
    page = RDLNew(@"Page");
  else if (page)
    page = RDLTake(page);
  if (header)
    [page addChild:RDLTake(header)];
  if (footer)
    [page addChild:RDLTake(footer)];
  if (columns)
    [page addChild:RDLTake(columns)];
  if (columnSpacing)
    [page addChild:RDLTake(columnSpacing)];

  NSXMLElement *section = RDLNew(@"ReportSection");
  if (body)
    [section addChild:RDLTake(body)];
  if (width)
    [section addChild:RDLTake(width)];
  if (page)
    [section addChild:page];
  NSXMLElement *sections = RDLNew(@"ReportSections");
  [sections addChild:section];
  [root addChild:sections];
}
