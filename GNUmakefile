#
# RDLKit on GNUstep: the libraries, rdlgen and RDLDesigner, and their tests.
#
#   make            RDLKit (the generator), RDLKitUI (the viewer and the
#                   designer, to embed), rdlgen and RDLDesigner
#   make check      no macOS-only imports; the two suites, built and run
#                   under AddressSanitizer (and Xvfb when there is no
#                   display); the designer's UI tests, run in RDLDesigner
#                   itself; rdlgen on a sample report; the example host
#                   (Examples/ReportHost), --self-test; and the libraries
#                   installed into a staging directory and used from there
#                   (Scripts/installcheck.sh)
#   make install    the libraries with their headers (and RDLKitUI's XIBs),
#                   rdlgen and RDLDesigner; not the test bundles. What an app
#                   pins: the release's rdlkit-<v>-ubuntu22.04-<arch>.tar.xz,
#                   unpacked at /, then -lRDLKitUI -lRDLKit
#
# Each part builds on the libraries in the tree, not installed ones.
# macOS: Makefile.apple.
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = RDLKit
SUBPROJECTS = RDLKit RDLKitUI RDLGen RDLDesigner

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
RDL_RUN = LD_LIBRARY_PATH="$(CURDIR)/RDLKit/$(GNUSTEP_OBJ_DIR_NAME):$(CURDIR)/RDLKitUI/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

# The suites are built here, not with the rest: under AddressSanitizer
# (SANITIZE=1), which names a bad write where it happens.
check::
	Scripts/check-imports.sh
	$(XVFB) $(MAKE) -C RDLKitTests run-tests SANITIZE=1
	$(XVFB) $(MAKE) -C RDLDesignerTests run-tests SANITIZE=1
	$(XVFB) $(MAKE) -C RDLDesignerUITests run-tests
	$(RDL_RUN) XVFB="$(XVFB)" Scripts/rdlgen-smoke.sh RDLGen/$(GNUSTEP_OBJ_DIR_NAME)/rdlgen
	$(MAKE) -C Examples/ReportHost self-test
	@stage=$$(mktemp -d) && \
	  $(MAKE) -C RDLKit install DESTDIR=$$stage > $$stage.log 2>&1 && \
	  $(MAKE) -C RDLKitUI install DESTDIR=$$stage >> $$stage.log 2>&1 \
	  || { cat $$stage.log; rm -rf $$stage $$stage.log; exit 1; }; \
	  Scripts/installcheck.sh gnustep $$stage; status=$$?; rm -rf $$stage $$stage.log; exit $$status

after-clean::
	$(MAKE) -C Examples/ReportHost clean
	$(MAKE) -C RDLKitTests clean
	$(MAKE) -C RDLDesignerTests clean
	$(MAKE) -C RDLDesignerUITests clean
