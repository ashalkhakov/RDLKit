/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import "RDLKit.h"

// JSONPath, checked against the document every implementation is compared on --
// Goessner's store, the one the original article uses and the one the
// cross-implementation comparisons all quote. The queries below are that
// article's, plus the cases where implementations are known to disagree, so
// "ours behaves like the others" is a thing this file actually establishes
// rather than a hope.
//
// Order: selections through arrays keep the document's order and are compared
// as lists; selections that cross object members cannot, because an
// NSDictionary has no member order, and are compared as sets.
@interface RDLJSONPathTests : XCTestCase
@end

@implementation RDLJSONPathTests

- (id)store {
  NSString *json = @"{\"store\":{"
                    "\"book\":["
                    "{\"category\":\"reference\",\"author\":\"Nigel Rees\","
                    "\"title\":\"Sayings of the Century\",\"price\":8.95},"
                    "{\"category\":\"fiction\",\"author\":\"Evelyn Waugh\","
                    "\"title\":\"Sword of Honour\",\"price\":12.99},"
                    "{\"category\":\"fiction\",\"author\":\"Herman Melville\","
                    "\"title\":\"Moby Dick\",\"isbn\":\"0-553-21311-3\",\"price\":8.99},"
                    "{\"category\":\"fiction\",\"author\":\"J. R. R. Tolkien\","
                    "\"title\":\"The Lord of the Rings\",\"isbn\":\"0-395-19395-8\","
                    "\"price\":22.99}"
                    "],"
                    "\"bicycle\":{\"color\":\"red\",\"price\":19.95}"
                    "},\"expensive\":10}";
  return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                         options:0
                                           error:NULL];
}

// What a path selects, or nil when it does not parse -- which is itself a
// result worth asserting.
- (NSArray *)select:(NSString *)path {
  NSError *err = nil;
  RDLJSONPath *parsed = [RDLJSONPath pathWithString:path error:&err];
  if (parsed == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"'%@' did not parse: %@", path,
                                              [err localizedDescription]]);
    return nil;
  }
  return [parsed selectFrom:[self store]];
}

- (void)expect:(NSString *)path isList:(NSArray *)wanted {
  NSArray *got = [self select:path];
  if (got != nil && ![got isEqualToArray:wanted])
    XCTFail(@"%@", [NSString stringWithFormat:@"%@ selected %@, wanted %@", path, got, wanted]);
}

- (void)expect:(NSString *)path isSet:(NSArray *)wanted {
  NSArray *got = [self select:path];
  if (got == nil)
    return;
  if (![[NSCountedSet setWithArray:got] isEqual:[NSCountedSet setWithArray:wanted]])
    XCTFail(@"%@", [NSString stringWithFormat:@"%@ selected %@, wanted %@ in some order", path,
                                              got, wanted]);
}

- (void)expect:(NSString *)path count:(NSUInteger)wanted {
  NSArray *got = [self select:path];
  if (got != nil && [got count] != wanted)
    XCTFail(@"%@", [NSString stringWithFormat:@"%@ selected %lu, wanted %lu: %@", path,
                                              (unsigned long)[got count], (unsigned long)wanted,
                                              got]);
}

- (void)expectRefused:(NSString *)path because:(NSString *)why {
  NSError *err = nil;
  if ([RDLJSONPath pathWithString:path error:&err] != nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"'%@' should be refused: %@", path, why]);
  else if ([[err localizedDescription] length] == 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"'%@' was refused without saying why", path]);
}

#pragma mark - The article's own queries

- (void)testTheQueriesFromTheJSONPathArticle {
  NSArray *authors = @[ @"Nigel Rees", @"Evelyn Waugh", @"Herman Melville", @"J. R. R. Tolkien" ];

  [self expect:@"$.store.book[*].author" isList:authors];
  [self expect:@"$..author" isSet:authors];
  // The store's two members, whatever order the dictionary hands them back in.
  [self expect:@"$.store.*" count:2];
  [self expect:@"$.store..price"
         isSet:@[ @8.95, @12.99, @8.99, @22.99, @19.95 ]];
  [self expect:@"$..book[2].title" isList:@[ @"Moby Dick" ]];
  [self expect:@"$..book[-1].title" isList:@[ @"The Lord of the Rings" ]];
  [self expect:@"$..book[0,1].title" isList:@[ @"Sayings of the Century", @"Sword of Honour" ]];
  [self expect:@"$..book[:2].title" isList:@[ @"Sayings of the Century", @"Sword of Honour" ]];
  [self expect:@"$..book[?(@.isbn)].title" isList:@[ @"Moby Dick", @"The Lord of the Rings" ]];
  [self expect:@"$..book[?(@.price<10)].title"
        isList:@[ @"Sayings of the Century", @"Moby Dick" ]];
  // Every value in the document, which is the one query that exercises the
  // whole walk: store and expensive, the book array and the bicycle, the four
  // books, and each book's own members -- 28 in all.
  [self expect:@"$..*" count:28];
}

