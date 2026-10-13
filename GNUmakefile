#
# RDLKit on GNUstep: the library, rdlgen and RDLDesigner, and their tests.
#
#   make            the library, the tool, the designer and the test bundles
#   make check      no macOS-only imports, the two suites (under Xvfb when
#                   there is no display), and rdlgen on a sample report
#   make install    the library, rdlgen and RDLDesigner; not the test bundles
#
# Each part builds on the library in the tree (RDLKit/), not an installed one.
# macOS: Makefile.apple.
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = RDLKit
SUBPROJECTS = RDLKit RDLGen RDLDesigner RDLKitTests RDLDesignerTests

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
RDL_RUN = LD_LIBRARY_PATH="$(CURDIR)/RDLKit/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

check::
	Scripts/check-imports.sh
	$(XVFB) $(MAKE) -C RDLKitTests run-tests
	$(XVFB) $(MAKE) -C RDLDesignerTests run-tests
	$(RDL_RUN) XVFB="$(XVFB)" Scripts/rdlgen-smoke.sh RDLGen/$(GNUSTEP_OBJ_DIR_NAME)/rdlgen
