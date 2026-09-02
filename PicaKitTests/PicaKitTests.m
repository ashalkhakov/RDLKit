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
- (void)testBandEnumeration {
  PICA_ASSERT_NO_FAILURES(PicaRunBandEnumerationChecks());
}
- (void)testTablixExplicitRebuild {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixRebuildChecks());
}
- (void)testRichTextSpans {
  PICA_ASSERT_NO_FAILURES(PicaRunRichTextChecks());
}
- (void)testTablixAdvanced {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixAdvancedChecks());
}
@end

@interface PicaEditorTests : PICA_TEST_CASE
@end
@implementation PicaEditorTests
- (void)testDocument {
  PICA_ASSERT_NO_FAILURES(PicaRunDocumentChecks());
}
- (void)testGranularUndo {
  PICA_ASSERT_NO_FAILURES(PicaRunUndoChecks());
}
- (void)testEditorTablixOps {
  PICA_ASSERT_NO_FAILURES(PicaRunEditorTablixChecks());
}
- (void)testSelection {
  PICA_ASSERT_NO_FAILURES(PicaRunSelectionChecks());
}
- (void)testInsertionPolicy {
  PICA_ASSERT_NO_FAILURES(PicaRunInsertionChecks());
}
- (void)testItemTransfer {
  PICA_ASSERT_NO_FAILURES(PicaRunItemTransferChecks());
}
- (void)testTextAttributes {
  PICA_ASSERT_NO_FAILURES(PicaRunTextAttributeChecks());
}
- (void)testRichTextCodec {
  PICA_ASSERT_NO_FAILURES(PicaRunRichTextCodecChecks());
}
- (void)testExpressionCompletion {
  PICA_ASSERT_NO_FAILURES(PicaRunCompletionChecks());
}
- (void)testEditingContext {
  PICA_ASSERT_NO_FAILURES(PicaRunEditingContextChecks());
}
- (void)testTextInput {
  PICA_ASSERT_NO_FAILURES(PicaRunTextInputChecks());
}
- (void)testPageGeometry {
  PICA_ASSERT_NO_FAILURES(PicaRunPageGeometryChecks());
}
- (void)testTablixGeometry {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixGeometryChecks());
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
