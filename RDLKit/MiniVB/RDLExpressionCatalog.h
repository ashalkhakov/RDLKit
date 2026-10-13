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

@class RDLFunctionCategory;

// One name a picker can put into an expression. Every function the evaluator
// implements is one of these; so is anything a particular report offers, such
// as one of its fields, which is why the summary and the insertion are here
// rather than assumed from the name.
@interface RDLFunctionInfo : NSObject
@property (nonatomic, copy) NSString *name;
// "Sum(expression)" -- the name with its arguments named.
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSString *summary;
// What a picker types when this is chosen. A function opens its bracket,
// because its arguments come next; a name that stands on its own goes in
// whole. Defaults to the name.
@property (nonatomic, copy) NSString *insertion;
// The one category this belongs to. Weak: a category holds its functions, and
// this is the way back.
@property (nonatomic, weak) RDLFunctionCategory *category;
@end

// A group of them, under a name. A picker shows the categories in one table
// and the chosen category's functions in another, so it needs no grouping
// logic of its own -- and a report can make categories of its own the same
// way, for the names only it knows about.
@interface RDLFunctionCategory : NSObject
// Every function given is assigned to this category, which is what makes the
// back pointer true.
+ (instancetype)categoryNamed:(NSString *)name
                   containing:(NSArray<RDLFunctionInfo *> *)functions;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSArray<RDLFunctionInfo *> *functions;
@end

@interface RDLExpressionCatalog : NSObject
// Every function RDLExpression evaluates, in no particular order. Nothing here
// is aspirational: a name in this list is a name the evaluator answers to.
+ (NSArray<RDLFunctionInfo *> *)functions;
// The same functions, grouped, in the order a picker should show them.
+ (NSArray<RDLFunctionCategory *> *)categories;
// The one named, or nil. Case-insensitive, as the evaluator is.
+ (RDLFunctionInfo *)functionNamed:(NSString *)name;
+ (RDLFunctionCategory *)categoryNamed:(NSString *)name;
@end