#pragma mark - The forms a path can take

- (void)testTheWaysAStepCanBeWritten {
  // Dotted and bracketed are the same path.
  [self expect:@"$.store.bicycle.color" isList:@[ @"red" ]];
  [self expect:@"$['store']['bicycle']['color']" isList:@[ @"red" ]];
  [self expect:@"$.store['bicycle'].color" isList:@[ @"red" ]];
  // A leading $ is optional, the way a report writes one.
  [self expect:@"store.bicycle.color" isList:@[ @"red" ]];
  [self expect:@"['store']['bicycle']['color']" isList:@[ @"red" ]];
  // Whitespace around the whole thing is not part of it.
  [self expect:@"  $.store.bicycle.color  " isList:@[ @"red" ]];

  // A name that could not be written with a dot.
  NSDictionary *odd = @{@"a.b" : @1, @"x y" : @2, @"" : @3};
  RDLJSONPath *dotted = [RDLJSONPath pathWithString:@"$['a.b']" error:NULL];
  if (![[dotted selectFrom:odd] isEqualToArray:@[ @1 ]])
    XCTFail(@"%@", @"a quoted name keeps its dots");
  RDLJSONPath *spaced = [RDLJSONPath pathWithString:@"$[\"x y\"]" error:NULL];
  if (![[spaced selectFrom:odd] isEqualToArray:@[ @2 ]])
    XCTFail(@"%@", @"double quotes name a member too");

  // Absent things select nothing, which is not an error.
  [self expect:@"$.store.book[99]" count:0];
  [self expect:@"$.nothing.here" count:0];
  [self expect:@"$.store.book[*].nothing" count:0];
}

- (void)testIndexesAndSlices {
  NSArray *(^titles)(NSString *) = ^NSArray *(NSString *path) {
    return [self select:path];
  };
  NSArray *all = @[ @"Sayings of the Century", @"Sword of Honour", @"Moby Dick",
                    @"The Lord of the Rings" ];

  [self expect:@"$.store.book[0].title" isList:@[ all[0] ]];
  [self expect:@"$.store.book[-1].title" isList:@[ all[3] ]];
  [self expect:@"$.store.book[-2].title" isList:@[ all[2] ]];
  [self expect:@"$.store.book[1:3].title" isList:@[ all[1], all[2] ]];
  [self expect:@"$.store.book[:2].title" isList:@[ all[0], all[1] ]];
  [self expect:@"$.store.book[2:].title" isList:@[ all[2], all[3] ]];
  [self expect:@"$.store.book[-2:].title" isList:@[ all[2], all[3] ]];
  [self expect:@"$.store.book[:-2].title" isList:@[ all[0], all[1] ]];
  [self expect:@"$.store.book[::2].title" isList:@[ all[0], all[2] ]];
  [self expect:@"$.store.book[::-1].title" isList:@[ all[3], all[2], all[1], all[0] ]];
  [self expect:@"$.store.book[1:1].title" count:0];
  [self expect:@"$.store.book[3:1].title" count:0];
  // Out of range is clamped rather than refused, which is what the others do.
  [self expect:@"$.store.book[0:99].title" isList:all];
  [self expect:@"$.store.book[-99:2].title" isList:@[ all[0], all[1] ]];
  if ([titles(@"$.store.book[*]") count] != 4)
    XCTFail(@"%@", @"[*] over an array is its elements");

  // A union may name members as well as elements.
  [self expect:@"$.store.bicycle['color','price']" isSet:@[ @"red", @19.95 ]];
  [self expect:@"$.store.book[0,-1].title" isList:@[ all[0], all[3] ]];
}

- (void)testDescent {
  // ..name finds a member at any depth, including the shallow one.
  [self expect:@"$..color" isList:@[ @"red" ]];
  [self expect:@"$..bicycle.color" isList:@[ @"red" ]];
  [self expect:@"$..book[?(@.category=='reference')].author" isList:@[ @"Nigel Rees" ]];
  // ..name into an array descends through its elements.
  [self expect:@"$..title" count:4];
  // Descent that finds nothing is empty, not an error.
  [self expect:@"$..nothing" count:0];
  // A descent step and an index compose.
  [self expect:@"$..book[1].author" isList:@[ @"Evelyn Waugh" ]];
}

