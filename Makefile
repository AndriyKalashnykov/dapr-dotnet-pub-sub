# SPDX-License-Identifier: MIT

.DEFAULT_GOAL := help

# Use bash for recipe execution (dash lacks `set -o pipefail`)
SHELL := /bin/bash

# Ensure user-local binaries (mise + mise shims) are on PATH
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# ---------------------------------------------------------------------------
# Tool versions
# ---------------------------------------------------------------------------
# .NET SDK version derived from global.json (single source of truth)
DOTNET_VERSION     := $(shell awk -F'"' '/"version"/{split($$4,v,"."); print v[1]"."v[2]; exit}' global.json 2>/dev/null)
# Node, dapr CLI, act, kind, kubectl, helm, and cloud-provider-kind are pinned in .mise.toml
# renovate: datasource=github-releases depName=dapr/dapr extractVersion=^v(?<version>.*)$
DAPR_RUNTIME_VERSION := 1.17.6
# Consumed via 'docker run' (containerised scanner) — intentionally NOT a mise host pin
# renovate: datasource=github-releases depName=aquasecurity/trivy extractVersion=^v(?<version>.*)$
TRIVY_VERSION      := 0.70.0
# Consumed via 'docker run' (containerised scanner) — intentionally NOT a mise host pin
# renovate: datasource=github-releases depName=gitleaks/gitleaks extractVersion=^v(?<version>.*)$
GITLEAKS_VERSION   := 8.30.1
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.14.0
# renovate: datasource=helm depName=dapr registryUrl=https://dapr.github.io/helm-charts
DAPR_HELM_VERSION  := 1.17.4
# KinD node image — bumped together with kind (see kind release notes)
# renovate: datasource=docker depName=kindest/node
KIND_NODE_IMAGE    := kindest/node:v1.35.0@sha256:4613778f3cfcd10e615029370f5786704559103cf27bef934597ba562b269661
# act runner image for 'make ci-run' (ubuntu-latest maps to ubuntu-24.04)
# renovate: datasource=docker depName=catthehacker/ubuntu versioning=loose
ACT_UBUNTU_VERSION := act-24.04-20260622
KIND_CLUSTER_NAME  := dapr-pubsub
# Use a per-cluster kubectl context to avoid clobbering kubeconfig across projects
KUBECTL            := kubectl --context=kind-$(KIND_CLUSTER_NAME)
HELM               := helm --kube-context=kind-$(KIND_CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Project constants
# ---------------------------------------------------------------------------
APP_NAME         := dapr-dotnet-pub-sub
CURRENTTAG       := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "none")
SOLUTION         := dapr-dotnet-pub-sub.slnx
PORTS            := 3530 3531 3532 5230 5231 5232 7006 7007
SEMVER_RE        := ^v[0-9]+\.[0-9]+\.[0-9]+$$
COVERAGE_DIR     := tests/TestResults
COVERAGE_FILE    := coverage.cobertura.xml
COVERAGE_MIN     := 0.80

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

#deps: @ Check required tool dependencies (dotnet, curl)
deps:
	@command -v dotnet >/dev/null 2>&1 || { echo "ERROR: dotnet is not installed (need $(DOTNET_VERSION)+)"; exit 1; }
	@command -v curl   >/dev/null 2>&1 || { echo "ERROR: curl is not installed"; exit 1; }

#deps-docker: @ Check Docker is installed (for containerised scanners)
deps-docker:
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed"; exit 1; }

#deps-run: @ Check runtime dependencies (dotnet, curl, docker, dapr)
deps-run: deps deps-docker deps-tools
	@command -v dapr   >/dev/null 2>&1 || { echo "ERROR: dapr CLI is not installed (run 'mise install')"; exit 1; }

#deps-tools: @ Install pinned tools (mise + node, dapr CLI, act per .mise.toml)
deps-tools:
	@set -euo pipefail; \
	if ! command -v mise >/dev/null 2>&1; then \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	fi; \
	mise install --yes

#deps-act: @ Install pinned tools (alias for deps-tools — needed by ci-run)
deps-act: deps-tools

