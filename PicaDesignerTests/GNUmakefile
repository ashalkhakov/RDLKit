# An XCTest bundle for the designer, the standard GNUstep way. Requires
# tools-xctest (https://github.com/gnustep/tools-xctest).
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = PicaDesignerTests

# The app's plain objects are compiled in directly: the test target holds the
# editing logic, not the window shell, which is why PicaAppDelegate and the
# window controllers are absent.
PicaDesignerTests_OBJC_FILES = \
  PicaDesignerTests.m \
  ../PicaDesigner/PicaChange.m \
  ../PicaDesigner/PicaDocument.m \
  ../PicaDesigner/PicaEditingContext.m \
  ../PicaDesigner/PicaEditor.m \
  ../PicaDesigner/PicaExpressionHelper.m \
  ../PicaDesigner/PicaInspectorFields.m \
  ../PicaDesigner/PicaItemFactory.m \
  ../PicaDesigner/PicaNewReport.m \
  ../PicaDesigner/PicaNewReportPanel.m \
  ../PicaDesigner/PicaPageGeometry.m \
  ../PicaDesigner/PicaRichTextCodec.m \
  ../PicaDesigner/PicaRichTextFormatter.m \
  ../PicaDesigner/PicaSamples.m \
  ../PicaDesigner/PicaSelection.m \
  ../PicaDesigner/PicaTablixEditor.m
PicaDesignerTests_OBJCFLAGS += -fobjc-arc -Wall
PicaDesignerTests_INCLUDE_DIRS = -I../PicaKit -I../PicaDesigner
ADDITIONAL_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
PicaDesignerTests_BUNDLE_LIBS += -lPicaKit -lXCTest -ldispatch
PicaDesignerTests_NEEDS_GUI = yes

# The two modal panels the checks open are looked up with -bundleForClass:,
# which resolves to this bundle rather than to Pica.app.
PicaDesignerTests_RESOURCE_FILES = \
  ../PicaDesigner/PicaTablixEditor.xib \
  ../PicaDesigner/PicaNewReportPanel.xib

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
	LD_LIBRARY_PATH="$(CURDIR)/../PicaKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
