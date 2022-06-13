# EuPathDB ontology Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the EuPathDB ontology.
#

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
EUPATH  := $(OBO)/EUPATH_
DEV     := $(OBO)/eupath/dev
TODAY   := $(shell date +%Y-%m-%d)

### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the official development version of ROBOT
build/robot.jar: | build
	curl -L -o $@ "https://github.com/ontodev/robot/releases/latest/download/robot.jar"

ROBOT := java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
build/import_%.owl: src/ontology/OntoFox-input/input_%.txt | build/robot.jar build
	curl -s -F file=@$< -o $@ https://ontofox.hegroup.org/service.php

# Use ROBOT to remove external axioms
src/ontology/imports/import_EFO.owl: build/import_EFO.owl
	$(ROBOT) remove --input build/import_EFO.owl \
	--base-iri 'http://www.ebi.ac.uk/efo/EFO_' \
	--axioms external \
	--preserve-structure false \
	--trim false \
	--output $@

src/ontology/imports/import_%.owl: build/import_%.owl
	$(ROBOT) remove --input build/import_$*.owl \
	--base-iri 'http://purl.obolibrary.org/obo/$*_' \
	--axioms external \
	--preserve-structure false \
	--trim false \
	--output $@

IMPORT_NAMES := APOLLO_SV\
 ARO\
 BTO\
 CHEBI\
 CIDO\
 CL\
 CMO\
 DOID\
 DRON\
 DUO\
 ECTO\
 EFO\
 ENVO\
 FOODON\
 GENEPIO\
 GO\
 HP\
 IAO\
 IDO\
 MOD\
 NCBITaxon\
 NCIT\
 OAE\
 OBCS\
 OBI\
 OBIB\
 OGMS\
 OMP\
 OMRSE\
 ONS\
 ONTONEO\
 OPL\
 PATO\
 PCO\
 PDRO\
 PHIPO\
 PO\
 PR\
 REO\
 RO\
 SO\
 STATO\
 SYMP\
 UBERON\
 UO\
 VO

IMPORT_FILES := $(foreach x,$(IMPORT_NAMES),src/ontology/imports/import_$(x).owl)

#IMPORT_FILES := $(wildcard src/ontology/imports/import_*.owl)

.PHONY: imports
imports: $(IMPORT_FILES)


### Templates
#
src/ontology/modules/%.owl: src/ontology/templates/%.tsv | build/robot.jar
	echo '' > $@
	$(ROBOT) merge \
	--input src/ontology/eupath_dev.owl \
	template \
	--template $< \
	annotate \
	--ontology-iri "http://purl.obolibrary.org/obo/eupath/dev/$(notdir $@)" \
	--output $@

# Update all modules
MODULE_NAMES := assays\
 chebi_roles\
 clinical-chemistry-data\
 devices\
 diagnosis\
 display_labels\
 general\
 insecticide_resistance\
 obsolete\
 popbio_organism\
 presence_data\
 protein_variant\
 raw_data\
 threshold-cycle\
 schedule_deprecate\
 symptom_duration

MODULE_FILES := $(foreach x,$(MODULE_NAMES),src/ontology/modules/$(x).owl)

.PHONY: modules
modules: $(MODULE_FILES)


### Build
#
# Here we create a standalone OWL file appropriate for release.
# This involves merging, reasoning, annotating,
# and removing any remaining import declarations.
build/eupath_merged.owl: src/ontology/eupath_dev.owl | build/robot.jar build
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/eupath/eupath_merged.owl" \
	--version-iri "$(OBO)/eupath/$(TODAY)/eupath_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/eupath_merged.tmp.owl
	sed '/http:\/\/www\.w3\.org\/1999\/02\/22-rdf-syntax-ns#type/d' build/eupath_merged.tmp.owl > build/eupath_merged.tmp2.owl
	sed '/<owl:imports/d' build/eupath_merged.tmp2.owl > $@
	rm build/eupath_merged.tmp.owl
	rm build/eupath_merged.tmp2.owl

eupath.owl: build/eupath_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/eupath.owl" \
	--version-iri "$(OBO)/eupath/$(TODAY)/eupath.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

ROBOT_report.tsv: eupath.owl
	$(ROBOT) report \
	--input $< \
        --fail-on none \
	--output $@

### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/eupath_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/eupath-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/eupath.owl"

build/released-entities.tsv: build/eupath-previous-release.owl src/sparql/get-eupath-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/eupath_merged.owl src/sparql/get-eupath-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

new-terms.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -13 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities list-entities

# Run validation queries on eupath_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/eupath_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " eupath IRIs have been dropped"
	@! test -s $<

# Count additional terms
.PHONY: list-entities
list-entities: new-terms.tsv
	@echo $(shell < $< wc -l) " terms have been added"

# Run a Hermit reasoner to find inconsistencies
.PHONY: reason
reason: build/eupath_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### General/Users/jiezheng/Documents/ontology/eupath
#
# Full build
.PHONY: all
all: test eupath.owl ROBOT_report.tsv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh
