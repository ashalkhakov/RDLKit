#import "PicaTestMacros.h"
#import "PicaDesignerChecks.h"

// One case per area, plus an aggregate, mirroring PicaKitTests.

@interface PicaEditingCoreTests : PICA_TEST_CASE
@end
@implementation PicaEditingCoreTests
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
- (void)testEditingContext {
  PICA_ASSERT_NO_FAILURES(PicaRunEditingContextChecks());
}
@end

@interface PicaCanvasTests : PICA_TEST_CASE
@end
@implementation PicaCanvasTests
- (void)testPageGeometry {
  PICA_ASSERT_NO_FAILURES(PicaRunPageGeometryChecks());
}
- (void)testTablixGeometry {
  PICA_ASSERT_NO_FAILURES(PicaRunTablixGeometryChecks());
}
@end

@interface PicaUITests : PICA_TEST_CASE
@end
@implementation PicaUITests
- (void)testInspectorFieldBindings {
  PICA_ASSERT_NO_FAILURES(PicaRunFieldBindingChecks());
}
- (void)testRichTextCodec {
  PICA_ASSERT_NO_FAILURES(PicaRunRichTextCodecChecks());
}
- (void)testExpressionCompletion {
  PICA_ASSERT_NO_FAILURES(PicaRunCompletionChecks());
}
- (void)testTextInput {
  PICA_ASSERT_NO_FAILURES(PicaRunTextInputChecks());
}
- (void)testModalSession {
  PICA_ASSERT_NO_FAILURES(PicaRunModalSessionChecks());
}
- (void)testAllDesignerChecks {
  PICA_ASSERT_NO_FAILURES(PicaRunAllDesignerChecks());
}
@end
