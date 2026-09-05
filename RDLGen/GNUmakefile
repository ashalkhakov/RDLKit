include $(GNUSTEP_MAKEFILES)/common.make

# tool.make, so TOOL_NAME -- this read APP_NAME until the rename, which
# application.make would have wanted and tool.make ignores.
TOOL_NAME = rdlgen
rdlgen_OBJCFLAGS += -fobjc-arc -I../RDLKit
rdlgen_OBJC_FILES = main.m
# RDLKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
rdlgen_TOOL_LIBS += -lRDLKit -ldispatch
rdlgen_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/tool.make
