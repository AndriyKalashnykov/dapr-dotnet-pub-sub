# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr pub/sub demo with two .NET 10 microservices communicating via Kafka through the Dapr sidecar. The **producer** publishes `TinyMessage` events to a Kafka topic; the **consumer** receives them via Dapr's declarative subscription with content-based routing.

## Build & Run Commands

```bash
make help                     # List available tasks
make deps                     # Check required tool dependencies (dotnet, curl)
make deps-docker              # Check Docker is installed (for containerised scanners)
make deps-run                 # Check runtime dependencies (dotnet, curl, docker, dapr)
make deps-tools               # Install pinned tools (mise + Node, Dapr CLI, act per .mise.toml)
make deps-act                 # Alias for deps-tools (preserved for ci-run dependency chain)
make clean                    # Remove build artifacts
make format                   # Auto-fix code formatting
make lint                     # Check code style and compiler warnings
make vulncheck                # Check for vulnerable NuGet packages
make trivy-fs                 # Trivy filesystem scan (vuln, secret, misconfig)
make secrets                  # Scan for committed secrets with gitleaks
make mermaid-lint             # Validate Mermaid diagrams in markdown files
make deps-prune               # Show redundant NuGet package references
make deps-prune-check         # Verify no redundant NuGet package references
make static-check             # Composite gate: lint + vulncheck + trivy-fs + secrets + mermaid-lint + deps-prune-check
make build                    # Restore + build entire solution
make test                     # Run unit tests (Category=Unit, seconds)
make integration-test         # Run integration tests (Category=Integration, in-process WebApplicationFactory)
make coverage-check           # Run full suite with coverage and enforce 80% line threshold
make image-build              # Build producer + consumer Docker images (used by e2e)
make e2e                      # Run Compose-based e2e (Kafka + Dapr sidecars + producer/consumer as containers)
make kind-up                  # Create KinD cluster with Dapr + Kafka + apps + cloud-provider-kind
make kind-down                # Tear down KinD cluster + cloud-provider-kind orphans
make e2e-kind                 # Run K8s e2e against KinD LoadBalancer IP (requires kind-up)
make dapr-init                # Install pinned Dapr runtime (idempotent)
make update                   # Update NuGet packages to latest versions
make run                      # Build, stop previous, then run both apps via `dapr run -f .`
make post                     # Send test messages to producer (requires make run)
make stop                     # Stop Dapr + kill processes on known ports
make stop-dapr                # Stop Dapr multi-app run
make stop-apps PORTS="..."    # Kill processes on given ports
make kafka-start              # Start Kafka stack (KRaft mode, Kafka UI) — foreground
make kafka-stop               # Stop Kafka stack and remove volumes
make ci                       # Run full CI pipeline (static-check, build, test, integration-test, coverage-check)
make ci-run                   # Run GitHub Actions workflow locally using act
make release VERSION=vX.Y.Z   # Create a semver-validated release tag
make renovate-bootstrap       # Install Node (via mise) for Renovate
make renovate-validate        # Validate Renovate configuration
```

Build a single project: `dotnet build producer/producer.csproj` (the solution file is `dapr-dotnet-pub-sub.slnx`; `dotnet build` auto-discovers it at the repo root).

## Architecture

### Four projects in `dapr-dotnet-pub-sub.slnx`:

