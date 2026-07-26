.PHONY: practitioner-guide practitioner-guide-check clean-practitioner-guide

GUIDE_DIR := docs/practitioner-guide
GUIDE_BUILD := $(GUIDE_DIR)/build
GUIDE_PDF := $(GUIDE_BUILD)/TransportNetworkWelfare-Practitioner-Guide.pdf

practitioner-guide:
	mkdir -p "$(GUIDE_BUILD)"
	latexmk -pdf -interaction=nonstopmode -halt-on-error \
		-outdir="$(GUIDE_BUILD)" "$(GUIDE_DIR)/main.tex"
	cp "$(GUIDE_BUILD)/main.pdf" "$(GUIDE_PDF)"
	@echo "$(GUIDE_PDF)"

practitioner-guide-check: practitioner-guide
	bash scripts/check_practitioner_guide.sh "$(GUIDE_DIR)" "$(GUIDE_PDF)"

clean-practitioner-guide:
	latexmk -C -outdir="$(GUIDE_BUILD)" "$(GUIDE_DIR)/main.tex"
	rm -f "$(GUIDE_PDF)"