#deps-prune: @ Show redundant NuGet package references
deps-prune: deps
	@set -euo pipefail; \
	echo "=== Dependency Pruning ==="; \
	echo "--- .NET: checking for redundant PackageReferences ---"; \
	OUTPUT=$$(dotnet build $(SOLUTION) --nologo -v q 2>&1); \
	if echo "$$OUTPUT" | grep -E 'NU1510|NU1504'; then \
		echo "  ^^^ Remove these PackageReferences from .csproj files"; \
	else \
		echo "  No redundant .NET packages found."; \
	fi; \
	echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no redundant NuGet package references
deps-prune-check: deps
	@set -euo pipefail; \
	echo "Checking for redundant package references..."; \
	OUTPUT=$$(dotnet build $(SOLUTION) --nologo -v q 2>&1); \
	if echo "$$OUTPUT" | grep -qE 'NU1510|NU1504'; then \
		echo "ERROR: Redundant or duplicate package references found:"; \
		echo "$$OUTPUT" | grep -E 'NU1510|NU1504'; \
		exit 1; \
	fi

#clean: @ Remove build artifacts
clean:
	@dotnet clean $(SOLUTION) --verbosity quiet
	@find . -type d \( -name bin -o -name obj \) -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean complete."

#format: @ Auto-fix code formatting
format: deps
	@dotnet format $(SOLUTION)

#lint: @ Check code style and compiler warnings (format verify + warnings-as-errors)
lint: deps
	@dotnet format $(SOLUTION) --verify-no-changes --verbosity diagnostic
	@dotnet build $(SOLUTION) -warnaserror --nologo -v q

#vulncheck: @ Check for vulnerable NuGet packages
vulncheck: deps
	@set -euo pipefail; \
	OUTPUT=$$(dotnet list $(SOLUTION) package --vulnerable --include-transitive 2>&1); \
	echo "$$OUTPUT"; \
	if echo "$$OUTPUT" | grep -q 'has the following vulnerable packages'; then \
		echo "ERROR: Vulnerable packages found (see above)."; \
		exit 1; \
	fi

#trivy-fs: @ Trivy filesystem scan (vuln, secret, misconfig)
trivy-fs: deps-docker
	@echo "Running Trivy filesystem scan..."
	@docker run --rm -v "$$PWD:/src" ghcr.io/aquasecurity/trivy:$(TRIVY_VERSION) \
		fs --scanners vuln,secret,misconfig \
		--severity HIGH,CRITICAL \
		--skip-dirs '**/bin,**/obj' \
		--ignorefile /src/.trivyignore \
		--exit-code 1 --no-progress /src

#secrets: @ Scan for committed secrets with gitleaks
secrets: deps-docker
	@echo "Running gitleaks secret scan..."
	@docker run --rm -v "$$PWD:/repo" ghcr.io/gitleaks/gitleaks:v$(GITLEAKS_VERSION) \
		detect --source /repo --redact --no-banner

#mermaid-lint: @ Validate Mermaid diagrams in markdown files
mermaid-lint: deps-docker
	@set -euo pipefail; \
	IMAGE="minlag/mermaid-cli:$(MERMAID_CLI_VERSION)"; \
	for attempt in 1 2 3; do \
		if docker pull --quiet "$$IMAGE" >/dev/null 2>&1; then break; fi; \
		if [ "$$attempt" -eq 3 ]; then echo "ERROR: failed to pull $$IMAGE after 3 attempts"; exit 1; fi; \
		echo "Pull attempt $$attempt failed; retrying in $$((attempt * 5))s..."; \
		sleep $$((attempt * 5)); \
	done; \
	MD_FILES=$$(git ls-files '*.md' 2>/dev/null | xargs grep -lF '```mermaid' 2>/dev/null || true); \
	if [ -z "$$MD_FILES" ]; then \
		echo "No Mermaid blocks found — skipping."; \
		exit 0; \
	fi; \
	FAILED=0; \
	for md in $$MD_FILES; do \
		echo "Validating Mermaid blocks in $$md..."; \
		LOG=$$(mktemp); \
		if docker run --rm -v "$$PWD:/data:ro" \
			"$$IMAGE" \
			-i "/data/$$md" -o "/tmp/$$(basename $$md .md).svg" >"$$LOG" 2>&1; then \
			echo "  ✓ All blocks rendered cleanly."; \
		else \
			echo "  ✗ Parse error in $$md:"; \
			sed 's/^/    /' "$$LOG"; \
			FAILED=$$((FAILED + 1)); \
		fi; \
		rm -f "$$LOG"; \
	done; \
	if [ "$$FAILED" -gt 0 ]; then \
		echo "Mermaid lint: $$FAILED file(s) had parse errors."; \
		exit 1; \
	fi

