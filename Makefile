PYTHON ?= python3
JOBS ?= 2
RUN_ARGS ?=

.PHONY: setup doctor repo-check lint test-unit test-uvm-smoke uvm-dpi formal-smoke formal-rtl synth-smoke frontends formal-symbols multi-egress-declarations ci regression coverage benchmark synthesis sta
setup:
	bash tools/setup.sh --jobs $(JOBS)

doctor repo-check lint test-unit test-uvm-smoke uvm-dpi formal-smoke formal-rtl synth-smoke frontends formal-symbols multi-egress-declarations ci regression coverage benchmark synthesis sta:
	$(PYTHON) tools/run.py $@ --jobs $(JOBS) $(RUN_ARGS)

.PHONY: multi-egress-pools-preparation multi-egress-pools-candidate multi-egress-pools-formal
multi-egress-pools-preparation multi-egress-pools-candidate multi-egress-pools-formal:
	$(PYTHON) tools/run.py $@ --jobs $(JOBS) $(RUN_ARGS)
