.DEFAULT_GOAL := help

# Use bash for recipe execution (dash lacks `set -o pipefail`)
SHELL := /bin/bash

# Ensure user-local binaries are on PATH (for tools installed by deps-act)
export PATH := $(HOME)/.local/bin:$(PATH)

# ---------------------------------------------------------------------------
# Tool versions
# ---------------------------------------------------------------------------
# .NET SDK version derived from global.json (single source of truth)
DOTNET_VERSION     := $(shell awk -F'"' '/"version"/{split($$4,v,"."); print v[1]"."v[2]; exit}' global.json 2>/dev/null)
# Node version derived from .nvmrc (single source of truth)
NODE_VERSION       := $(shell cat .nvmrc 2>/dev/null || echo 24)
# renovate: datasource=github-releases depName=dapr/cli extractVersion=^v(?<version>.*)$
DAPR_CLI_VERSION     := 1.17.1
# renovate: datasource=github-releases depName=dapr/dapr extractVersion=^v(?<version>.*)$
DAPR_RUNTIME_VERSION := 1.17.4
# renovate: datasource=github-releases depName=nvm-sh/nvm extractVersion=^v(?<version>.*)$
NVM_VERSION        := 0.40.4
# renovate: datasource=github-releases depName=nektos/act extractVersion=^v(?<version>.*)$
ACT_VERSION        := 0.2.87
# renovate: datasource=github-releases depName=aquasecurity/trivy extractVersion=^v(?<version>.*)$
TRIVY_VERSION      := 0.69.3
# renovate: datasource=github-releases depName=gitleaks/gitleaks extractVersion=^v(?<version>.*)$
GITLEAKS_VERSION   := 8.30.1
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

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
deps-run: deps deps-docker
	@command -v dapr   >/dev/null 2>&1 || { echo "ERROR: dapr CLI is not installed (need $(DAPR_CLI_VERSION)+)"; exit 1; }

#deps-act: @ Install act for local CI (to ~/.local/bin)
deps-act: deps
	@set -euo pipefail; \
	if ! command -v act >/dev/null 2>&1; then \
		echo "Installing act $(ACT_VERSION) to $$HOME/.local/bin..."; \
		mkdir -p "$$HOME/.local/bin"; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh \
			| bash -s -- -b "$$HOME/.local/bin" v$(ACT_VERSION); \
	fi

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
		--exit-code 1 --no-progress /src

#secrets: @ Scan for committed secrets with gitleaks
secrets: deps-docker
	@echo "Running gitleaks secret scan..."
	@docker run --rm -v "$$PWD:/repo" ghcr.io/gitleaks/gitleaks:v$(GITLEAKS_VERSION) \
		detect --source /repo --redact --no-banner

#mermaid-lint: @ Validate Mermaid diagrams in markdown files
mermaid-lint: deps-docker
	@set -euo pipefail; \
	MD_FILES=$$(git ls-files '*.md' 2>/dev/null | xargs grep -lF '```mermaid' 2>/dev/null || true); \
	if [ -z "$$MD_FILES" ]; then \
		echo "No Mermaid blocks found — skipping."; \
		exit 0; \
	fi; \
	FAILED=0; \
	for md in $$MD_FILES; do \
		echo "Validating Mermaid blocks in $$md..."; \
		LOG=$$(mktemp); \
		if docker run --rm -v "$$PWD:/data" \
			minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
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

#static-check: @ Composite quality gate (lint + vulncheck + trivy-fs + secrets + mermaid-lint + deps-prune-check)
static-check: lint vulncheck trivy-fs secrets mermaid-lint deps-prune-check
	@echo "All static checks passed."

#build: @ Restore and build entire solution
build: deps
	@dotnet restore $(SOLUTION)
	@dotnet build $(SOLUTION)

#test: @ Run unit tests (TinyMessageDto only)
test: deps
	@dotnet run --project tests/tests.csproj -- --treenode-filter "/*/*/TinyMessageDtoTests/*"

#e2e: @ Run end-to-end tests (Producer/Consumer via WebApplicationFactory)
e2e: deps
	@dotnet run --project tests/tests.csproj -- --treenode-filter "/*/*/*EndpointTests/*"

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
kafka-start: deps-run
	@docker compose --file docker-compose-kafka.yml up

#kafka-stop: @ Stop Kafka stack and remove volumes
kafka-stop:
	@docker compose --file docker-compose-kafka.yml down --remove-orphans --volumes

#ci: @ Run full CI pipeline (static-check, build, test, e2e, coverage-check)
ci: static-check build test e2e coverage-check
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

DAPR_LOG := /tmp/dapr-e2e.log

#e2e-sidecar: @ Run real-sidecar e2e tests (starts Kafka + Dapr, tests full pub/sub pipeline)
e2e-sidecar: deps-run build dapr-init
	@set -euo pipefail; \
	cleanup() { \
		echo "Cleaning up..."; \
		dapr stop -f . 2>/dev/null || true; \
		for PORT in $(PORTS); do \
			lsof -t -i:$$PORT 2>/dev/null | xargs -r kill -9 2>/dev/null || true; \
		done; \
		docker compose --file docker-compose-kafka.yml down --remove-orphans --volumes 2>/dev/null || true; \
	}; \
	trap cleanup EXIT; \
	echo "=== Starting Kafka in background ==="; \
	docker compose --file docker-compose-kafka.yml up -d; \
	echo "Waiting for Kafka broker (healthcheck)..."; \
	for i in $$(seq 1 40); do \
		if docker compose --file docker-compose-kafka.yml exec -T kafka \
			kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then \
			echo "Kafka is ready."; break; \
		fi; \
		sleep 3; \
	done; \
	echo "=== Starting producer + consumer via Dapr ==="; \
	dapr run -f . > $(DAPR_LOG) 2>&1 & \
	echo "Waiting for producer on :5232..."; \
	for i in $$(seq 1 60); do \
		curl -sf http://localhost:5232/dapr/config >/dev/null 2>&1 && break; \
		sleep 2; \
	done; \
	echo "Waiting for consumer on :5231..."; \
	for i in $$(seq 1 60); do \
		STATUS=$$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5231/ 2>/dev/null); \
		[ "$$STATUS" != "000" ] && break; \
		sleep 2; \
	done; \
	echo "=== Services ready — running e2e sidecar tests ==="; \
	DAPR_LOG=$(DAPR_LOG) bash e2e/e2e-sidecar.sh

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

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

#renovate-bootstrap: @ Install nvm and Node for Renovate
renovate-bootstrap:
	@set -euo pipefail; \
	if ! command -v node >/dev/null 2>&1; then \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install $(NODE_VERSION); \
	fi

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-docker deps-run deps-act deps-prune deps-prune-check clean format lint \
        vulncheck trivy-fs secrets mermaid-lint static-check build test e2e coverage-check \
        dapr-init update run post stop stop-dapr stop-apps kafka-start kafka-stop ci e2e-sidecar ci-run \
        release renovate-bootstrap renovate-validate
