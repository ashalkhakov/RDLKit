// PicaKit — native RDL generator (RDL + data + parameters → pages / PDF / HTML).
// Pair with ../PicaDesigner for the AppKit designer.
// Pure Objective-C, ARC. Cocoa and GNUstep. No Swift, no UIKit.
#import "PicaCompatibility.h"
#import "RDLReport.h"
#import "RDLParser.h"
#import "RDLExpression.h"
#import "RDLLayoutEngine.h"
#import "RDLView.h"
#import "RDLBackend.h"
#import "RDLGenerator.h"
// Editor core: document, selection, insertion policy and the undoable
// mutation layer. UI-free, so PicaKitTests can cover it.
#import "RDLChange.h"
#import "RDLSelection.h"
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLItemFactory.h"
// Text: one style->AppKit translation, the rich-text codec, and expression
// completion (all UI-free so they can be checked).
#import "RDLTextAttributes.h"
#import "RDLRichTextCodec.h"
#import "RDLExpressionCompletion.h"
// Page geometry: coordinate transform, band placement, hit testing.
#import "RDLPageGeometry.h"
