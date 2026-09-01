#import "PicaTestMacros.h"
#import "PicaChecks.h"

@interface PicaParserTests : PICA_TEST_CASE
@end
@implementation PicaParserTests
- (void)testWriterAndParserRoundTrip {
  PICA_ASSERT_NO_FAILURES(PicaRunParserChecks());
}
@end

@interface PicaExpressionTests : PICA_TEST_CASE
@end
@implementation PicaExpressionTests
- (void)testFieldsParametersGlobalsSumCountFormat {
  PICA_ASSERT_NO_FAILURES(PicaRunExpressionChecks());
}
- (void)testExpressionTranslationAndLanguage {
  PICA_ASSERT_NO_FAILURES(PicaRunExpressionLangChecks());
}
@end

@interface PicaLayoutTests : PICA_TEST_CASE
@end
@implementation PicaLayoutTests
- (void)testPagesTablixAndJSONBind {
  PICA_ASSERT_NO_FAILURES(PicaRunLayoutChecks());
}
- (void)testTablixHierarchyPagination {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixChecks());
}
- (void)testTablixGroupsFiltersNoRows {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixGroupChecks());
}

- (void)testTablixEditing {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixEditingChecks());
}
- (void)testTablixAdvanced {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixAdvancedChecks());
}
@end

@interface PicaBackendTests : PICA_TEST_CASE
@end
@implementation PicaBackendTests
- (void)testBackendRegistry {
  PICA_ASSERT_NO_FAILURES(PicaRunBackendRegistryChecks());
}
- (void)testHTMLBackend {
  PICA_ASSERT_NO_FAILURES(PicaRunHTMLBackendChecks());
}
- (void)testRDLSubsetFeatures {
  PICA_ASSERT_NO_FAILURES(PicaRunRDLSubsetChecks());
}
- (void)testRDLSubset2Features {
  PICA_ASSERT_NO_FAILURES(PicaRunRDLSubset2Checks());
}
- (void)testPDFBackend {
  PICA_ASSERT_NO_FAILURES(PicaRunPDFBackendChecks());
}
- (void)testAllBasicFeatures {
  PICA_ASSERT_NO_FAILURES(PicaRunAllChecks());
}
@end
