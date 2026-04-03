.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Tool versions
# ---------------------------------------------------------------------------
DOTNET_VERSION     := 10.0
DAPR_VERSION       := 1.17.7
DOCKER_MIN_VERSION := 20.10
NVM_VERSION        := 0.40.4
ACT_VERSION        := 0.2.87

# ---------------------------------------------------------------------------
# Project constants
# ---------------------------------------------------------------------------
APP_NAME   := dapr-dotnet-pub-sub
CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
SOLUTION   := dapr-dotnet-pub-sub.sln
PORTS    := "3530,3531,3532,5230,5231,5232,7006,7007"
SEMVER_RE := ^[0-9]+\.[0-9]+\.[0-9]+$$

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#deps: @ Check required tool dependencies
deps:
	@command -v dotnet >/dev/null 2>&1 || { echo "ERROR: dotnet is not installed (need $(DOTNET_VERSION)+)"; exit 1; }

#deps-run: @ Check runtime dependencies (dotnet, docker, dapr)
deps-run: deps
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed (need $(DOCKER_MIN_VERSION)+)"; exit 1; }
	@command -v dapr   >/dev/null 2>&1 || { echo "ERROR: dapr CLI is not installed"; exit 1; }

#deps-act: @ Install act for local CI
deps-act:
	@command -v dotnet >/dev/null 2>&1 || { echo "ERROR: dotnet is not installed (need $(DOTNET_VERSION)+)"; exit 1; }
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#clean: @ Remove build artifacts
clean:
	@dotnet clean $(SOLUTION) --verbosity quiet
	@echo "Clean complete."

#format: @ Auto-fix code formatting
format: deps
	@dotnet format $(SOLUTION)

#lint: @ Run dotnet format to check code style
lint: deps
	@dotnet format $(SOLUTION) --verify-no-changes --verbosity diagnostic

#build: @ Restore and build entire solution
build: deps
	@dotnet restore $(SOLUTION)
	@dotnet build $(SOLUTION)

#test: @ Run all tests
test: build
	@dotnet test $(SOLUTION) --no-build

#update: @ Update NuGet packages to latest versions
update: build test
	@cd consumer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package
	@cd producer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package

#run: @ Build, stop previous, and run both apps via Dapr
run: deps-run build stop
	@dapr run -f .

#post: @ Send test messages to producer
post:
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "a1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "1"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "b1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "2"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "0"}'
	@curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z"}'
	@curl -X POST http://localhost:5232/sendasbytes -H "Content-Type: application/json" -d '{"id": "b2cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-27T02:52:04.835Z", "type": "1"}'

#stop-dapr: @ Stop Dapr multi-app run
stop-dapr:
	@dapr stop -f .

#stop-apps: @ Kill processes running on known ports
stop-apps:
	@if [ -z "$(PORTS)" ]; then \
		echo "Usage: make stop-apps PORTS=\"<port1> <port2> <port3> ...\""; \
	else \
		for PORT in $(PORTS); do \
			echo "Checking for processes using port $$PORT..."; \
			if PIDS=$$(lsof -t -i:$$PORT) && [ -n "$$PIDS" ]; then \
				echo "Found processes using port $$PORT: $$PIDS"; \
				echo "Killing processes..."; \
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

#kafka-start: @ Start Kafka stack
kafka-start: deps-run
	@docker compose --file docker-compose-kafka.yml up

#kafka-stop: @ Stop Kafka stack
kafka-stop:
	@docker compose --file docker-compose-kafka.yml down --remove-orphans --volumes

#ci: @ Run full CI pipeline (lint, build, test)
ci: deps lint build test
	@echo "CI pipeline passed."

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#release: @ Create a release tag (usage: make release VERSION=1.0.0)
release:
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION is required. Usage: make release VERSION=1.0.0"; \
		exit 1; \
	fi
	@echo "$(VERSION)" | grep -qE '$(SEMVER_RE)' || { echo "ERROR: VERSION=$(VERSION) is not valid semver (expected X.Y.Z)"; exit 1; }
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Tagged v$(VERSION). Push with: git push origin v$(VERSION)"

#renovate-bootstrap: @ Install nvm and npm for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install --lts; \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@npx --yes renovate --platform=local

.PHONY: help deps deps-run deps-act clean format lint build test update run post stop stop-dapr stop-apps \
        kafka-start kafka-stop ci ci-run release renovate-bootstrap renovate-validate
