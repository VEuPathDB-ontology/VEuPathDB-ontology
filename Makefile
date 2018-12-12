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
	curl -L -o $@ https://build.berkeleybop.org/job/robot/lastSuccessfulBuild/artifact/bin/robot.jar

ROBOT := java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
build/import_%.owl: src/OntoFox-input/input_%.txt | build
	curl -s -F file=@$< -o $@ http://ontofox.hegroup.org/service.php

# Use ROBOT to ensure that serialization is consistent.
src/ontology/import/import_%.owl: build/import_%.owl
	$(ROBOT) convert -i build/$import_*.owl -o $@

IMPORT_FILES := $(wildcard src/ontology/import/import_*.owl)

.PHONY: imports
imports: $(IMPORT_FILES)


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
	sed '/<owl:imports/d' build/eupath_merged.tmp.owl > $@
	rm build/eupath_merged.tmp.owl

eupath.owl: build/eupath_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/eupath.owl" \
	--version-iri "$(OBO)/eupath/$(TODAY)/eupath.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/eupath_merged.owl
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

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

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
all: test eupath.owl build/terms-report.csv

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
