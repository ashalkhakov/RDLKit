include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = RDLKit
RDLKit_NEEDS_GUI = yes
RDLKit_LIBRARIES_DEPEND_UPON += -lz -ldispatch
RDLKit_OBJCFLAGS += -fobjc-arc -Wall
RDLKit_HEADER_FILES = \
  RDLKit.h \
  RDLCompatibility.h \
  RDLReport.h \
  RDLParser.h \
  RDLExpression.h \
  RDLLayoutEngine.h \
  RDLView.h \
  RDLBackend.h \
  RDLGenerator.h \
  RDLTextAttributes.h
RDLKit_OBJC_FILES = \
  RDLReport.m \
  RDLParser.m \
  RDLUpgrader.m \
  RDLChartRenderer.m \
  RDLChecker.m \
  RDLZipArchive.m \
  RDLDocxReader.m \
  RDLImporter.m \
  RDLExpression.m \
  RDLExpressionCatalog.m \
  RDLLayoutEngine.m \
  RDLView.m \
  RDLHTMLBackend.m \
  RDLPDFBackend.m \
  RDLGenerator.m \
  RDLTextAttributes.m

# The app, instrumented. "corrupted double-linked list" is reported by whatever
# allocation happens to notice, long after the write that did the damage, so it
# never names the culprit. Built this way, AddressSanitizer names both the write
# and the allocation it ran past, at the moment it happens:
#
#   make -C RDLKit SANITIZE=1 && make -C RDLDesigner SANITIZE=1
#   ASAN_OPTIONS=detect_leaks=0 ./RDLDesigner/RDLDesigner.app/RDLDesigner
#
# Build the library the same way: an uninstrumented library is a hole in the
# report exactly where most of the work happens.
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/library.make