#pragma mark - Filters

- (void)testFilters {
  NSArray *cheap = @[ @"Sayings of the Century", @"Moby Dick" ];

  [self expect:@"$..book[?(@.price < 10)].title" isList:cheap];
  [self expect:@"$..book[?(@.price <= 8.99)].title" isList:cheap];
  [self expect:@"$..book[?(@.price > 20)].title" isList:@[ @"The Lord of the Rings" ]];
  [self expect:@"$..book[?(@.price >= 22.99)].title" isList:@[ @"The Lord of the Rings" ]];
  [self expect:@"$..book[?(@.category == 'reference')].title"
        isList:@[ @"Sayings of the Century" ]];
  [self expect:@"$..book[?(@.category != 'fiction')].title"
        isList:@[ @"Sayings of the Century" ]];
  [self expect:@"$..book[?(@.category == \"reference\")].title"
        isList:@[ @"Sayings of the Century" ]];
  // Existence, and its negation.
  [self expect:@"$..book[?(@.isbn)].title" isList:@[ @"Moby Dick", @"The Lord of the Rings" ]];
  [self expect:@"$..book[?(!@.isbn)].title"
        isList:@[ @"Sayings of the Century", @"Sword of Honour" ]];
  // And, or, and parentheses.
  [self expect:@"$..book[?(@.price < 10 && @.category == 'fiction')].title"
        isList:@[ @"Moby Dick" ]];
  [self expect:@"$..book[?(@.price > 20 || @.category == 'reference')].title"
        isList:@[ @"Sayings of the Century", @"The Lord of the Rings" ]];
  [self expect:@"$..book[?((@.price < 10 || @.price > 20) && @.isbn)].title"
        isList:@[ @"Moby Dick", @"The Lord of the Rings" ]];
  // A bracketed member name inside a filter.
  [self expect:@"$..book[?(@['category'] == 'reference')].title"
        isList:@[ @"Sayings of the Century" ]];
  // A filter over an object's members rather than an array's elements.
  [self expect:@"$.store[?(@.color == 'red')].price" isList:@[ @19.95 ]];
  // A type mismatch is false rather than a coincidence: '10' is not 10.
  [self expect:@"$..book[?(@.price == '8.95')]" count:0];
  // Comparing something that is not there is false, except for !=.
  [self expect:@"$..book[?(@.nothing > 1)]" count:0];
  [self expect:@"$..book[?(@.nothing != 1)]" count:4];

  // The filter tree is a tree, not a string: the parts are inspectable, which
  // is what lets a caller explain one.
  NSError *err = nil;
  RDLJSONPath *path = [RDLJSONPath pathWithString:@"$..book[?(@.price < 10)]" error:&err];
  RDLJSONPathStep *step = [path.steps lastObject];
  if (step.kind != RDLJSONPathStepKindFilter || step.filter.kind != RDLJSONFilterKindCompare ||
      step.filter.op != RDLJSONFilterOperatorLess ||
      ![step.filter.path isEqualToArray:@[ @"price" ]] ||
      ![step.filter.literal isEqual:@10])
    XCTFail(@"%@", @"a filter should parse into its parts");
}

#pragma mark - What is refused

- (void)testMalformedAndUnsupportedPathsAreReported {
  // A report still renders when a path selects the wrong nodes, so silence is
  // the failure worth avoiding: everything here says what is wrong.
  [self expectRefused:@"" because:@"an empty string is not a path"];
  [self expectRefused:@"$.a[" because:@"the bracket is not closed"];
  [self expectRefused:@"$.a." because:@"the step is empty"];
  [self expectRefused:@"$.a[]" because:@"[] selects nothing"];
  [self expectRefused:@"$.a[b]" because:@"a bare word is not an index or a quoted name"];
  [self expectRefused:@"$.a[1:2:0]" because:@"a slice cannot step by zero"];
  [self expectRefused:@"$.a[1:2:3:4]" because:@"a slice has three parts at most"];
  [self expectRefused:@"$.a[?(@.b" because:@"the filter is not closed"];
  [self expectRefused:@"$.a[?(b == 1)]" because:@"a filter tests @"];
  [self expectRefused:@"$.a[?(@.b == )]" because:@"the comparison has no right side"];
  [self expectRefused:@"$.a[?(@.b == 'x)]" because:@"the quote is not closed"];
  [self expectRefused:@"$.a[?(@.b == x)]" because:@"a bare word is not a literal"];
  [self expectRefused:@"$.a[(@.length-1)]" because:@"script expressions are not supported"];
  [self expectRefused:@"$a" because:@"a name must follow a dot or sit in brackets"];
}

@end
