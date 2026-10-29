# An XCTest bundle for the designer, the standard GNUstep way. Requires
# tools-xctest (https://github.com/gnustep/tools-xctest).
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLDesignerTests
# Built and run, never installed.
RDLDesignerTests_STANDARD_INSTALL = no

# RDLKitUI's objects and the app's are compiled in directly, so the checks can
# drive the same classes the app runs. Only main.m is left out -- its main() would collide
# with the test runner's -- so the window controllers and app delegate the
# window checks exercise are all present.
RDLDesignerTests_OBJC_FILES = \
  ../RDLDesigner/RDLUpdater.m \
  RDLEditingCoreTests.m \
  RDLCanvasTests.m \
  RDLDesignerTestSupport.m \
  RDLWindowTests.m \
  RDLPortabilityTests.m \
  RDLRoundTripTests.m \
  RDLInspectorTests.m \
  RDLExpressionUITests.m \
  RDLRichTextTests.m \
  RDLTablixUITests.m \
  RDLNewReportTests.m \
  ../RDLKitUI/RDLChange.m \
  ../RDLKitUI/RDLDocument.m \
  ../RDLKitUI/RDLEditingContext.m \
  ../RDLKitUI/RDLEditor.m \
  ../RDLKitUI/RDLTablixStructure.m \
  ../RDLKitUI/RDLExpressionHelper.m \
  ../RDLKitUI/RDLInspectorFields.m \
  ../RDLKitUI/RDLItemFactory.m \
  ../RDLDesigner/RDLNewReport.m \
  ../RDLDesigner/RDLNewReportPanel.m \
  ../RDLKitUI/RDLPageGeometry.m \
  ../RDLKitUI/RDLRichTextCodec.m \
  ../RDLKitUI/RDLPlainTextEdit.m \
  ../RDLKitUI/RDLRichTextFormatter.m \
  ../RDLKitUI/RDLSamples.m \
  ../RDLKitUI/RDLSelection.m \
  ../RDLKitUI/RDLRichTextEditor.m \
  ../RDLKitUI/RDLExpressionEditor.m \
  ../RDLKitUI/RDLInsertPalette.m \
  ../RDLKitUI/RDLExpressionCell.m \
  ../RDLKitUI/RDLExpressionField.m \
  ../RDLKitUI/RDLFilterEditor.m \
  ../RDLKitUI/RDLSortEditor.m \
  ../RDLKitUI/RDLValueListEditor.m \
  ../RDLKitUI/RDLEmbeddedImages.m \
  ../RDLKitUI/RDLEmbeddedImagesEditor.m \
  ../RDLKitUI/RDLDatasetOptionsEditor.m \
  ../RDLKitUI/RDLVariablesEditor.m \
  ../RDLKitUI/RDLCodeEditor.m \
  ../RDLKitUI/RDLStylePanel.m \
  ../RDLKitUI/RDLPreviewWindow.m \
  ../RDLKitUI/RDLGroupsView.m \
  ../RDLKitUI/RDLProblemsView.m \
  ../RDLKitUI/RDLSourceView.m \
  ../RDLKitUI/RDLSnapGuides.m \
  ../RDLKitUI/RDLChartAxisEditor.m \
  ../RDLKitUI/RDLChartSeriesEditor.m \
  ../RDLKitUI/RDLGroupPropertiesEditor.m \
  ../RDLKitUI/RDLToolbarIcons.m \
  ../RDLKitUI/RDLPane.m \
  ../RDLKitUI/RDLExpressionTheme.m \
  ../RDLKitUI/RDLExpressionTextStorage.m \
  ../RDLKitUI/RDLDatasetNavigator.m \
  ../RDLKitUI/RDLReportDesigner.m \
  ../RDLKitUI/RDLReportDesignerWindowController.m \
  ../RDLKitUI/RDLReportViewController.m \
  ../RDLKitUI/RDLReportViewerWindowController.m \
  ../RDLKitUI/RDLKitUIBundle.m \
  RDLEmbeddingTests.m \
  ../RDLKitUI/RDLCanvasView.m \
  ../RDLKitUI/RDLCanvasRenderer.m \
  ../RDLKitUI/RDLCanvasInteraction.m \
  ../RDLKitUI/RDLInPlaceEditor.m \
  ../RDLKitUI/RDLInspectorView.m \
  ../RDLKitUI/RDLDataView.m \
  ../RDLKitUI/RDLParameterPrompts.m \
  ../RDLKitUI/RDLRenderInputsEditor.m \
  ../RDLKitUI/RDLOutlineDataSource.m \
  ../RDLKitUI/RDLOutlineView.m \
  ../RDLKitUI/RDLTabBadge.m \
  ../RDLKitUI/ThirdParty/DMTabBar/DMTabBar.m \
  ../RDLKitUI/ThirdParty/DMTabBar/DMTabBarItem.m \
  ../RDLKitUI/RDLFieldInspectorView.m \
  ../RDLKitUI/RDLDatasetFieldsView.m \
  ../RDLDesigner/RDLGeneratorWindow.m \
  ../RDLKitUI/RDLParameterNavigator.m \
  ../RDLKitUI/RDLDataSourceNavigator.m \
  ../RDLKitUI/RDLDataSourceView.m \
  ../RDLKitUI/RDLParameterInspectorView.m \
  ../RDLKitUI/RDLBordersEditor.m \
  ../RDLKitUI/RDLSubreportParametersEditor.m \
  ../RDLDesigner/RDLAppDelegate.m \
  ../RDLDesigner/RDLWelcomeWindow.m
