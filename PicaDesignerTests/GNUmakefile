# An XCTest bundle for the designer, the standard GNUstep way. Requires
# tools-xctest (https://github.com/gnustep/tools-xctest).
#
#   make          build the bundle
#   make check    build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = PicaDesignerTests

# The app's plain objects are compiled in directly: the test target holds the
# editing logic, not the window shell, which is why PicaAppDelegate and the
# window controllers are absent.
PicaDesignerTests_OBJC_FILES = \
  PicaDesignerChecks.m \
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
PicaDesignerTests_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
PicaDesignerTests_BUNDLE_LIBS += -lPicaKit -lXCTest
PicaDesignerTests_NEEDS_GUI = yes

# The two modal panels the checks open are looked up with -bundleForClass:,
# which resolves to this bundle rather than to Pica.app.
PicaDesignerTests_RESOURCE_FILES = \
  ../PicaDesigner/PicaTablixEditor.xib \
  ../PicaDesigner/PicaNewReportPanel.xib

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

.PHONY: check
check: all
	LD_LIBRARY_PATH="$(CURDIR)/../PicaKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  $(XCTEST) $(BUNDLE_NAME).bundle
