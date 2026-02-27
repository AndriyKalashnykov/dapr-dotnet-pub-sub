# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr pub/sub demo with two .NET 10 microservices communicating via Kafka through the Dapr sidecar. The **producer** publishes `TinyMessage` events to a Kafka topic; the **consumer** receives them via Dapr's declarative subscription with content-based routing.

## Build & Run Commands

```bash
make build          # Restore + build entire solution
make run            # Build, stop previous, then run both apps via `dapr run -f .`
make post           # Send test messages to producer (multiple types)
make stop           # Stop Dapr + kill processes on known ports
make runk           # Start Kafka stack (Zookeeper, Kafka, Kafka UI, Kafdrop)
make stopk          # Stop Kafka stack
```

Build a single project: `dotnet build producer/producer.csproj`

## Architecture

### Three projects in `dapr-dotnet-pub-sub.sln`:

- **common/** — Shared library (`OutputType: Library`). Contains `TinyMessage` record and `TinyMessageDto` with parsing/validation logic. Referenced by both apps.
- **producer/** — ASP.NET Web API. Exposes `POST /send` (JSON publish) and `POST /sendasbytes` (byte publish). Uses `DaprClient.PublishEventAsync` to publish to the `message-pubsub-kafka` component on topic `incoming-messages`.
- **consumer/** — ASP.NET Web API. Receives messages via Dapr subscription. Uses `CloudEvents` middleware and MVC controllers for subscription endpoint mapping.

### Message routing (declarative subscription)

Defined in `components/subscription.yaml` using Dapr v2alpha1 Subscription spec:
- `type == "1"` → `POST /handletype1`
- `type == "2"` → `POST /handletype2`
- default → `POST /dafault-messagehandler` (note: intentional typo in route name)

### Dapr components (`components/` directory)

- `kafka.yaml` — Kafka pubsub component (`message-pubsub-kafka`), broker at `localhost:9092`, scoped to producer + consumer
- `subscription.yaml` — Declarative subscription with content-based routing rules
- `redis-pubsub.yaml` — Redis pubsub component (unused, kept as alternative)
- `dapr.yaml` — Multi-app run template in project root (not in components/)

### Port assignments

| Service  | App Port | Dapr Sidecar Port |
|----------|----------|--------------------|
| producer | 5232     | 3532               |
| consumer | 5231     | 3531               |

### Infrastructure (docker-compose-kafka.yml)

Kafka stack: Zookeeper (:2181), Kafka (:9092), Kafka UI (:9080), Kafdrop (:9000).

## Tech Stack

- .NET 10 (defined in `global.json`, `rollForward: latestFeature`)
- Dapr SDK: `Dapr.AspNetCore` 1.16.1
- Kafka as the message broker (Confluent images)
- CI: GitHub Actions — build only (`make build`)