RDLDesignerTests_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
# ThirdParty/DMTabBar as well: the tests import "DMTabBar.h" by name, which
# Xcode resolves through its header map and gnustep-make has no equivalent for.
RDLDesignerTests_INCLUDE_DIRS = -I../RDLKit -I../RDLKit/MiniVB -I../RDLKitUI -I../RDLDesigner \
                                -I../RDLKitUI/ThirdParty/DMTabBar
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLDesignerTests_BUNDLE_LIBS += -lRDLKit -lXCTest -ldispatch
RDLDesignerTests_NEEDS_GUI = yes

# The panels the checks open are looked up with -bundleForClass:,
# which resolves to this bundle rather than to RDLDesigner.app.
RDLDesignerTests_RESOURCE_FILES = \
  ../RDLKitUI/RDLReportDesigner.xib \
  ../RDLKitUI/RDLReportDesignerWindow.xib \
  ../RDLKitUI/RDLReportViewController.xib \
  ../RDLKitUI/RDLReportViewerWindow.xib \
  ../RDLKitUI/RDLInspectorSections.xib \
  ../RDLKitUI/RDLFilterEditor.xib \
  ../RDLKitUI/RDLSortEditor.xib \
  ../RDLKitUI/RDLValueListEditor.xib \
  ../RDLKitUI/RDLEmbeddedImagesEditor.xib \
  ../RDLKitUI/RDLDatasetOptionsEditor.xib \
  ../RDLKitUI/RDLVariablesEditor.xib \
  ../RDLKitUI/RDLCodeEditor.xib \
  ../RDLKitUI/RDLStylePanel.xib \
  ../RDLKitUI/RDLPreviewWindow.xib \
  ../RDLKitUI/RDLGroupsView.xib \
  ../RDLKitUI/RDLProblemsView.xib \
  ../RDLKitUI/RDLSourceView.xib \
  ../RDLKitUI/RDLChartAxisEditor.xib \
  ../RDLKitUI/RDLChartSeriesEditor.xib \
  ../RDLKitUI/RDLGroupPropertiesEditor.xib \
  ../RDLKitUI/RDLBordersEditor.xib \
  ../RDLKitUI/RDLDatasetNavigator.xib \
  ../RDLKitUI/RDLInsertPalette.xib \
  ../RDLKitUI/RDLDatasetFieldsView.xib \
  ../RDLKitUI/RDLFieldInspectorView.xib \
  ../RDLKitUI/RDLExpressionEditor.xib \
  ../RDLKitUI/RDLRichTextEditor.xib \
  ../RDLDesigner/RDLNewReportPanel.xib \
  ../RDLKitUI/RDLDataSourceNavigator.xib \
  ../RDLKitUI/RDLParameterNavigator.xib \
  ../RDLKitUI/RDLParameterInspectorView.xib \
  ../RDLKitUI/RDLDataSourceView.xib \
  ../RDLKitUI/RDLSubreportParametersEditor.xib \
  ../RDLKitUI/RDLRenderInputsEditor.xib \
  ../RDLDesigner/RDLGeneratorWindow.xib \
  ../RDLDesigner/RDLWelcomeWindow.xib \
  ../RDLKitUI/RDLAddElementPanel.xib \
  ../RDLDesigner/MainMenu.xib \
  ../RDLDesigner/Samples

# Heap corruption does not name itself: "malloc_consolidate(): unaligned
# fastbin chunk" is reported by whichever allocation happens to notice, long
# after the overflow. Build with SANITIZE=1 to have AddressSanitizer name the
# write and the allocation it ran past instead:
#
#   make run-tests SANITIZE=1
#
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
# The bundle is dlopened by an xctest binary that is not instrumented, so the
# ASan runtime has to be loaded first or its interceptors are never installed.
# Named after the architecture, so this cannot be hardcoded: on anything but
# x86_64 the lookup returns the name it was given, LD_PRELOAD then fails
# quietly, and the run proceeds with no interceptors and no report.
ASAN_ARCH := $(shell uname -m)
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-$(ASAN_ARCH).so)
# Leaks are not what is being looked for here, and a test bundle reports plenty.
# handle_abort=1 so the SIGABRT the timeout below sends is reported by ASan
# with a symbolized backtrace, instead of the process simply disappearing.
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
endif

# Undefined behaviour, which is a different question from memory safety and a
# different tool: UBSAN=1 checks signed overflow, shifts, misaligned and null
# pointers, out-of-range enum and bool loads, and float-to-integer conversions
# that do not fit. None of it touches the allocator, so unlike the sanitizers
# above it does not change the shape of the heap it is run against.
#
#   make -C RDLKit UBSAN=1 && make -C RDLKitTests run-tests UBSAN=1
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
# As with AddressSanitizer: the bundle is dlopened by an xctest binary that is
# not instrumented, so the runtime has to be loaded first. halt_on_error=0 so
# one run reports everything it finds rather than the first thing only.
UBSAN_ARCH := $(shell uname -m)
UBSAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.ubsan_standalone-$(UBSAN_ARCH).so)
SANITIZE_ENV := LD_PRELOAD="$(UBSAN_LIB)" UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

.PHONY: run-tests
# Bounded. A test that opens a modal panel can wait for an event that never
# arrives on a machine with no window manager, and an unbounded hang costs the
# whole job's timeout and says nothing about where it stopped. TEST_TIMEOUT
# seconds later the run is aborted, and with SANITIZE=1 that abort comes back
# as a backtrace naming the call that was waiting.
TEST_TIMEOUT ?= 600

run-tests: all
	$(SANITIZE_ENV) \
	LD_LIBRARY_PATH="$(CURDIR)/../RDLKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/../RDLKit/$(GNUSTEP_OBJ_DIR):$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
