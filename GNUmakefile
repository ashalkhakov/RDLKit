#
# RDLKit on GNUstep: the library, rdlgen and RDLDesigner, and their tests.
#
#   make            the library, the tool and the designer
#   make check      no macOS-only imports; the two suites, built and run
#                   under AddressSanitizer (and Xvfb when there is no
#                   display); the designer's UI tests, run in RDLDesigner
#                   itself; rdlgen on a sample report
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
SUBPROJECTS = RDLKit RDLGen RDLDesigner

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
RDL_RUN = LD_LIBRARY_PATH="$(CURDIR)/RDLKit/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

# The suites are built here, not with the rest: under AddressSanitizer
# (SANITIZE=1), which names a bad write where it happens.
check::
	Scripts/check-imports.sh
	$(XVFB) $(MAKE) -C RDLKitTests run-tests SANITIZE=1
	$(XVFB) $(MAKE) -C RDLDesignerTests run-tests SANITIZE=1
	$(XVFB) $(MAKE) -C RDLDesignerUITests run-tests
	$(RDL_RUN) XVFB="$(XVFB)" Scripts/rdlgen-smoke.sh RDLGen/$(GNUSTEP_OBJ_DIR_NAME)/rdlgen

after-clean::
	$(MAKE) -C RDLKitTests clean
	$(MAKE) -C RDLDesignerTests clean
	$(MAKE) -C RDLDesignerUITests clean
