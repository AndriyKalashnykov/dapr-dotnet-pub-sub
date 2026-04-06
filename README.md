[![CI](https://github.com/AndriyKalashnykov/dapr-dotnet-pub-sub/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-dotnet-pub-sub/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-dotnet-pub-sub.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-dotnet-pub-sub/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-dotnet-pub-sub)
# Dapr DotNet pub/sub

Dapr publish-subscribe demo with two .NET 10 microservices communicating via Kafka through the Dapr sidecar. The **producer** publishes `TinyMessage` events to a Kafka topic; the **consumer** receives them via Dapr's declarative subscription with content-based routing.

Visit [this](https://docs.dapr.io/developing-applications/building-blocks/pubsub/) link for more information about Dapr
and Pub-Sub.

## Quick Start

```bash
make deps         # verify required tools (dotnet)
make build        # restore and build the solution
make test         # run all tests
make kafka-start  # start Kafka in KRaft mode (in a separate terminal)
make run          # build and run both apps via Dapr
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Git](https://git-scm.com/) | 2.0+ | Version control |
| [.NET SDK](https://dotnet.microsoft.com/download) | 10.0+ | Build and run .NET projects |
| [Docker](https://www.docker.com/) | 20.10+ | Run Kafka infrastructure |
| [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) | 1.17.7+ | Sidecar-based pub/sub |
| [curl](https://curl.se/) | any | Send HTTP requests to APIs |

Install all required dependencies:

```bash
make deps
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Restore and build entire solution |
| `make test` | Run all tests |
| `make lint` | Check code style and compiler warnings |
| `make format` | Auto-fix code formatting |
| `make clean` | Remove build artifacts |
| `make run` | Build, stop previous, and run both apps via Dapr |
| `make post` | Send test messages to producer |
| `make update` | Update NuGet packages to latest versions |

### Dapr & Kafka

| Target | Description |
|--------|-------------|
| `make kafka-start` | Start Kafka stack |
| `make kafka-stop` | Stop Kafka stack |
| `make stop` | Stop Dapr and kill processes on known ports |
| `make stop-dapr` | Stop Dapr multi-app run |
| `make stop-apps` | Kill processes running on known ports |

### Code Quality

| Target | Description |
|--------|-------------|
| `make vulncheck` | Check for vulnerable NuGet packages |
| `make deps-prune` | Show redundant NuGet package references |
| `make deps-prune-check` | Verify no redundant NuGet package references |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Run full CI pipeline (lint, test, build, deps-prune-check) |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Utilities

| Target | Description |
|--------|-------------|
| `make help` | List available tasks |
| `make deps` | Check required tool dependencies (dotnet) |
| `make deps-run` | Check runtime dependencies (dotnet, docker, dapr) |
| `make deps-act` | Install act for local CI |
| `make release VERSION=X.Y.Z` | Create a release tag (usage: make release VERSION=1.0.0) |
| `make renovate-bootstrap` | Install nvm and npm for Renovate |
| `make renovate-validate` | Validate Renovate configuration |

## Run all apps with multi-app run template file

This section shows how to run both applications at once
using [multi-app run template files](https://docs.dapr.io/developing-applications/local-development/multi-app-dapr-run/multi-app-overview/)
with `dapr run -f .`. This enables to you test the interactions between multiple applications.

1. Open a new terminal window and run Kafka:

```bash
make kafka-start
```


2. Open a new terminal window and run consumer and producer:

```bash
make run
```

3. Send a message to the producer app:
```bash
curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "a1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "2"}'
```

The terminal console output should look similar to this:

```text
== APP - producer == info: Microsoft.AspNetCore.Hosting.Diagnostics[1]
== APP - producer ==       Request starting HTTP/1.1 POST http://localhost:5232/send - application/json 67
== APP - producer == Received request body: {
== APP - producer ==     "id": "a1cdd036-c529-4bf9-bd59-d7148ef9237d",
== APP - producer ==     "timeStamp": "2025-09-26T02:52:04.835Z",
== APP - producer ==     "type": "2"
== APP - producer == }
== APP - producer == info: Microsoft.AspNetCore.Routing.EndpointMiddleware[0]
== APP - producer ==       Executing endpoint 'HTTP: POST /send'
== APP - producer == Sent message a1cdd036-c529-4bf9-bd59-d7148ef9237d, timestamp: 9/26/2025 2:52:04 AM +00:00
== APP - producer == info: Microsoft.AspNetCore.Http.Result.AcceptedResult[1]
== APP - producer ==       Setting HTTP status code 202.
== APP - producer == info: Microsoft.AspNetCore.Http.Result.AcceptedResult[3]
== APP - producer ==       Writing value of type 'Guid' as Json.
== APP - consumer == Request received: POST /handletype2
== APP - producer == info: Microsoft.AspNetCore.Routing.EndpointMiddleware[1]
== APP - producer ==       Executed endpoint 'HTTP: POST /send'
== APP - producer == info: Microsoft.AspNetCore.Hosting.Diagnostics[2]
== APP - producer ==       Request finished HTTP/1.1 POST http://localhost:5232/send - 202 - application/json;+charset=utf-8 191.3736ms
== APP - consumer == Received message a1cdd036-c529-4bf9-bd59-d7148ef9237d, timestamp: 9/26/2025 2:52:04 AM +00:00
...
```

4. Stop and clean up application processes and Kafka

```bash
make stop
make kafka-stop
```

## Run a single app at a time with Dapr (Optional)

An alternative to running all or multiple applications at once is to run single apps one-at-a-time using multiple
`dapr run .. -- dotnet run` commands. This next section covers how to do this.

### Run Dotnet message subscriber with Dapr

1. Run the Dotnet subscriber app with Dapr:

```bash
cd ./consumer
dapr run --app-id consumer --app-port 5231 --components-path ../components dotnet run
```

### Run Dotnet message publisher with Dapr

1. Run the Dotnet publisher app with Dapr:

```bash
cd ./producer
dapr run --app-id producer --app-port 5232 --components-path ../components dotnet run
```

2. Stop and clean up application processes

```bash
dapr stop --app-id consumer
dapr stop --app-id producer
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests. The pipeline enforces code style with `dotnet format`, builds the solution, and runs TUnit tests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **static-check** | push, PR, tags | Code style and compiler warnings via `make lint` |
| **test** | after static-check | Run TUnit tests via `make test` |
| **build** | after static-check | Restore and build via `make build`, verify no redundant packages |

Test and build run in parallel after static-check passes (fail-fast).

The `Cleanup old workflow runs` workflow runs weekly to delete runs older than 7 days.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.
