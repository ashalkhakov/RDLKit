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
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../PicaKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  $(XCTEST) $(BUNDLE_NAME).bundle
