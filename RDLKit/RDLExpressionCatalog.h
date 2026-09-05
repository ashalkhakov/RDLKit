/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

// What an attribute will accept once its expression has been evaluated. An
// expression is still an expression whatever it sits in; this says what its
// result has to be coercible to, so the editor can say what is expected and a
// check can say when it plainly is not.
typedef NS_ENUM(NSInteger, RDLExpressionContext) {
  RDLExpressionContextUnspecified = 0,
  // Anything with a string form: a textbox value, a label.
  RDLExpressionContextText,
  // #rrggbb or a named colour: Color, BackgroundColor, a border colour.
  RDLExpressionContextColor,
  // A measurement with a unit: FontSize, padding, a border width.
  RDLExpressionContextLength,
  // A number, for a count or a position.
  RDLExpressionContextNumber,
  // True or False: Hidden, ToggleItem, a filter's result.
  RDLExpressionContextBoolean,
  // One of a fixed set of RDL keywords: FontWeight, TextAlign, BorderStyle.
  RDLExpressionContextKeyword
};

// A sentence naming what the context expects, for the editor to show.
FOUNDATION_EXPORT NSString *RDLExpressionContextDescription(RDLExpressionContext context);

// One function the evaluator implements, for the picker.
@interface RDLFunctionInfo : NSObject
@property (nonatomic, copy) NSString *name;
// "Sum(expression)" -- the name with its arguments named.
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSString *summary;
// "Aggregate", "Text", "Number", "Date", "Logical", "Report", "Lookup",
// "Conversion". The picker groups by this.
@property (nonatomic, copy) NSString *category;
@end

@interface RDLExpressionCatalog : NSObject
// Every function RDLExpression evaluates. Nothing here is aspirational: a name
// in this list is a name the evaluator answers to.
+ (NSArray<RDLFunctionInfo *> *)functions;
// The categories, in the order the picker should show them.
+ (NSArray<NSString *> *)categories;
+ (NSArray<RDLFunctionInfo *> *)functionsInCategory:(NSString *)category;
// The one named, or nil. Case-insensitive, as the evaluator is.
+ (RDLFunctionInfo *)functionNamed:(NSString *)name;
@end