#license-check: @ Verify every source file carries an SPDX-License-Identifier header
license-check:
	@set -euo pipefail; \
	MISSING=0; \
	for f in $$(git ls-files '*.cs' '*.sh' Dockerfile '*/Dockerfile' Makefile 2>/dev/null); do \
		if [ -f "$$f" ] && ! head -2 "$$f" | grep -qF 'SPDX-License-Identifier'; then \
			echo "MISSING SPDX header: $$f"; \
			MISSING=$$((MISSING + 1)); \
		fi; \
	done; \
	if [ "$$MISSING" -gt 0 ]; then \
		echo "License check failed: $$MISSING file(s) missing SPDX header."; \
		exit 1; \
	fi; \
	echo "License check passed: all tracked source files carry an SPDX header."

#check-dotnet-alignment: @ Verify .NET major.minor matches across global.json and both Dockerfiles
check-dotnet-alignment:
	@set -euo pipefail; \
	GJ="$(DOTNET_VERSION)"; \
	if [ -z "$$GJ" ]; then echo "ERROR: could not derive .NET version from global.json"; exit 1; fi; \
	FAIL=0; \
	for df in producer/Dockerfile consumer/Dockerfile; do \
		DV=$$(awk -F= '/^ARG DOTNET_VERSION=/{print $$2; exit}' "$$df"); \
		if [ "$$DV" != "$$GJ" ]; then \
			echo "MISMATCH: $$df has ARG DOTNET_VERSION=$$DV but global.json pins $$GJ"; \
			FAIL=1; \
		fi; \
	done; \
	if [ "$$FAIL" -ne 0 ]; then \
		echo "ERROR: .NET version drift across global.json and Dockerfiles."; exit 1; \
	fi; \
	echo ".NET version aligned ($$GJ) across global.json + producer/consumer Dockerfiles."

#static-check: @ Composite quality gate (check-dotnet-alignment + lint + license-check + vulncheck + trivy-fs + secrets + mermaid-lint + deps-prune-check)
static-check: check-dotnet-alignment lint license-check vulncheck trivy-fs secrets mermaid-lint deps-prune-check
	@echo "All static checks passed."

#build: @ Restore and build entire solution
build: deps
	@dotnet restore $(SOLUTION)
	@dotnet build $(SOLUTION)

#test: @ Run unit tests (Category=Unit)
test: deps
	@dotnet run --project tests/tests.csproj -- --treenode-filter "/*/*/*/*[Category=Unit]"

#integration-test: @ Run integration tests (Category=Integration, in-process WebApplicationFactory)
integration-test: deps
	@dotnet run --project tests/tests.csproj -- --treenode-filter "/*/*/*/*[Category=Integration]"

#coverage-check: @ Run full test suite with code coverage and enforce 80% threshold
coverage-check: deps
	@set -euo pipefail; \
	rm -rf $(COVERAGE_DIR); \
	mkdir -p $(COVERAGE_DIR); \
	dotnet run --project tests/tests.csproj -- \
		--coverage \
		--coverage-output-format cobertura \
		--coverage-output $(COVERAGE_FILE) \
		--results-directory $(COVERAGE_DIR); \
	COV_XML="$(COVERAGE_DIR)/$(COVERAGE_FILE)"; \
	if [ ! -f "$$COV_XML" ]; then echo "ERROR: coverage report not produced at $$COV_XML"; exit 1; fi; \
	RATE=$$(grep -oP '^<coverage line-rate="\K[0-9.]+' "$$COV_XML" | head -1); \
	if [ -z "$$RATE" ]; then echo "ERROR: could not parse line-rate from $$COV_XML"; exit 1; fi; \
	echo "Line coverage: $$RATE (threshold: $(COVERAGE_MIN))"; \
	awk -v r="$$RATE" -v t="$(COVERAGE_MIN)" 'BEGIN{ if (r+0 >= t+0) exit 0; exit 1 }' || \
		{ echo "ERROR: coverage $$RATE is below threshold $(COVERAGE_MIN)"; exit 1; }; \
	echo "Coverage check passed."

#update: @ Update NuGet packages to latest versions
update: deps
	@set -euo pipefail; \
	for proj in common consumer producer tests; do \
		echo "Updating packages in $$proj..."; \
		( cd "$$proj" && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package ); \
	done

