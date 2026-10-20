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

RDLKitUI_OBJC_FILES = \
  RDLBordersEditor.m \
  RDLCanvasInteraction.m \
  RDLCanvasRenderer.m \
  RDLCanvasView.m \
  RDLChange.m \
  RDLChartAxisEditor.m \
  RDLChartSeriesEditor.m \
  RDLCodeEditor.m \
  RDLDataSourceNavigator.m \
  RDLDataSourceView.m \
  RDLDataView.m \
  RDLDatasetFieldsView.m \
  RDLDatasetNavigator.m \
  RDLDatasetOptionsEditor.m \
  RDLDocument.m \
  RDLEditingContext.m \
  RDLEditor.m \
  RDLEmbeddedImages.m \
  RDLEmbeddedImagesEditor.m \
  RDLExpressionCell.m \
  RDLExpressionEditor.m \
  RDLExpressionField.m \
  RDLExpressionHelper.m \
  RDLExpressionTextStorage.m \
  RDLExpressionTheme.m \
  RDLFieldInspectorView.m \
  RDLFilterEditor.m \
  RDLGroupPropertiesEditor.m \
  RDLGroupsView.m \
  RDLInPlaceEditor.m \
  RDLInsertPalette.m \
  RDLInspectorFields.m \
  RDLInspectorView.m \
  RDLItemFactory.m \
  RDLKitUIBundle.m \
  RDLOutlineDataSource.m \
  RDLOutlineView.m \
  RDLPageGeometry.m \
  RDLPane.m \
  RDLParameterInspectorView.m \
  RDLParameterNavigator.m \
  RDLParameterPrompts.m \
  RDLPlainTextEdit.m \
  RDLPreviewWindow.m \
  RDLProblemsView.m \
  RDLRenderInputsEditor.m \
  RDLReportDesigner.m \
  RDLReportDesignerWindowController.m \
  RDLReportViewController.m \
  RDLReportViewerWindowController.m \
  RDLRichTextCodec.m \
  RDLRichTextEditor.m \
  RDLRichTextFormatter.m \
  RDLSamples.m \
  RDLSelection.m \
  RDLSnapGuides.m \
  RDLSortEditor.m \
  RDLSourceView.m \
  RDLStylePanel.m \
  RDLSubreportParametersEditor.m \
  RDLTabBadge.m \
  RDLTablixStructure.m \
  RDLToolbarIcons.m \
  RDLValueListEditor.m \
  RDLVariablesEditor.m \
  ThirdParty/DMTabBar/DMTabBar.m \
  ThirdParty/DMTabBar/DMTabBarItem.m

# Every window, panel and pane is a XIB: Xcode compiles them into the
# framework, gnustep-gui reads them as they are, from the library's resources.
RDLKitUI_RESOURCE_FILES = \
  RDLAddElementPanel.xib \
  RDLBordersEditor.xib \
  RDLChartAxisEditor.xib \
  RDLChartSeriesEditor.xib \
  RDLCodeEditor.xib \
  RDLDataSourceNavigator.xib \
  RDLDataSourceView.xib \
  RDLDatasetFieldsView.xib \
  RDLDatasetNavigator.xib \
  RDLDatasetOptionsEditor.xib \
  RDLEmbeddedImagesEditor.xib \
  RDLExpressionEditor.xib \
  RDLFieldInspectorView.xib \
  RDLFilterEditor.xib \
  RDLGroupPropertiesEditor.xib \
  RDLGroupsView.xib \
  RDLInsertPalette.xib \
  RDLInspectorSections.xib \
  RDLParameterInspectorView.xib \
  RDLParameterNavigator.xib \
  RDLPreviewWindow.xib \
  RDLProblemsView.xib \
  RDLRenderInputsEditor.xib \
  RDLReportDesigner.xib \
  RDLReportDesignerWindow.xib \
  RDLReportViewController.xib \
  RDLReportViewerWindow.xib \
  RDLRichTextEditor.xib \
  RDLSortEditor.xib \
  RDLSourceView.xib \
  RDLStylePanel.xib \
  RDLSubreportParametersEditor.xib \
  RDLValueListEditor.xib \
  RDLVariablesEditor.xib

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
