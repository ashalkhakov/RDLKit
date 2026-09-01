include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Pica
Pica_NEEDS_GUI = yes
Pica_OBJCFLAGS += -fobjc-arc -Wall -I../PicaKit
Pica_OBJC_FILES = \
  main.m \
  PicaController.m \
  PicaCanvasView.m \
  PicaDesignerWindow.m \
  PicaGeneratorWindow.m \
  PicaAppDelegate.m \
  PicaSamples.m \
  PicaInspectorView.m \
  PicaDataView.m \
  PicaWelcomeWindow.m
Pica_OBJC_LIBS += -lPicaKit
Pica_APPLICATION_ICON =
Pica_MAIN_MODEL_FILE =

include $(GNUSTEP_MAKEFILES)/application.make
