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
// Style -> AppKit text attributes, shared with the designer canvas and its
// rich-text codec because RDLView's preview needs the same translation.
#import "RDLTextAttributes.h"
