include $(GNUSTEP_MAKEFILES)/common.make

# UDCode's RDL extension (docs/UDCODE.md): RDL.bundle, RDLKitUI's designer in a
# UDCode tab. Built against UDCode's SDK (its udcodekit archive,
# .github/pins.env's UDCODEKIT_VERSION) installed on the same GNUstep stack as
# UDCode's; the top GNUmakefile builds it only where that SDK is.
# Scripts/udcx.sh packages it, its libraries inside it.
BUNDLE_NAME = RDL
BUNDLE_EXTENSION = .bundle
RDL_PRINCIPAL_CLASS = RDLExtension
RDL_NEEDS_GUI = yes
RDL_STANDARD_INSTALL = no
# RDLKitUI compiled in, its XIBs among the bundle's resources
# (RDLKitUIBundle() then answers this bundle): a library inside the bundle
# would need its DLL beside its resources, where Windows does not look for the
# bundle's DLL's libraries.
include ../RDLKitUI/files.make
RDL_OBJC_FILES = \
  RDLExtension.m \
  RDLEditorViewController.m \
  RDLTextDiff.m \
  $(addprefix ../RDLKitUI/,$(RDLKITUI_OBJC_FILES))
RDL_RESOURCE_FILES = \
  Resources/LanguageInfo.plist \
  RDLEditor.xib \
  RDLEditorMenus.xib \
  $(addprefix ../RDLKitUI/,$(RDLKITUI_RESOURCE_FILES))
RDL_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses
# Windows: RDLKitUI's C constants and functions are this bundle's own, not a
# DLL's to import (RDLKITUI_EXPORT).
ifeq ($(OS),Windows_NT)
RDL_CPPFLAGS += -DRDLKITUI_EXPORT=extern
endif
RDL_INCLUDE_DIRS = -I../RDLKitUI -I../RDLKitUI/ThirdParty/DMTabBar -I../RDLKit -I../RDLKit/MiniVB
RDL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
# Its own library, which the package puts beside its binary (RDLKit's): found
# from where the binary is. UDCode's own (UDCodeKit, GNUstep's) are the running
# UDCode's: on Linux left for it, as UDCode's own plug-ins leave them; a
# Windows DLL is linked against all it uses.
RDL_BUNDLE_LIBS += -lRDLKit -ldispatch
ifneq ($(OS),Windows_NT)
RDL_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
RDL_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/bundle.make
