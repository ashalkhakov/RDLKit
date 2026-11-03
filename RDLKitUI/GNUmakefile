# RDLKitUI on GNUstep: the report viewer and the report designer, as a library
# an application embeds (RDLReportViewController, RDLReportDesigner and their
# window controllers), over RDLKit. RDLDesigner is a thin application on it.
#
#   make            libRDLKitUI, against RDLKit in the tree
#   make install    the library, its public headers (RDLKitUI/RDLKitUI.h ...),
#                   and its XIBs, where -[NSBundle bundleForClass:] finds them:
#                   $(GNUSTEP_LIBRARY)/Libraries/RDLKitUI/Versions/0/Resources
#
# macOS: the RDLKitUI framework in RDLKit.xcodeproj (Makefile.apple).
include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = RDLKitUI
RDLKitUI_NEEDS_GUI = yes
RDLKitUI_INTERFACE_VERSION = 0
# The XIBs go in the library's resource bundle, installed where
# -[NSBundle bundleForClass:] looks for a library's (and built in the tree at
# RDLKitUI/Versions/0/Resources).
RDLKitUI_HAS_RESOURCE_BUNDLE = yes
RDLKitUI_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: RDLKITUI_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifeq ($(OS),Windows_NT)
RDLKitUI_CPPFLAGS += "-DRDLKITUI_EXPORT=__declspec(dllexport) extern"
endif
RDLKitUI_INCLUDE_DIRS += -I../RDLKit -I../RDLKit/MiniVB -IThirdParty/DMTabBar
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLKitUI_LIBRARIES_DEPEND_UPON += -lRDLKit -ldispatch $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS)

# What an application imports: <RDLKitUI/RDLKitUI.h>. The rest are the
# components' insides.
RDLKitUI_HEADER_FILES = \
  RDLKitUI.h \
  RDLReportDataSource.h \
  RDLReportViewController.h \
  RDLReportViewerWindowController.h \
  RDLReportDesigner.h \
  RDLReportDesignerWindowController.h

include files.make
RDLKitUI_OBJC_FILES = $(RDLKITUI_OBJC_FILES)
RDLKitUI_RESOURCE_FILES = $(RDLKITUI_RESOURCE_FILES)

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
endif

include $(GNUSTEP_MAKEFILES)/library.make
