/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The places in a report where one thing refers to another by name: every
// expression, and every ToggleItem. What renaming a report item has to visit,
// so that ReportItems!Total and a toggle naming Total follow it.
#import <Foundation/Foundation.h>
#import "RDLReport.h"

typedef NS_ENUM(NSInteger, RDLReferenceSiteKind) {
  RDLReferenceSiteKindUnspecified = 0,
  // An RDLValue or RDLExpr that is an expression, or text that may be one --
  // a text box's, a text run's or an image's value.
  RDLReferenceSiteKindExpression,
  // The name of the text box that shows and hides something.
  RDLReferenceSiteKindToggleItem,
};

// One such place: the object that holds it, and where in that object.
@interface RDLReferenceSite : NSObject
@property (nonatomic, readonly) RDLReferenceSiteKind kind;
@property (nonatomic, readonly, strong) id owner;
@property (nonatomic, readonly, copy) NSString *key;
// What is there now, and putting something else there. A value in a list or a
// dictionary is put back by giving the owner a new list or dictionary.
- (id)value;
- (void)setValue:(id)value;
// What is there now, as it would be with report item `name` called `newName`;
// nil when nothing here refers to that item.
- (id)valueRenamingReportItem:(NSString *)name to:(NSString *)newName;
@end

@interface RDLReport (RDLReferenceSites)
// Every such place in the report: its bands and everything in them however
// deep, its datasets, parameters and variables. Found by walking the model's
// own stored properties, so a property added to the model is found without
// this being told about it. What belongs to another report -- a subreport's
// definition -- is not walked, and neither is data.
- (NSArray<RDLReferenceSite *> *)referenceSites;
@end
