include $(GNUSTEP_MAKEFILES)/common.make

# tool.make, so TOOL_NAME -- this read APP_NAME until the rename, which
# application.make would have wanted and tool.make ignores.
TOOL_NAME = picagen
picagen_OBJCFLAGS += -fobjc-arc -I../PicaKit
picagen_OBJC_FILES = main.m
picagen_TOOL_LIBS += -lPicaKit
picagen_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/tool.make
