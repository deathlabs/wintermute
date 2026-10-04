# ---------------------------------------------------------
# Default settings.
# ---------------------------------------------------------

# Use Bash as the default shell.
SHELL := /bin/bash

# Set the default Make target.
.DEFAULT_GOAL := test-container

# Normalize the workspace path and expose it to Docker Compose.
WORKSPACE ?= $(CURDIR)
MCP_SERVER_WORKSPACE := $(abspath $(WORKSPACE))
export MCP_SERVER_WORKSPACE

# Tell Docker Compose to use Bake for builds.
export COMPOSE_BAKE := true

# Set the default Docker Compose profile.
DOCKER_COMPOSE_PROFILE ?= all

# Set Docker build context and image reference.
BUILD_CONTEXT := mcp-server
DOCKERFILE_PATH :=$(BUILD_CONTEXT)/Dockerfile
IMAGE_REF := wintermute/mcp:latest
CONTAINER_NAME := wintermute_mcp

# Set SBOM and VEX file paths.
SBOM_PATH := wintermute-sbom.json
VEX_YAML_PATH :=$(BUILD_CONTEXT)/vex.yaml
VEX_JSON_PATH :=$(BUILD_CONTEXT)/vex.json

# Set VEX metadata.
VEX_AUTHOR ?= Victor Fernandez III
VEX_ID_BASE ?= wintermute

# Set scanner configuration and thresholds.
SEMGREP_CONFIG ?= auto
HADOLINT_FAILURE_THRESHOLD ?= warning
GRYPE_FAILURE_THRESHOLD ?= medium

# ---------------------------------------------------------
# Update uv.lock.
# ---------------------------------------------------------

.PHONY: lock
.SILENT: lock
lock:
	echo "[*] Locking wintermute Python dependencies"
	cd $(BUILD_CONTEXT)/wintermute && uv lock

# ---------------------------------------------------------
# Check the source code for quality.
# ---------------------------------------------------------

.PHONY: check
.SILENT: check
check:
	echo "[*] Checking wintermute's source code quality"
	ruff check --fix $(BUILD_CONTEXT)

# ---------------------------------------------------------
# Format the source code.
# ---------------------------------------------------------

.PHONY: format
.SILENT: format
format:
	echo "[*] Formatting wintermute's source code"
	ruff format $(BUILD_CONTEXT)

# ---------------------------------------------------------
# Check the repository for secrets.
# ---------------------------------------------------------

.PHONY: secrets
.SILENT: secrets
secrets:
	echo "[*] Checking wintermute's source code for hardcoded secrets"
	trufflehog filesystem \
		--no-update \
		--fail \
		--fail-on-scan-errors \
		--results=verified,unknown \
		--log-level=-1 \
		--exclude-paths $(BUILD_CONTEXT)/trufflehog-exclusions.txt 

# ---------------------------------------------------------
# Check the Dockerfile for quality.
# ---------------------------------------------------------

.PHONY: dockerfile-lint
.SILENT: dockerfile-lint
dockerfile-lint:
	echo "[*] Checking wintermute's Dockerfile for lint"
	hadolint \
		--failure-threshold "$(HADOLINT_FAILURE_THRESHOLD)" \
		"$(DOCKERFILE_PATH)"

# ---------------------------------------------------------
# Check for first-party vulnerabilities.
# ---------------------------------------------------------

.PHONY: sast
.SILENT: sast
sast:
	echo "[*] Checking wintermute's source code for first-party vulnerabilities"
	semgrep scan --config "$(SEMGREP_CONFIG)" $(BUILD_CONTEXT)

# ---------------------------------------------------------
# Build the container image.
# ---------------------------------------------------------

.PHONY: build-container
.SILENT: build-container
build-container: lock check format secrets dockerfile-lint sast
	echo "[*] Building wintermute's container image"
	docker compose --profile $(DOCKER_COMPOSE_PROFILE) build 

# ---------------------------------------------------------
# Generate a VEX file for the container image.
# ---------------------------------------------------------

define VEX_FILTER
{
  "@context": "https://openvex.dev/ns/v0.2.0",
  "@id": strenv(VEX_ID),
  "author": strenv(VEX_AUTHOR),
  "timestamp": strenv(VEX_TIMESTAMP),
  "version": 1,
  "statements": [
    .advisories[] | {
      "vulnerability": {
        "name": .vulnerability
      },
      "products": [
        .products[] | {
          "@id": .
        }
      ],
      "status": .status,
      "justification": .justification,
      "impact_statement": .impact_statement
    }
  ]
}
endef

export VEX_FILTER

.PHONY: vex
.SILENT: vex
vex:
	echo "[*] Generating wintermute's VEX statements"
	VEX_ID="$(VEX_ID_BASE)" \
	VEX_AUTHOR="$(VEX_AUTHOR)" \
	VEX_TIMESTAMP="$$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
	yq -o=json "$$VEX_FILTER" "$(VEX_YAML_PATH)" > "$(VEX_JSON_PATH)"

# ---------------------------------------------------------
# Generate an SBOM for the container image.
# ---------------------------------------------------------

.PHONY: sbom
.SILENT: sbom
sbom: build-container
	echo "[*] Generating wintermute's SBOM"
	syft wintermute/mcp:latest -o cyclonedx-json="$(SBOM_PATH)"

# ---------------------------------------------------------
# Check for third-party vulnerabilities.
# ---------------------------------------------------------

.PHONY: dependency-scan
.SILENT: dependency-scan
dependency-scan: sbom vex
	echo "[*] Updating the Grype vulnerability database"
	grype db update
	echo "[*] Checking wintermute's SBOM for third-party vulnerabilities"
	grype sbom:"$(SBOM_PATH)" \
		--vex "$(VEX_JSON_PATH)" \
		--fail-on "$(GRYPE_FAILURE_THRESHOLD)"

# ---------------------------------------------------------
# Start the container.
# ---------------------------------------------------------

.PHONY: start-container
.SILENT: start-container
start-container: dependency-scan
	docker compose --profile $(DOCKER_COMPOSE_PROFILE) up -d

# ---------------------------------------------------------
# Check the status of the container.
# ---------------------------------------------------------

.PHONY: status
.SILENT: status
status:
	docker compose --profile $(DOCKER_COMPOSE_PROFILE) ps --format "table {{.Name}}\t{{.Ports}}\t{{.Status}}"

# ---------------------------------------------------------
# Test the container.
# ---------------------------------------------------------

.PHONY: test-container
.SILENT: test-container
test-container: start-container
	echo "[*] Testing wintermute"
	cd tests && uv run python main.py

# ---------------------------------------------------------
# Stop the container.
# ---------------------------------------------------------

.PHONY: stop-container
.SILENT: stop-container
stop-container:
	docker container stop ${CONTAINER_NAME} || true

# ---------------------------------------------------------
# Remove the container.
# ---------------------------------------------------------

.PHONY: remove-container
.SILENT: remove-container
remove-container:
	docker container rm ${CONTAINER_NAME} || true

# ---------------------------------------------------------
# Remove the container image.
# ---------------------------------------------------------

.PHONY: remove-container-image
.SILENT: remove-container-image
remove-container-image:
	docker image rm ${IMAGE_REF} || true

# ---------------------------------------------------------
# Purge the container and its container image.
# ---------------------------------------------------------

.PHONY: clean
.SILENT: clean
clean: stop-container remove-container remove-container-image
