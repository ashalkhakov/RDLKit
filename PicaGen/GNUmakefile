include $(GNUSTEP_MAKEFILES)/common.make

# tool.make, so TOOL_NAME -- this read APP_NAME until the rename, which
# application.make would have wanted and tool.make ignores.
TOOL_NAME = picagen
picagen_OBJCFLAGS += -fobjc-arc -I../PicaKit
picagen_OBJC_FILES = main.m
# PicaKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
picagen_TOOL_LIBS += -lPicaKit -ldispatch
picagen_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/tool.make