#run: @ Build, stop previous, and run both apps via Dapr
run: deps-run build stop
	@dapr run -f .

#post: @ Send test messages to producer (requires make run)
post: deps
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "a1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "1"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "b1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "2"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "0"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z"}'
	@curl -X POST http://localhost:5232/sendasbytes -H "Content-Type: application/json" -d '{"id": "b2cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-27T02:52:04.835Z", "type": "1"}'

#stop-dapr: @ Stop Dapr multi-app run
stop-dapr:
	@dapr stop -f .

#stop-apps: @ Kill processes on known ports (usage: make stop-apps PORTS="5231 5232 ...")
stop-apps:
	@set -euo pipefail; \
	if [ -z "$(PORTS)" ]; then \
		echo "Usage: make stop-apps PORTS=\"<port1> <port2> ...\""; \
	else \
		for PORT in $(PORTS); do \
			echo "Checking for processes using port $$PORT..."; \
			if PIDS=$$(lsof -t -i:$$PORT 2>/dev/null) && [ -n "$$PIDS" ]; then \
				echo "Found processes using port $$PORT: $$PIDS"; \
				kill -9 $$PIDS; \
				echo "Processes on port $$PORT killed."; \
			else \
				echo "No processes found using port $$PORT."; \
			fi; \
		done; \
	fi

#stop: @ Stop Dapr and kill processes on known ports
stop: stop-dapr stop-apps
	@echo "All stopped."

#kafka-start: @ Start Kafka stack (KRaft mode, foreground)
kafka-start: deps deps-docker
	@docker compose --file compose/kafka-only.yml up

#kafka-stop: @ Stop Kafka stack and remove volumes
kafka-stop:
	@docker compose --file compose/kafka-only.yml down --remove-orphans --volumes

#ci: @ Run full CI pipeline (static-check, build, test, integration-test, coverage-check)
ci: static-check build test integration-test coverage-check
	@echo "CI pipeline passed."

#dapr-init: @ Initialize Dapr with pinned runtime version (idempotent)
dapr-init: deps-run
	@set -euo pipefail; \
	INSTALLED=$$(dapr --version 2>/dev/null | awk -F': ' '/Runtime version/ {gsub(/^v/, "", $$2); print $$2}'); \
	if [ "$$INSTALLED" = "$(DAPR_RUNTIME_VERSION)" ]; then \
		echo "Dapr runtime $(DAPR_RUNTIME_VERSION) already installed."; \
	else \
		echo "Installing Dapr runtime $(DAPR_RUNTIME_VERSION) (current: $${INSTALLED:-none})..."; \
		dapr uninstall --all 2>/dev/null || true; \
		dapr init --runtime-version $(DAPR_RUNTIME_VERSION); \
	fi

#image-build: @ Build producer and consumer Docker images (used by e2e)
image-build: deps-docker
	@docker compose --file compose/docker-compose.yml build producer consumer

#image-test: @ Run container-structure-test against the built images (Dockerfile-contract assertions)
image-test: deps-docker deps-tools image-build
	@set -euo pipefail; \
	for svc in producer consumer; do \
		echo "Testing dapr-dotnet-pub-sub-$$svc:e2e..."; \
		container-structure-test test \
			--image "dapr-dotnet-pub-sub-$$svc:e2e" \
			--config "compose/structure-test/$$svc.yaml"; \
	done

#image-scan: @ Trivy scan the built producer + consumer images (HIGH,CRITICAL, fixed-only)
image-scan: deps-docker image-build
	@set -euo pipefail; \
	for IMAGE in dapr-dotnet-pub-sub-producer:e2e dapr-dotnet-pub-sub-consumer:e2e; do \
		echo "Scanning $$IMAGE..."; \
		docker run --rm \
			-v /var/run/docker.sock:/var/run/docker.sock \
			ghcr.io/aquasecurity/trivy:$(TRIVY_VERSION) \
			image \
			--severity HIGH,CRITICAL \
			--ignore-unfixed \
			--exit-code 1 \
			--no-progress \
			"$$IMAGE"; \
	done; \
	echo "Image scan passed: no fixed HIGH/CRITICAL vulnerabilities in producer/consumer images."

