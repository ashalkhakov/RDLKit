# An XCTest bundle for the designer, the standard GNUstep way. Requires
# tools-xctest (https://github.com/gnustep/tools-xctest).
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLDesignerTests

# The app's plain objects are compiled in directly: the test target holds the
# editing logic, not the window shell, which is why RDLAppDelegate and the
# window controllers are absent.
RDLDesignerTests_OBJC_FILES = \
  RDLEditingCoreTests.m \
  RDLCanvasTests.m \
  RDLDesignerTestSupport.m \
  RDLWindowTests.m \
  RDLInspectorTests.m \
  RDLExpressionUITests.m \
  RDLRichTextTests.m \
  RDLTablixUITests.m \
  RDLNewReportTests.m \
  ../RDLDesigner/RDLChange.m \
  ../RDLDesigner/RDLDocument.m \
  ../RDLDesigner/RDLEditingContext.m \
  ../RDLDesigner/RDLEditor.m \
  ../RDLDesigner/RDLExpressionHelper.m \
  ../RDLDesigner/RDLInspectorFields.m \
  ../RDLDesigner/RDLItemFactory.m \
  ../RDLDesigner/RDLNewReport.m \
  ../RDLDesigner/RDLNewReportPanel.m \
  ../RDLDesigner/RDLPageGeometry.m \
  ../RDLDesigner/RDLRichTextCodec.m \
  ../RDLDesigner/RDLRichTextFormatter.m \
  ../RDLDesigner/RDLSamples.m \
  ../RDLDesigner/RDLSelection.m \
  ../RDLDesigner/RDLRichTextEditor.m \
  ../RDLDesigner/RDLExpressionEditor.m \
  ../RDLDesigner/RDLInsertPalette.m \
  ../RDLDesigner/RDLExpressionCell.m \
  ../RDLDesigner/RDLExpressionField.m \
  ../RDLDesigner/RDLPane.m \
  ../RDLDesigner/RDLExpressionTheme.m \
  ../RDLDesigner/RDLExpressionTextStorage.m \
  ../RDLDesigner/RDLDatasetNavigator.m \
  ../RDLDesigner/RDLDesignerWindow.m \
  ../RDLDesigner/RDLCanvasView.m \
  ../RDLDesigner/RDLCanvasRenderer.m \
  ../RDLDesigner/RDLCanvasInteraction.m \
  ../RDLDesigner/RDLInPlaceEditor.m \
  ../RDLDesigner/RDLInspectorView.m \
  ../RDLDesigner/RDLDataView.m \
  ../RDLDesigner/RDLOutlineDataSource.m \
  ../RDLDesigner/RDLTabBadge.m \
  ../RDLDesigner/ThirdParty/DMTabBar/DMTabBar.m \
  ../RDLDesigner/ThirdParty/DMTabBar/DMTabBarItem.m \
  ../RDLDesigner/RDLFieldInspectorView.m \
  ../RDLDesigner/RDLDatasetFieldsView.m \
  ../RDLDesigner/RDLTablixEditor.m
RDLDesignerTests_OBJCFLAGS += -fobjc-arc -Wall
# ThirdParty/DMTabBar as well: the tests import "DMTabBar.h" by name, which
# Xcode resolves through its header map and gnustep-make has no equivalent for.
RDLDesignerTests_INCLUDE_DIRS = -I../RDLKit -I../RDLDesigner \
                                -I../RDLDesigner/ThirdParty/DMTabBar
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLDesignerTests_BUNDLE_LIBS += -lRDLKit -lXCTest -ldispatch
RDLDesignerTests_NEEDS_GUI = yes

# The panels the checks open are looked up with -bundleForClass:,
# which resolves to this bundle rather than to RDLDesigner.app.
RDLDesignerTests_RESOURCE_FILES = \
  ../RDLDesigner/RDLDesignerWindow.xib \
  ../RDLDesigner/RDLInspectorSections.xib \
  ../RDLDesigner/RDLDatasetNavigator.xib \
  ../RDLDesigner/RDLInsertPalette.xib \
  ../RDLDesigner/RDLDatasetFieldsView.xib \
  ../RDLDesigner/RDLFieldInspectorView.xib \
  ../RDLDesigner/RDLExpressionEditor.xib \
  ../RDLDesigner/RDLRichTextEditor.xib \
  ../RDLDesigner/RDLTablixEditor.xib \
  ../RDLDesigner/RDLNewReportPanel.xib

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
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-x86_64.so)
# Leaks are not what is being looked for here, and a test bundle reports plenty.
# handle_abort=1 so the SIGABRT the timeout below sends is reported by ASan
# with a symbolized backtrace, instead of the process simply disappearing.
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
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
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
