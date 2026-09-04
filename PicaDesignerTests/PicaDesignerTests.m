#import <XCTest/XCTest.h>
#import "PicaDesignerChecks.h"

// One case per area, plus an aggregate, mirroring PicaKitTests.

@interface PicaEditingCoreTests : XCTestCase
@end
@implementation PicaEditingCoreTests
- (void)testDocument {
  NSArray<NSString *> *fails = PicaRunDocumentChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testGranularUndo {
  NSArray<NSString *> *fails = PicaRunUndoChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testEditorTablixOps {
  NSArray<NSString *> *fails = PicaRunEditorTablixChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testSelection {
  NSArray<NSString *> *fails = PicaRunSelectionChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testInsertionPolicy {
  NSArray<NSString *> *fails = PicaRunInsertionChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testItemTransfer {
  NSArray<NSString *> *fails = PicaRunItemTransferChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testEditingContext {
  NSArray<NSString *> *fails = PicaRunEditingContextChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testExport {
  NSArray<NSString *> *fails = PicaRunExportChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testSharedPipeline {
  NSArray<NSString *> *fails = PicaRunSharedPipelineChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end

@interface PicaCanvasTests : XCTestCase
@end
@implementation PicaCanvasTests
- (void)testPageGeometry {
  NSArray<NSString *> *fails = PicaRunPageGeometryChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTablixGeometry {
  NSArray<NSString *> *fails = PicaRunTablixGeometryChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end

@interface PicaUITests : XCTestCase
@end
@implementation PicaUITests
- (void)testInspectorFieldBindings {
  NSArray<NSString *> *fails = PicaRunFieldBindingChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testRichTextCodec {
  NSArray<NSString *> *fails = PicaRunRichTextCodecChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testExpressionCompletion {
  NSArray<NSString *> *fails = PicaRunCompletionChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testTextInput {
  NSArray<NSString *> *fails = PicaRunTextInputChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testDialogLifecycle {
  NSArray<NSString *> *fails = PicaRunDialogLifecycleChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testNewReportWizard {
  NSArray<NSString *> *fails = PicaRunNewReportChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testNewReportPanel {
  NSArray<NSString *> *fails = PicaRunNewReportPanelChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testMenuWiring {
  NSArray<NSString *> *fails = PicaRunMenuWiringChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testScaffoldedTablixEditor {
  NSArray<NSString *> *fails = PicaRunScaffoldedTablixEditorChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
- (void)testAllDesignerChecks {
  NSArray<NSString *> *fails = PicaRunAllDesignerChecks();
  XCTAssertTrue([fails count] == 0, @"%@",
                [fails componentsJoinedByString:@"\n"]);
}
@end
