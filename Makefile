.PHONY: practitioner-guide-assets practitioner-guide-example-assets practitioner-guide-external-assets practitioner-guide practitioner-guide-check clean-practitioner-guide plot-check release-metadata-check release-artifacts clean-release-artifacts

GUIDE_DIR := docs/practitioner-guide
GUIDE_BUILD := $(GUIDE_DIR)/build
GUIDE_PDF := $(GUIDE_BUILD)/TransportNetworkWelfare-Practitioner-Guide.pdf
DIST_DIR := dist
RELEASE_GUIDE := $(DIST_DIR)/TransportNetworkWelfare-Practitioner-Guide.pdf

practitioner-guide-assets:
	julia examples/grid_multimodal/build_inputs.jl
	julia --project=. scripts/build_practitioner_guide_assets.jl
	bash scripts/build_practitioner_guide_figures.sh build
	python3 -m plots.example_assets

practitioner-guide-example-assets:
	python3 -m plots.example_assets

practitioner-guide-external-assets:
	test -n "$(TNW_SIOUX_FALLS_ROOT)"
	test -n "$(TNW_WESTEROS_ROOT)"
	test -n "$(TNW_SEATTLE_ARTIFACTS)"
	test -n "$(TNW_SEATTLE_MODEL_ROOT)"
	test -n "$(TNW_SEATTLE_GEOGRAPHY_ROOT)"
	test -n "$(TNW_SEATTLE_GTFS_ROOT)"
	python3 scripts/build_practitioner_external_example_assets.py \
		--sioux-root "$(TNW_SIOUX_FALLS_ROOT)" \
		--westeros-root "$(TNW_WESTEROS_ROOT)" \
		--seattle-artifacts "$(TNW_SEATTLE_ARTIFACTS)" \
		--seattle-model-root "$(TNW_SEATTLE_MODEL_ROOT)" \
		--seattle-geography-root "$(TNW_SEATTLE_GEOGRAPHY_ROOT)" \
		--seattle-gtfs-root "$(TNW_SEATTLE_GTFS_ROOT)"

practitioner-guide:
	mkdir -p "$(GUIDE_BUILD)"
	SOURCE_DATE_EPOCH=946684800 FORCE_SOURCE_DATE=1 TZ=UTC \
	latexmk -g -pdf -interaction=nonstopmode -halt-on-error \
		-outdir="$(GUIDE_BUILD)" "$(GUIDE_DIR)/main.tex"
	qpdf --deterministic-id --linearize "$(GUIDE_BUILD)/main.pdf" "$(GUIDE_PDF)"
	@echo "$(GUIDE_PDF)"

practitioner-guide-check: practitioner-guide
	julia --project=. scripts/build_practitioner_guide_assets.jl --check
	bash scripts/build_practitioner_guide_figures.sh check
	python3 -m plots.example_assets --check
	python3 scripts/build_practitioner_external_example_assets.py --check
	bash scripts/check_practitioner_guide.sh "$(GUIDE_DIR)" "$(GUIDE_PDF)"

clean-practitioner-guide:
	latexmk -C -outdir="$(GUIDE_BUILD)" "$(GUIDE_DIR)/main.tex"
	rm -f "$(GUIDE_PDF)"

plot-check:
	python3 -m unittest discover -s plots -p 'test_*.py'

release-metadata-check:
	python3 scripts/check_release_metadata.py

release-artifacts: release-metadata-check practitioner-guide-check
	mkdir -p "$(DIST_DIR)"
	cp "$(GUIDE_PDF)" "$(RELEASE_GUIDE)"
	cd "$(DIST_DIR)" && shasum -a 256 "$$(basename "$(RELEASE_GUIDE)")" > TransportNetworkWelfare-Practitioner-Guide.sha256
	@echo "$(RELEASE_GUIDE)"

clean-release-artifacts:
	rm -rf "$(DIST_DIR)"
