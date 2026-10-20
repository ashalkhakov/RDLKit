include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = RDLDesigner
RDLDesigner_NEEDS_GUI = yes
RDLDesigner_OBJCFLAGS += -fobjc-arc -Wall -I../RDLKit -I../RDLKit/MiniVB -I../RDLKitUI \
                         -I../RDLKitUI/ThirdParty/DMTabBar -Werror=logical-not-parentheses
# The application around the designer: the library and the generator windows,
# the new-report wizard, the menu bar, updates. The designer itself -- its
# windows, panes and editing core -- is RDLKitUI's.
RDLDesigner_OBJC_FILES = \
  RDLUpdater.m \
  main.m \
  RDLAppDelegate.m \
  RDLWelcomeWindow.m \
  RDLGeneratorWindow.m \
  RDLNewReport.m \
  RDLNewReportPanel.m
# RDLKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR) -L../RDLKitUI/$(GNUSTEP_OBJ_DIR)
RDLDesigner_OBJC_LIBS += -lRDLKitUI -lRDLKit -ldispatch
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

# The application's own windows, and RDLKitUI's as well: an installed
# libRDLKitUI finds its XIBs in its own resources, and one run from the tree --
# the checks, the UI suite, the AppImage -- finds them here
# (RDLKitUIBundle()).
RDLDesigner_RESOURCE_FILES += \
  RDLDesigner.png \
  MainMenu.xib \
  RDLWelcomeWindow.xib \
  RDLGeneratorWindow.xib \
  RDLNewReportPanel.xib \
  ../RDLKitUI/RDLAddElementPanel.xib \
  ../RDLKitUI/RDLBordersEditor.xib \
  ../RDLKitUI/RDLChartAxisEditor.xib \
  ../RDLKitUI/RDLChartSeriesEditor.xib \
  ../RDLKitUI/RDLCodeEditor.xib \
  ../RDLKitUI/RDLDataSourceNavigator.xib \
  ../RDLKitUI/RDLDataSourceView.xib \
  ../RDLKitUI/RDLDatasetFieldsView.xib \
  ../RDLKitUI/RDLDatasetNavigator.xib \
  ../RDLKitUI/RDLDatasetOptionsEditor.xib \
  ../RDLKitUI/RDLEmbeddedImagesEditor.xib \
  ../RDLKitUI/RDLExpressionEditor.xib \
  ../RDLKitUI/RDLFieldInspectorView.xib \
  ../RDLKitUI/RDLFilterEditor.xib \
  ../RDLKitUI/RDLGroupPropertiesEditor.xib \
  ../RDLKitUI/RDLGroupsView.xib \
  ../RDLKitUI/RDLInsertPalette.xib \
  ../RDLKitUI/RDLInspectorSections.xib \
  ../RDLKitUI/RDLParameterInspectorView.xib \
  ../RDLKitUI/RDLParameterNavigator.xib \
  ../RDLKitUI/RDLPreviewWindow.xib \
  ../RDLKitUI/RDLProblemsView.xib \
  ../RDLKitUI/RDLRenderInputsEditor.xib \
  ../RDLKitUI/RDLReportDesigner.xib \
  ../RDLKitUI/RDLReportDesignerWindow.xib \
  ../RDLKitUI/RDLReportViewController.xib \
  ../RDLKitUI/RDLReportViewerWindow.xib \
  ../RDLKitUI/RDLRichTextEditor.xib \
  ../RDLKitUI/RDLSortEditor.xib \
  ../RDLKitUI/RDLSourceView.xib \
  ../RDLKitUI/RDLStylePanel.xib \
  ../RDLKitUI/RDLSubreportParametersEditor.xib \
  ../RDLKitUI/RDLValueListEditor.xib \
  ../RDLKitUI/RDLVariablesEditor.xib

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
