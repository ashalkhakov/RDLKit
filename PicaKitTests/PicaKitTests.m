#import <XCTest/XCTest.h>
#import "PicaChecks.h"

@interface PicaParserTests : XCTestCase
@end
@implementation PicaParserTests
- (void)testWriterAndParserRoundTrip {
  NSArray<NSString *> *fails = PicaRunParserChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end

@interface PicaExpressionTests : XCTestCase
@end
@implementation PicaExpressionTests
- (void)testFieldsParametersGlobalsSumCountFormat {
  NSArray<NSString *> *fails = PicaRunExpressionChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testExpressionTranslationAndLanguage {
  NSArray<NSString *> *fails = PicaRunExpressionLangChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end

@interface PicaLayoutTests : XCTestCase
@end
@implementation PicaLayoutTests
- (void)testPagesTablixAndJSONBind {
  NSArray<NSString *> *fails = PicaRunLayoutChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTablixHierarchyPagination {
  NSArray<NSString *> *fails = PicaRunTablixChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTablixGroupsFiltersNoRows {
  NSArray<NSString *> *fails = PicaRunTablixGroupChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}

- (void)testTablixEditing {
  NSArray<NSString *> *fails = PicaRunTablixEditingChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testBandEnumeration {
  NSArray<NSString *> *fails = PicaRunBandEnumerationChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTablixExplicitRebuild {
  NSArray<NSString *> *fails = PicaRunTablixRebuildChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testRichTextSpans {
  NSArray<NSString *> *fails = PicaRunRichTextChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTablixAdvanced {
  NSArray<NSString *> *fails = PicaRunTablixAdvancedChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end

@interface PicaBackendTests : XCTestCase
@end
@implementation PicaBackendTests
- (void)testBackendRegistry {
  NSArray<NSString *> *fails = PicaRunBackendRegistryChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testHTMLBackend {
  NSArray<NSString *> *fails = PicaRunHTMLBackendChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testRDLSubsetFeatures {
  NSArray<NSString *> *fails = PicaRunRDLSubsetChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testRDLSubset2Features {
  NSArray<NSString *> *fails = PicaRunRDLSubset2Checks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testPDFBackend {
  NSArray<NSString *> *fails = PicaRunPDFBackendChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testAllBasicFeatures {
  NSArray<NSString *> *fails = PicaRunAllChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end
