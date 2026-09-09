include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = RDLDesigner
RDLDesigner_NEEDS_GUI = yes
RDLDesigner_OBJCFLAGS += -fobjc-arc -Wall -I../RDLKit -Werror=logical-not-parentheses
RDLDesigner_OBJC_FILES = \
  main.m \
  RDLEditingContext.m \
  RDLChange.m \
  RDLSelection.m \
  RDLDocument.m \
  RDLEditor.m \
  RDLItemFactory.m \
  RDLPageGeometry.m \
  RDLRichTextCodec.m \
  RDLRichTextFormatter.m \
  RDLCanvasView.m \
  RDLCanvasRenderer.m \
  RDLInPlaceEditor.m \
  RDLCanvasInteraction.m \
  RDLDesignerWindow.m \
  RDLOutlineDataSource.m \
  RDLGeneratorWindow.m \
  RDLAppDelegate.m \
  RDLSamples.m \
  RDLInspectorView.m \
  RDLInspectorFields.m \
  RDLExpressionHelper.m \
  RDLTablixEditor.m \
  RDLNewReport.m \
  RDLNewReportPanel.m \
  RDLRichTextEditor.m \
  RDLDataView.m \
  RDLWelcomeWindow.m \
  RDLExpressionEditor.m \
  RDLInsertPalette.m \
  RDLExpressionCell.m \
  RDLExpressionField.m \
  RDLFilterEditor.m \
  RDLSubreportParametersEditor.m \
  RDLToolbarIcons.m \
  RDLPane.m \
  RDLExpressionTheme.m \
  RDLExpressionTextStorage.m \
  RDLTabBadge.m \
  RDLDatasetNavigator.m \
  RDLDataSourceNavigator.m \
  RDLDataSourceView.m \
  RDLParameterNavigator.m \
  RDLParameterInspectorView.m \
  RDLFieldInspectorView.m \
  RDLDatasetFieldsView.m \
  ThirdParty/DMTabBar/DMTabBar.m \
  ThirdParty/DMTabBar/DMTabBarItem.m
# RDLKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLDesigner_OBJC_LIBS += -lRDLKit -ldispatch
# The bundle's icon: GNUstep puts it in the About panel, on the application's
# window and miniwindow icons, and in the dock tile. The same PNG the AppImage
# installs as the desktop icon.
RDLDesigner_APPLICATION_ICON = RDLDesigner.png

# The windows and the menu bar are XIBs. Xcode compiles them to .nib; here they
# are copied in as they are, and gnustep-gui reads the XIB directly (GSXib5).
# Both are found by the same -initWithNibNamed:, which is why no path or
# extension appears anywhere in the source.
# The sample reports are files, not code: they ship as a directory so that the
# master-detail pair and the JSON document they read stay beside each other,
# which is what a Subreport's relative ReportName resolves against.
# gnustep-make copies each resource file flat into Resources/ (bundle.make:
# `cp -fr $(RESOURCE_FILES_DIR)/$$f .../Resources/`), so naming the files one
# by one as Samples/X.rdl would drop them all beside the XIBs and leave the
# Samples directory empty -- which is what shipped. A resource file may be a
# directory, which is copied recursively and lands where its name says, so the
# directory is what gets named. It also means a new sample needs no edit here.
RDLDesigner_RESOURCE_FILES = \
  Samples

RDLDesigner_RESOURCE_FILES += \
  RDLDesigner.png \
  RDLExpressionEditor.xib \
  MainMenu.xib \
  RDLWelcomeWindow.xib \
  RDLDesignerWindow.xib \
  RDLGeneratorWindow.xib \
  RDLInspectorSections.xib \
  RDLFilterEditor.xib \
  RDLSubreportParametersEditor.xib \
  RDLDatasetNavigator.xib \
  RDLDataSourceNavigator.xib \
  RDLDataSourceView.xib \
  RDLParameterNavigator.xib \
  RDLParameterInspectorView.xib \
  RDLInsertPalette.xib \
  RDLDatasetFieldsView.xib \
  RDLFieldInspectorView.xib \
  RDLAddElementPanel.xib \
  RDLPreviewWindow.xib \
  RDLTablixEditor.xib \
  RDLRichTextEditor.xib \
  RDLNewReportPanel.xib

# Left empty on purpose: the menu bar is loaded explicitly in
# -[RDLAppDelegate loadMenuBar], so that the Samples submenu can be filled in
# from the sample catalogue through a real outlet.
RDLDesigner_MAIN_MODEL_FILE =

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

include $(GNUSTEP_MAKEFILES)/application.make
