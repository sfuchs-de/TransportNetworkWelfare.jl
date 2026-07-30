.PHONY: help instantiate test smoke docs check public-release-check \
	practitioner-guide-assets practitioner-guide-example-assets \
	practitioner-guide-external-assets practitioner-guide \
	practitioner-guide-check clean-practitioner-guide plot-check \
	census-check release-metadata-check provenance-check secret-scan \
	release-artifacts clean-release-artifacts clean

JULIA ?= julia
PYTHON ?= python3

GUIDE_DIR := docs/practitioner-guide
GUIDE_BUILD := $(GUIDE_DIR)/build
GUIDE_PDF := $(GUIDE_BUILD)/TransportNetworkWelfare-Practitioner-Guide.pdf
DIST_DIR := dist
RELEASE_GUIDE := $(DIST_DIR)/TransportNetworkWelfare-Practitioner-Guide.pdf

help:
	@printf '%s\n' \
		'Common targets:' \
		'  instantiate          Install Julia dependencies' \
		'  test                 Run the Julia test suite' \
		'  smoke                Run the toy CLI workflow' \
		'  docs                 Build HTML documentation' \
		'  census-check         Test the public Census adapter' \
		'  check                Run package and repository checks' \
		'  practitioner-guide   Build the guide PDF' \
		'  practitioner-guide-check  Verify guide assets and PDF' \
		'  public-release-check Run all public-release checks' \
		'  release-artifacts    Build the checked release PDF and checksum' \
		'  clean                Remove ignored build and smoke-test outputs'

instantiate:
	$(JULIA) --project=. -e 'using Pkg; Pkg.instantiate()'

test:
	$(JULIA) --project=. -e 'using Pkg; Pkg.test()'

smoke:
	$(JULIA) --project=. bin/tnw.jl validate examples/toy/config.toml
	$(JULIA) --project=. bin/tnw.jl analyze examples/toy/config.toml
	$(JULIA) --project=. bin/tnw.jl decompose examples/toy/config.toml

docs:
	$(JULIA) --project=docs -e \
		'using Pkg; Pkg.develop(path="."); Pkg.instantiate(); include("docs/make.jl")'

census-check:
	$(PYTHON) -m unittest discover -s replication/rsue/census_ports -p 'test_*.py'

release-metadata-check:
	$(PYTHON) scripts/check_release_metadata.py

provenance-check:
	$(PYTHON) scripts/verify_provenance.py

secret-scan:
	$(PYTHON) scripts/scan_secrets.py

check: test smoke docs census-check release-metadata-check provenance-check secret-scan
	git diff --check

practitioner-guide-assets:
	$(JULIA) examples/grid_multimodal/build_inputs.jl
	$(JULIA) --project=. scripts/build_practitioner_guide_assets.jl
	bash scripts/build_practitioner_guide_figures.sh build
	$(PYTHON) -m plots.example_assets

practitioner-guide-example-assets:
	$(PYTHON) -m plots.example_assets

practitioner-guide-external-assets:
	test -n "$(TNW_SIOUX_FALLS_ROOT)"
	test -n "$(TNW_WESTEROS_ROOT)"
	test -n "$(TNW_SEATTLE_ARTIFACTS)"
	test -n "$(TNW_SEATTLE_MODEL_ROOT)"
	test -n "$(TNW_SEATTLE_GEOGRAPHY_ROOT)"
	test -n "$(TNW_SEATTLE_GTFS_ROOT)"
	$(PYTHON) scripts/build_practitioner_external_example_assets.py \
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
	qpdf --deterministic-id --linearize \
		"$(GUIDE_BUILD)/main.pdf" "$(GUIDE_PDF)"
	@echo "$(GUIDE_PDF)"

practitioner-guide-check: practitioner-guide
	$(JULIA) --project=. scripts/build_practitioner_guide_assets.jl --check
	bash scripts/build_practitioner_guide_figures.sh check
	$(PYTHON) -m plots.example_assets --check
	$(PYTHON) scripts/build_practitioner_external_example_assets.py --check
	bash scripts/check_practitioner_guide.sh "$(GUIDE_DIR)" "$(GUIDE_PDF)"

clean-practitioner-guide:
	rm -rf "$(GUIDE_BUILD)"

plot-check:
	$(PYTHON) -m unittest discover -s plots -p 'test_*.py'

public-release-check: check plot-check practitioner-guide-check
	$(PYTHON) test/verify_prop2.py

release-artifacts: release-metadata-check practitioner-guide-check
	mkdir -p "$(DIST_DIR)"
	cp "$(GUIDE_PDF)" "$(RELEASE_GUIDE)"
	cd "$(DIST_DIR)" && shasum -a 256 \
		"$$(basename "$(RELEASE_GUIDE)")" \
		> TransportNetworkWelfare-Practitioner-Guide.sha256
	@echo "$(RELEASE_GUIDE)"

clean-release-artifacts:
	rm -rf "$(DIST_DIR)"

clean: clean-practitioner-guide clean-release-artifacts
	rm -f Manifest.toml docs/Manifest.toml
	rm -rf docs/build examples/toy/output examples/braess/output \
		examples/cow/output examples/grid_multimodal/output \
		examples/urban_toy/output examples/urban_multimodal/output
