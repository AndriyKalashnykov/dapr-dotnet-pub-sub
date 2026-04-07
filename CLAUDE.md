# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr pub/sub demo with two .NET 10 microservices communicating via Kafka through the Dapr sidecar. The **producer** publishes `TinyMessage` events to a Kafka topic; the **consumer** receives them via Dapr's declarative subscription with content-based routing.

## Build & Run Commands

```bash
make help           # List available tasks
make deps           # Check required tool dependencies (dotnet)
make deps-run       # Check runtime dependencies (dotnet, docker, dapr)
make deps-act       # Install act for local CI
make clean          # Remove build artifacts
make format         # Auto-fix code formatting
make lint           # Check code style and compiler warnings
make build          # Restore + build entire solution
make test           # Run all tests (depends on deps)
make update         # Update NuGet packages to latest versions
make run            # Build, stop previous, then run both apps via `dapr run -f .`
make post           # Send test messages to producer (multiple types)
make stop           # Stop Dapr + kill processes on known ports
make stop-dapr      # Stop Dapr multi-app run
make stop-apps      # Kill processes running on known ports
make kafka-start    # Start Kafka stack (KRaft mode, Kafka UI)
make kafka-stop     # Stop Kafka stack
make vulncheck      # Check for vulnerable NuGet packages
make deps-prune     # Show redundant NuGet package references
make ci             # Run full CI pipeline (lint, test, build, deps-prune-check)
make ci-run         # Run GitHub Actions workflow locally using act
make release VERSION=X.Y.Z  # Create a semver-validated release tag
make renovate-bootstrap      # Install nvm and npm for Renovate
make renovate-validate       # Validate Renovate configuration
```

Build a single project: `dotnet build producer/producer.csproj`

## Architecture

### Four projects in `dapr-dotnet-pub-sub.slnx`:

- **common/** -- Shared library (`OutputType: Library`). Contains `TinyMessage` record and `TinyMessageDto` with parsing/validation logic. Referenced by both apps.
- **producer/** -- ASP.NET Web API. Exposes `POST /send` (JSON publish) and `POST /sendasbytes` (byte publish). Uses `DaprClient.PublishEventAsync` to publish to the `message-pubsub-kafka` component on topic `incoming-messages`.
- **consumer/** -- ASP.NET Web API. Receives messages via Dapr subscription. Uses `CloudEvents` middleware and MVC controllers for subscription endpoint mapping.
- **tests/** -- TUnit test project. References common, producer, and consumer projects. Contains unit and integration tests using FakeItEasy for mocking and `Microsoft.AspNetCore.Mvc.Testing` for web API testing.

### Message routing (declarative subscription)

Defined in `components/subscription.yaml` using Dapr v2alpha1 Subscription spec:
- `type == "1"` -> `POST /handletype1`
- `type == "2"` -> `POST /handletype2`
- default -> `POST /dafault-messagehandler` (note: intentional typo in route name)

### Dapr components (`components/` directory)

- `kafka.yaml` -- Kafka pubsub component (`message-pubsub-kafka`), broker at `localhost:9092`, scoped to producer + consumer
- `subscription.yaml` -- Declarative subscription with content-based routing rules
- `dapr.yaml` -- Dapr configuration (tracing, metrics)
- `dapr.yaml` -- Multi-app run template in project root (not in components/)

### Port assignments

| Service  | App Port | Dapr Sidecar Port |
|----------|----------|--------------------|
| producer | 5232     | 3532               |
| consumer | 5231     | 3531               |

### Infrastructure (docker-compose-kafka.yml)

Kafka stack in KRaft mode (no Zookeeper): Kafka (:9092), Kafka UI (:9080).

## Tech Stack

- .NET 10 (defined in `global.json`, `rollForward: latestFeature`)
- Dapr SDK: `Dapr.AspNetCore` 1.17.7
- Kafka as the message broker (Confluent images)
- CI: GitHub Actions -- static-check, test, build (`make lint`, `make test`, `make build`)

## Upgrade Backlog

- [x] ~~Monitor NSubstitute~~ — Migrated to FakeItEasy v9.0.1 (Apr 2026). FakeItEasy ships net10.0 TFM, has 4 open issues vs NSubstitute's 104, and better maintenance health.
- [ ] TUnit daily releases generate frequent Renovate PRs — grouped under `TUnit` package rule; review if PR volume becomes disruptive

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
