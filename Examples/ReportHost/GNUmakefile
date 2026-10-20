# ReportHost on GNUstep: the example host, against the libraries in the tree.
#
#   make                            build it
#   make self-test                  build it and run --self-test under a display
#
# An application elsewhere builds against the installed libraries instead:
# -lRDLKitUI -lRDLKit, with <RDLKit/RDLKit.h> and <RDLKitUI/RDLKitUI.h> on the
# GNUstep header path (Scripts/installcheck.sh does exactly that).
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = ReportHost
ReportHost_NEEDS_GUI = yes
ReportHost_OBJC_FILES = ReportHost.m
ReportHost_OBJCFLAGS += -fobjc-arc -Wall
# <RDLKit/RDLKit.h> and <RDLKitUI/RDLKitUI.h> from the tree: the repository's
# root holds both directories. RDLKit.h's MiniVB headers are beside it once
# installed, and in MiniVB/ here.
ReportHost_INCLUDE_DIRS += -I../.. -I../../RDLKit -I../../RDLKit/MiniVB
ADDITIONAL_LIB_DIRS += -L../../RDLKit/$(GNUSTEP_OBJ_DIR) -L../../RDLKitUI/$(GNUSTEP_OBJ_DIR)
ReportHost_TOOL_LIBS += -lRDLKitUI -lRDLKit -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))

# The XIBs come from the tree as well: RDLKitUI is not installed yet.
.PHONY: self-test
self-test: all
	LD_LIBRARY_PATH="$(CURDIR)/../../RDLKit/$(GNUSTEP_OBJ_DIR):$(CURDIR)/../../RDLKitUI/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	RDLKITUI_RESOURCES="$(CURDIR)/../../RDLKitUI" \
	  timeout -s ABRT 300 $(XVFB) ./$(GNUSTEP_OBJ_DIR)/ReportHost --self-test Stock.rdl
