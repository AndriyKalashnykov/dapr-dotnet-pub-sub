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
make deps-act                 # Install act for local CI (to ~/.local/bin)
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
make test                     # Run unit tests (TinyMessageDtoTests only)
make e2e                      # Run end-to-end tests (Producer/Consumer via WebApplicationFactory)
make coverage-check           # Run all tests with coverage and enforce 80% line threshold
make dapr-init                # Install pinned Dapr runtime (idempotent)
make update                   # Update NuGet packages to latest versions
make run                      # Build, stop previous, then run both apps via `dapr run -f .`
make post                     # Send test messages to producer (requires make run)
make stop                     # Stop Dapr + kill processes on known ports
make stop-dapr                # Stop Dapr multi-app run
make stop-apps PORTS="..."    # Kill processes on given ports
make kafka-start              # Start Kafka stack (KRaft mode, Kafka UI) — foreground
make kafka-stop               # Stop Kafka stack and remove volumes
make ci                       # Run full CI pipeline (static-check, build, test, e2e, coverage-check)
make ci-run                   # Run GitHub Actions workflow locally using act
make release VERSION=vX.Y.Z   # Create a semver-validated release tag
make renovate-bootstrap       # Install nvm and Node for Renovate
make renovate-validate        # Validate Renovate configuration
```

Build a single project: `dotnet build producer/producer.csproj` (the solution file is `dapr-dotnet-pub-sub.slnx`; `dotnet build` auto-discovers it at the repo root).

## Architecture

### Four projects in `dapr-dotnet-pub-sub.slnx`:

- **common/** -- Shared library (`OutputType: Library`). Contains `TinyMessage` record and `TinyMessageDto` with parsing/validation logic. Referenced by both apps.
- **producer/** -- ASP.NET Web API. Exposes `POST /send` (JSON publish) and `POST /sendasbytes` (byte publish). Uses `DaprClient.PublishEventAsync` to publish to the `message-pubsub-kafka` component on topic `incoming-messages`.
- **consumer/** -- ASP.NET Web API. Receives messages via Dapr subscription. Uses `CloudEvents` middleware and MVC controllers for subscription endpoint mapping.
- **tests/** -- TUnit test project. References common, producer, and consumer projects. `TinyMessageDtoTests` are unit tests (run via `make test`); `ProducerEndpointTests`, `ProducerPublishEndpointTests`, and `ConsumerEndpointTests` are end-to-end tests using `WebApplicationFactory<Program>` (run via `make e2e`). `ProducerPublishEndpointTests` replaces the real `DaprClient` with a FakeItEasy fake to exercise the `/send` and `/sendasbytes` publish paths without a running sidecar.

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

### Infrastructure (docker-compose-kafka.yml)

Kafka stack in KRaft mode (no Zookeeper): Kafka (:9092), Kafka UI (:9080).

## Tech Stack

- .NET 10 (pinned in `global.json` → `10.0.201`, `rollForward: latestFeature`)
- Dapr SDK: `Dapr.AspNetCore` 1.17.8
- Kafka as the message broker (Confluent images)
- Testing: TUnit 1.30.8 + FakeItEasy 9.0.1 + `Microsoft.AspNetCore.Mvc.Testing` 10.0.5
- CI: GitHub Actions — `static-check` → `build`/`test` (parallel) → `e2e`/`coverage` (parallel) → `ci-pass` gate job (single branch-protection check), plus weekly `cleanup-runs.yml` for old runs and caches
- Static analysis: `make static-check` composite gate bundles `lint`, `vulncheck`, `trivy-fs`, `secrets` (gitleaks), `mermaid-lint` (mermaid-cli), and `deps-prune-check`
- Coverage: `make coverage-check` runs the full test suite under `Microsoft.Testing.Extensions.CodeCoverage` and enforces an 80% line-rate threshold via cobertura output

## Upgrade Backlog

- [ ] TUnit daily releases generate frequent Renovate PRs — grouped under `TUnit` package rule; review if PR volume becomes disruptive
- [ ] **Add real-sidecar e2e test** — current `make e2e` uses `WebApplicationFactory` (in-process, bypasses Dapr sidecar). A Newman/curl test against `make run` + real Kafka would catch Dapr subscription routing regressions. Low priority for a demo project.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
