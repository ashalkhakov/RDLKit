# The designer's UI tests: a bundle RDLDesigner loads at launch, and runs in
# itself. Requires tools-xctest (https://github.com/gnustep/tools-xctest).
#
#   make            build the bundle
#   make run-tests  build it and the app, and run the app with it, under a
#                   display (xvfb-run -a when there is none)
#
# RDL_UI_TESTS=Class[.method][,...] picks some; RDL_UI_ARTIFACTS is where the
# screenshots go (obj/artifacts by default).
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLDesignerUITests
# Built and run, never installed.
RDLDesignerUITests_STANDARD_INSTALL = no
# What gnustep-gui instantiates once it has loaded the bundle into the app.
RDLDesignerUITests_PRINCIPAL_CLASS = RDLUIHost

RDLDesignerUITests_OBJC_FILES = \
  RDLUIHost.m \
  RDLUIDriver.m \
  RDLUITestCase.m \
  RDLUIDocumentTests.m \
  RDLUICanvasTests.m \
  RDLUITablixTests.m \
  RDLUIDataTests.m \
  RDLUIWindowTests.m
RDLDesignerUITests_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
RDLDesignerUITests_INCLUDE_DIRS = -I../RDLKit -I../RDLKit/MiniVB -I../RDLDesigner \
                                  -I../RDLDesigner/ThirdParty/DMTabBar
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLDesignerUITests_BUNDLE_LIBS += -lRDLKit -lXCTest -ldispatch
RDLDesignerUITests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a -s \"-screen 0 1600x1200x24\"))
RDL_UI_ARTIFACTS ?= $(CURDIR)/$(GNUSTEP_OBJ_DIR)/artifacts
TEST_TIMEOUT ?= 900

.PHONY: run-tests
# The app's own defaults are kept apart from the person's: a home of its own.
run-tests: all
	$(MAKE) -C ../RDLDesigner
	rm -rf "$(RDL_UI_ARTIFACTS)" "$(CURDIR)/$(GNUSTEP_OBJ_DIR)/home"
	mkdir -p "$(RDL_UI_ARTIFACTS)" "$(CURDIR)/$(GNUSTEP_OBJ_DIR)/home"
	HOME="$(CURDIR)/$(GNUSTEP_OBJ_DIR)/home" \
	RDL_UI_ARTIFACTS="$(RDL_UI_ARTIFACTS)" \
	LD_LIBRARY_PATH="$(CURDIR)/../RDLKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XVFB) ../RDLDesigner/RDLDesigner.app/RDLDesigner \
	    -GSAppKitUserBundles '("$(CURDIR)/$(BUNDLE_NAME).bundle")'
