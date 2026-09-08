/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

// JSONPath: which part of a JSON document something is. Its own module because
// it is its own subject -- nothing here knows about reports or datasets, and it
// works on any graph NSJSONSerialization produces.
//
// Written rather than borrowed. The only Objective-C implementation to be found
// -- SMJJSONPath, a port of Jayway's -- is no longer published, and the
// alternatives are C libraries that bring GLib or a JSON parser of their own
// along with them.
//
// What is supported, which is the set the mainstream implementations agree on:
//
//   $                the document
//   .name  ['name']  a member, quoted when it has dots or spaces in it
//   [2]  [-1]        an element, counted from the end when negative
//   [*]  .*          every element or member
//   [1:3] [:2] [::2] a slice, with an optional step
//   [0,2] ['a','b']  a union of elements or members
//   ..name  ..*      every match at any depth
//   [?(@.isbn)]      the ones that have it
//   [?(@.p < 10 && @.q == 'x')]   comparisons, && and || and !
//
// What is not: script expressions (`[(@.length-1)]`) and functions. A path
// using one is reported rather than quietly selecting the wrong nodes -- which
// is the failure that matters here, because the report still renders.
//
// One caveat, and it is Foundation's: an NSDictionary has no member order, so a
// selection that crosses object members ("$.store.*", "$..author") comes back
// in an unspecified order. Selections through arrays keep the document's order.

typedef NS_ENUM(NSInteger, RDLJSONPathStepKind) {
  RDLJSONPathStepKindUnspecified = 0,
  RDLJSONPathStepKindRoot,               // $
  RDLJSONPathStepKindChild,              // .name  ['name']
  RDLJSONPathStepKindIndex,              // [2]  [-1]
  RDLJSONPathStepKindWildcard,           // [*]  .*
  RDLJSONPathStepKindSlice,              // [1:3]  [:2]  [::2]
  RDLJSONPathStepKindUnion,              // [0,2]  ['a','b']
  RDLJSONPathStepKindDescendant,         // ..name
  RDLJSONPathStepKindDescendantWildcard, // ..*
  RDLJSONPathStepKindFilter,             // [?(…)]
};

// A filter's tree. An enum rather than a string for the same reason the rest of
// this kit uses one: a mistyped comparison is a branch that never runs.
typedef NS_ENUM(NSInteger, RDLJSONFilterKind) {
  RDLJSONFilterKindUnspecified = 0,
  RDLJSONFilterKindExists,  // @.isbn
  RDLJSONFilterKindCompare, // @.price < 10
  RDLJSONFilterKindAnd,
  RDLJSONFilterKindOr,
  RDLJSONFilterKindNot,
};

typedef NS_ENUM(NSInteger, RDLJSONFilterOperator) {
  RDLJSONFilterOperatorUnspecified = 0,
  RDLJSONFilterOperatorEqual,
  RDLJSONFilterOperatorNotEqual,
  RDLJSONFilterOperatorLess,
  RDLJSONFilterOperatorLessOrEqual,
  RDLJSONFilterOperatorGreater,
  RDLJSONFilterOperatorGreaterOrEqual,
};

@interface RDLJSONFilter : NSObject
@property (nonatomic, assign) RDLJSONFilterKind kind;
@property (nonatomic, assign) RDLJSONFilterOperator op;
// The path from `@` to what is being tested: @[] is `@` itself, @[@"a", @"b"]
// is `@.a.b`.
@property (nonatomic, copy) NSArray<NSString *> *path;
// What it is compared against: an NSNumber, an NSString, or NSNull.
@property (nonatomic, strong) id literal;
@property (nonatomic, strong) RDLJSONFilter *left, *right;
// Whether one candidate passes.
- (BOOL)matches:(id)node;
@end

@interface RDLJSONPathStep : NSObject
@property (nonatomic, assign) RDLJSONPathStepKind kind;
@property (nonatomic, copy) NSString *name;    // Child, Descendant
@property (nonatomic, assign) NSInteger index; // Index
// Slice: nil start or end means "from the beginning" / "to the end".
@property (nonatomic, strong) NSNumber *sliceStart, *sliceEnd;
@property (nonatomic, assign) NSInteger sliceStep;
// Union: NSNumbers for elements, NSStrings for members.
@property (nonatomic, copy) NSArray *members;
@property (nonatomic, strong) RDLJSONFilter *filter;
@end

@interface RDLJSONPath : NSObject
// nil, with `error` set, when the path does not parse.
+ (instancetype)pathWithString:(NSString *)path error:(NSError **)error;
@property (nonatomic, readonly, copy) NSArray<RDLJSONPathStep *> *steps;
// The path as it was written, rebuilt from the steps.
@property (nonatomic, readonly, copy) NSString *source;
// Every value the path selects. An empty array when it selects nothing, which
// is not an error: a document may legitimately not have what was asked for.
- (NSArray *)selectFrom:(id)root;
@end