#e2e: @ Run Compose-based e2e (Kafka + producer/consumer + Dapr sidecars in containers)
e2e: deps-docker image-build
	@bash scripts/e2e-compose.sh

#kind-up: @ Create KinD cluster with Dapr + Kafka + producer/consumer (uses cloud-provider-kind for LoadBalancer)
kind-up: deps-docker deps-tools image-build
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) \
	 KIND_NODE_IMAGE=$(KIND_NODE_IMAGE) \
	 DAPR_HELM_VERSION=$(DAPR_HELM_VERSION) \
	 bash scripts/kind-up.sh

#kind-down: @ Tear down the KinD cluster + cloud-provider-kind (prunes kindccm-* orphans)
kind-down:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) bash scripts/kind-down.sh

#e2e-kind: @ Run K8s e2e against the KinD cluster (requires kind-up)
e2e-kind: deps-docker deps-tools
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) bash scripts/e2e-kind.sh

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@set -euo pipefail; \
	docker container prune -f 2>/dev/null || true; \
	GITHUB_TOKEN="$${GITHUB_TOKEN:-$$(gh auth token 2>/dev/null || true)}"; \
	if [ -z "$$GITHUB_TOKEN" ]; then \
		echo "ERROR: GITHUB_TOKEN unset and 'gh auth token' returned nothing."; \
		echo "       act's 'mise install' (aqua: backends) needs it to avoid GitHub's"; \
		echo "       60-req/hr anonymous API limit (HTTP 403). Run 'gh auth login' or export GITHUB_TOKEN."; \
		exit 1; \
	fi; \
	export GITHUB_TOKEN; \
	ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	EVENT_JSON=$$(mktemp -t act-event.XXXXXX.json); \
	trap 'rm -rf "$$ARTIFACT_PATH" "$$EVENT_JSON"' EXIT; \
	printf '{"ref":"refs/heads/main","repository":{"default_branch":"main","name":"$(APP_NAME)","full_name":"AndriyKalashnykov/$(APP_NAME)"}}\n' > "$$EVENT_JSON"; \
	echo "Using artifact server port $$ACT_PORT and path $$ARTIFACT_PATH"; \
	for j in changes static-check build test image-test image-scan e2e e2e-kind ci-pass; do \
		echo "==== act push --job $$j ===="; \
		act push --job "$$j" \
			--eventpath "$$EVENT_JSON" \
			-P ubuntu-latest=catthehacker/ubuntu:$(ACT_UBUNTU_VERSION) \
			--secret GITHUB_TOKEN \
			--container-architecture linux/amd64 \
			--pull=false \
			--artifact-server-port "$$ACT_PORT" \
			--artifact-server-path "$$ARTIFACT_PATH" || exit 1; \
	done

#release: @ Create a release tag (usage: make release VERSION=v1.2.3 or interactive)
release:
	@set -euo pipefail; \
	if [ -n "$(VERSION)" ]; then \
		NEW_TAG="$(VERSION)"; \
		case "$$NEW_TAG" in v*) ;; *) NEW_TAG="v$$NEW_TAG" ;; esac; \
	else \
		echo "Current tag: $(CURRENTTAG)"; \
		read -r -p "New tag (vX.Y.Z): " NEW_TAG; \
	fi; \
	if ! echo "$$NEW_TAG" | grep -qE '$(SEMVER_RE)'; then \
		echo "ERROR: tag must match vX.Y.Z (got: $$NEW_TAG)"; exit 1; \
	fi; \
	git tag -a "$$NEW_TAG" -m "Release $$NEW_TAG"; \
	read -r -p "Push $$NEW_TAG to origin? [y/N] " ANS; \
	case "$${ANS:-N}" in [yY]) git push origin "$$NEW_TAG" && echo "Pushed $$NEW_TAG." ;; *) echo "Tag created locally. Push with: git push origin $$NEW_TAG" ;; esac

#renovate-bootstrap: @ Install Node (via mise) for Renovate
renovate-bootstrap: deps-tools

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-docker deps-run deps-tools deps-act deps-prune deps-prune-check clean format lint \
        check-dotnet-alignment license-check vulncheck trivy-fs secrets mermaid-lint static-check build test integration-test \
        e2e e2e-kind kind-up kind-down image-build image-test image-scan coverage-check dapr-init update run post stop \
        stop-dapr stop-apps kafka-start kafka-stop ci ci-run release renovate-bootstrap renovate-validate
