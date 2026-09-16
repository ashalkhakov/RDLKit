// RDLKit — native RDL generator (RDL + data + parameters → pages / PDF / HTML).
// Pair with ../RDLDesigner for the AppKit designer.
// Pure Objective-C, ARC. Cocoa and GNUstep. No Swift, no UIKit.
#import "RDLCompatibility.h"
#import "RDLReport.h"
#import "RDLParser.h"
#import "RDLUpgrader.h"
#import "RDLChartRenderer.h"
#import "RDLChecker.h"
#import "RDLZipArchive.h"
#import "RDLDocxReader.h"
#import "RDLImporter.h"
#import "RDLExpression.h"
#import "RDLExpressionCatalog.h"
#import "RDLLayoutEngine.h"
#import "RDLView.h"
#import "RDLBackend.h"
#import "RDLGenerator.h"
// A report's parameters, worked out and checked as a report server does.
#import "RDLParameterValues.h"
#import "RDLNumber.h"
// The stage before layout that evaluates the data sources for the parameters.
#import "RDLDataEvaluation.h"
// Datasets from documents: JSON, XML and CSV, which is what a local report
// viewer binds to.
#import "RDLJSONPath.h"
#import "RDLDataProvider.h"
#import "RDLJSONDataProvider.h"
#import "RDLXMLDataProvider.h"
#import "RDLCSVDataProvider.h"
// Subreports: the report definitions a report names, found and loaded.
#import "RDLSubreportLoader.h"
// Style -> AppKit text attributes, shared with the designer canvas and its
// rich-text codec because RDLView's preview needs the same translation.
#import "RDLTextAttributes.h"
// One drawing of a border, shared by the preview, the PDF and the canvas.
#import "RDLBorderPainter.h"
