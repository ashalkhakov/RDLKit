# The RDL extension's tests (an XCTest bundle; tools-xctest), against UDCode's
# SDK installed: the extension's sources and RDLKitUI's compiled in (their XIBs
# found in this bundle, as in RDL.bundle), UDCodeKit's document and text model
# linked.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLTests
RDLTests_STANDARD_INSTALL = no

include ../../RDLKitUI/files.make
RDLTests_OBJC_FILES = \
  RDLTests.m \
  ../RDLExtension.m \
  ../RDLEditorViewController.m \
  ../RDLTextDiff.m \
  $(addprefix ../../RDLKitUI/,$(RDLKITUI_OBJC_FILES))
RDLTests_RESOURCE_FILES = \
  ../RDLEditor.xib \
  ../RDLEditorMenus.xib \
  $(addprefix ../../RDLKitUI/,$(RDLKITUI_RESOURCE_FILES))
RDLTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
ifeq ($(OS),Windows_NT)
RDLTests_CPPFLAGS += -DRDLKITUI_EXPORT=extern
endif
RDLTests_INCLUDE_DIRS = -I.. -I../../RDLKitUI -I../../RDLKitUI/ThirdParty/DMTabBar -I../../RDLKit -I../../RDLKit/MiniVB
ADDITIONAL_LIB_DIRS += -L../../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLTests_BUNDLE_LIBS += -lRDLKit -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch
RDLTests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 600

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../../RDLKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/../../RDLKit/$(GNUSTEP_OBJ_DIR):$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