- **common/** -- Shared library (`OutputType: Library`). Contains `TinyMessage` record and `TinyMessageDto` with parsing/validation logic. Referenced by both apps.
- **producer/** -- ASP.NET Web API. Exposes `POST /send` (JSON publish) and `POST /sendasbytes` (byte publish). Uses `DaprClient.PublishEventAsync` to publish to the `message-pubsub-kafka` component on topic `incoming-messages`.
- **consumer/** -- ASP.NET Web API. Receives messages via Dapr subscription. Uses `CloudEvents` middleware and MVC controllers for subscription endpoint mapping.
- **tests/** -- TUnit test project. References common, producer, and consumer projects. Test classes are tagged with `[Category("Unit")]` or `[Category("Integration")]`; `make test` filters to Unit, `make integration-test` filters to Integration. `TinyMessageDtoTests` are unit tests; `ProducerEndpointTests`, `ProducerPublishEndpointTests`, `ProducerErrorPathTests`, and `ConsumerEndpointTests` are integration tests using `WebApplicationFactory<Program>`. `ProducerPublishEndpointTests` replaces the real `DaprClient` with a FakeItEasy fake to exercise the `/send` and `/sendasbytes` publish paths without a running sidecar. `ProducerErrorPathTests` verifies error handling (including `application/problem+json` Content-Type) when `DaprClient` throws. `ConsumerEndpointTests` covers both raw-JSON and `application/cloudevents+json` envelope paths.
- **scripts/** -- E2E orchestration. `e2e-compose.sh` brings up `compose/docker-compose.yml` (Kafka + Dapr sidecars + producer/consumer images), exercises the publish path, and asserts subscription routing via consumer-container log polling (types 1, 2, 0, 99 + bytes 1; type 99 covers the default-route fall-through). `kind-up.sh` / `kind-down.sh` / `e2e-kind.sh` do the K8s equivalent against a KinD cluster with cloud-provider-kind for LoadBalancer support.

### Message routing (declarative subscription)

Defined in `components/subscription.yaml` using Dapr v2alpha1 Subscription spec:
- `type == "1"` -> `POST /handletype1`
- `type == "2"` -> `POST /handletype2`
- default -> `POST /dafault-messagehandler` (note: intentional typo in route name)

### Dapr components (`components/` directory)

- `kafka.yaml` -- Kafka pubsub component (`message-pubsub-kafka`), broker at `localhost:9092`, scoped to producer + consumer
- `subscription.yaml` -- Declarative subscription with content-based routing rules
- `dapr.yaml` -- Dapr configuration (tracing, metrics)

### Multi-app run template

The root-level `dapr.yaml` (not in `components/`) is the multi-app run template consumed by `dapr run -f .`.

### Port assignments

| Service  | App Port | Dapr Sidecar Port |
|----------|----------|--------------------|
| producer | 5232     | 3532               |
| consumer | 5231     | 3531               |

### Infrastructure

`compose/kafka-only.yml` runs Kafka in KRaft mode (no Zookeeper) for `make run` (Dapr-CLI multi-app flow): Kafka (:9092), Kafka UI (:9080). The full app+sidecar Compose stack used by `make e2e` lives in `compose/docker-compose.yml`.

## Tech Stack

- .NET 10 (pinned in `global.json` → `10.0.201`, `rollForward: latestFeature`)
- Dapr SDK: `Dapr.AspNetCore` 1.17.8
- Kafka as the message broker (Confluent images)
- Testing: TUnit 1.31.0 + FakeItEasy 9.0.1 + `Microsoft.AspNetCore.Mvc.Testing` 10.0.5
- CI: GitHub Actions — `changes` (path-filter gate) → `static-check` → `build`/`test` (parallel) → `e2e`/`e2e-kind` (parallel) → `ci-pass` gate job (single branch-protection check), plus weekly `cleanup-runs.yml` for old runs and caches. The `test` job runs `make coverage-check` (all Unit + Integration tests + 80% line threshold + cobertura artifact upload). The `e2e` job builds producer/consumer images and runs `scripts/e2e-compose.sh` against the full Compose stack (Kafka + Dapr sidecars). The `e2e-kind` job brings up a KinD cluster with cloud-provider-kind + Helm-installed Dapr + Kafka manifest and asserts subscription delivery through the producer's LoadBalancer IP.
- Static analysis: `make static-check` composite gate bundles `lint`, `vulncheck`, `trivy-fs`, `secrets` (gitleaks), `mermaid-lint` (mermaid-cli), and `deps-prune-check`
- Coverage: `make coverage-check` runs the full test suite under `Microsoft.Testing.Extensions.CodeCoverage` and enforces an 80% line-rate threshold via cobertura output
- Tool management: `.mise.toml` pins Node, Dapr CLI, and act — Renovate's `mise` manager tracks these natively. Remaining Makefile `_VERSION` constants (`DAPR_RUNTIME_VERSION`, `TRIVY_VERSION`, `GITLEAKS_VERSION`, `MERMAID_CLI_VERSION`) are tracked via inline `# renovate:` comments and the `custom.regex` manager.

### CI / act gap

`make ci-run` exercises the GitHub Actions workflow via [act](https://github.com/nektos/act). Two notes:

- The `Upload coverage report` step inside the `test` job is gated `if: always() && env.ACT != 'true'` because act's artifact server rejects the v7 uploader's `mime_type` field. The step runs normally on GitHub-hosted runners.
- A green `make ci-run` therefore does NOT exercise artifact upload — confirm on a real GitHub run before relying on the cobertura report being published.

## Upgrade Backlog

- [x] **Dockerize e2e: replace `dapr run -f .` with Docker Compose** — `compose/docker-compose.yml` brings up Kafka + Dapr sidecars (`network_mode: service:<app>`) + producer/consumer as containers; `scripts/e2e-compose.sh` asserts subscription routing via consumer-container log polling. `make image-build` builds the images; `make e2e` runs the full flow. The legacy `dapr run -f .` log-grep approach has been removed entirely.
- [x] **K8s e2e: deploy to KinD + cloud-provider-kind and run tests** — `k8s/` manifests cover namespace, Kafka (KRaft StatefulSet using `confluentinc/cp-kafka`), Dapr Component + Subscription CRDs, and producer/consumer Deployments with `dapr.io/enabled` annotations. `scripts/kind-up.sh` creates the cluster, starts host cloud-provider-kind, installs Dapr via Helm, applies manifests, and waits for the producer LoadBalancer route. `scripts/e2e-kind.sh` asserts via `kubectl logs` polling. The `e2e-kind` CI job runs alongside `e2e` (Compose).

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
