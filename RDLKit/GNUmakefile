include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = RDLKit
RDLKit_NEEDS_GUI = yes
RDLKit_LIBRARIES_DEPEND_UPON += -lz -ldispatch
RDLKit_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
# MiniVB, the subset of Visual Basic that RDL expressions and a report's Code
# need -- not a Visual Basic -- with the runtime library both call, is a
# directory of its own.
RDLKit_INCLUDE_DIRS += -IMiniVB
RDLKit_HEADER_FILES = \
  RDLKit.h \
  RDLCompatibility.h \
  RDLReport.h \
  RDLReferenceSites.h \
  RDLParser.h \
  RDLLayoutEngine.h \
  RDLView.h \
  RDLBackend.h \
  RDLGenerator.h \
  RDLJSONPath.h \
  RDLDataProvider.h \
  RDLJSONDataProvider.h \
  RDLXMLDataProvider.h \
  RDLCSVDataProvider.h \
  RDLSubreportLoader.h \
  RDLTextAttributes.h \
  RDLBorderPainter.h \
  RDLLinePainter.h \
  RDLParameterValues.h \
  RDLDataEvaluation.h
RDLKit_OBJC_FILES = \
  RDLReport.m \
  RDLParser.m \
  RDLUpgrader.m \
  RDLUpgraderSupport.m \
  RDLMigration2003.m \
  RDLMigration2005.m \
  RDLMigration2008.m \
  RDLMigration2010.m \
  RDLUpgraderRepairs.m \
  RDLChartRenderer.m \
  RDLChecker.m \
  RDLZipArchive.m \
  RDLDocxReader.m \
  RDLImporter.m \
  MiniVB/RDLExpression.m \
  MiniVB/RDLExpressionCatalog.m \
  RDLLayoutEngine.m \
  RDLView.m \
  RDLHTMLBackend.m \
  RDLPDFBackend.m \
  RDLGenerator.m \
  RDLJSONPath.m \
  RDLDataProvider.m \
  RDLJSONDataProvider.m \
  RDLXMLDataProvider.m \
  RDLCSVDataProvider.m \
  RDLSubreportLoader.m \
  RDLTextAttributes.m \
  MiniVB/RDLValueBoxing.m \
  MiniVB/RDLConversions.m \
  MiniVB/RDLReferences.m \
  MiniVB/RDLAggregates.m \
  MiniVB/RDLDateFormats.m \
  MiniVB/RDLVisualBasicText.m \
  MiniVB/RDLVisualBasicDates.m \
  MiniVB/RDLFunctionTable.m \
  MiniVB/RDLDotNetMembers.m \
  MiniVB/RDLForms.m \
  RDLReferenceSites.m \
  MiniVB/RDLCompiler.m \
  MiniVB/RDLVirtualMachine.m \
  RDLBorderPainter.m \
  RDLLinePainter.m \
  RDLMarkup.m \
  MiniVB/RDLCode.m \
  MiniVB/RDLCodeAST.m \
  MiniVB/RDLCodeParser.m \
  MiniVB/RDLExpressionParser.m \
  RDLParameterValues.m \
  MiniVB/RDLNumber.m \
  RDLDataEvaluation.m

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

# Undefined behaviour, which is a different question from memory safety and a
# different tool: UBSAN=1 checks signed overflow, shifts, misaligned and null
# pointers, out-of-range enum and bool loads, and float-to-integer conversions
# that do not fit. None of it touches the allocator, so unlike the sanitizers
# above it does not change the shape of the heap it is run against.
#
#   make -C RDLKit UBSAN=1 && make -C RDLKitTests run-tests UBSAN=1
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
endif

include $(GNUSTEP_MAKEFILES)/library.make

# The language's public headers, installed beside the rest rather than in a
# MiniVB directory: RDLKit.h imports them by name, as the Xcode
# framework, which flattens its headers, has them.
MINIVB_PUBLIC_HEADERS = RDLExpression.h RDLExpressionCatalog.h RDLNumber.h RDLValueBoxing.h

after-install::
	$(ECHO_NOTHING)for file in $(MINIVB_PUBLIC_HEADERS); do \
	  $(INSTALL_DATA) MiniVB/$$file $(GNUSTEP_HEADERS)/RDLKit/$$file; \
	done$(END_ECHO)

after-uninstall::
	$(ECHO_NOTHING)for file in $(MINIVB_PUBLIC_HEADERS); do \
	  rm -f $(GNUSTEP_HEADERS)/RDLKit/$$file; \
	done$(END_ECHO)
