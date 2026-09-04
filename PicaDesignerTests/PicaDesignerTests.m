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
- (void)testExport {
  PICA_ASSERT_NO_FAILURES(PicaRunExportChecks());
}
- (void)testSharedPipeline {
  PICA_ASSERT_NO_FAILURES(PicaRunSharedPipelineChecks());
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
- (void)testDialogLifecycle {
  PICA_ASSERT_NO_FAILURES(PicaRunDialogLifecycleChecks());
}
- (void)testNewReportWizard {
  PICA_ASSERT_NO_FAILURES(PicaRunNewReportChecks());
}
- (void)testNewReportPanel {
  PICA_ASSERT_NO_FAILURES(PicaRunNewReportPanelChecks());
}
- (void)testMenuWiring {
  PICA_ASSERT_NO_FAILURES(PicaRunMenuWiringChecks());
}
- (void)testScaffoldedTablixEditor {
  PICA_ASSERT_NO_FAILURES(PicaRunScaffoldedTablixEditorChecks());
}
- (void)testAllDesignerChecks {
  PICA_ASSERT_NO_FAILURES(PicaRunAllDesignerChecks());
}
@end
