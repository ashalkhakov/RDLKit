# An XCTest bundle that requires tools-xctest
# (https://github.com/gnustep/tools-xctest)
#
#   make          build the bundle
#   make check    build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = PicaKitTests

PicaKitTests_OBJC_FILES = \
  PicaKitTests.m
PicaKitTests_OBJCFLAGS += -fobjc-arc -Wall
PicaKitTests_INCLUDE_DIRS = -I../PicaKit
PicaKitTests_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
PicaKitTests_BUNDLE_LIBS += -lPicaKit -lXCTest
# The PDF backend and text measurement are AppKit.
PicaKitTests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# The .docx fixtures are found relative to __FILE__ rather than through the
# bundle, so they need no RESOURCE_FILES entry -- but they do mean the checks
# have to run from a source tree, not from an installed bundle.
.PHONY: check
check: all
	LD_LIBRARY_PATH="$(CURDIR)/../PicaKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  $(XCTEST) $(BUNDLE_NAME).bundle
