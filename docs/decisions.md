# Architecture Decisions

Non-obvious decisions and traps documented for the next contributor. Each entry names the **decision**, the **alternative that was rejected**, and the **failure mode** that drove the choice.

## ADR-001 — Kafka in K8s: `enableServiceLinks: false`

**Decision.** The Kafka StatefulSet pod (`k8s/kafka.yaml`) sets `spec.enableServiceLinks: false`.

**Rejected.** Default K8s service-discovery env injection (the implicit behaviour).

**Failure mode.** Kubernetes auto-injects env vars of the form `<UPPERCASE_SERVICE>_PORT=tcp://<ip>:<port>` for every Service in the pod's namespace. `confluentinc/cp-kafka`'s entrypoint translates `KAFKA_*` env vars into broker config: the auto-injected `KAFKA_PORT=tcp://10.96.x.x:9092` collides with cp-kafka's env-prefix translation and aborts the container at the `===> Configuring ...` stage with no diagnostic beyond `port is deprecated`. Disabling service links scopes the pod to its own ConfigMap-style env vars only.

**Reproducing.** Remove the `enableServiceLinks: false` line and run `make kind-up`; the kafka pod's `kubectl logs` stops at "Configuring..." and the pod stays in `CrashLoopBackOff`.

## ADR-002 — Kafka in K8s: hand-written manifest, not Bitnami chart

**Decision.** Kafka is deployed via a hand-written StatefulSet using `confluentinc/cp-kafka:8.2.0` (same image as `compose/docker-compose.yml`).

**Rejected.** The Bitnami `oci://registry-1.docker.io/bitnamicharts/kafka` Helm chart (version 32.4.3 at time of investigation).

**Failure mode.** The chart's default values reference `docker.io/bitnami/kafka:4.0.0-debian-12-r10`, which Bitnami removed from Docker Hub. Pulls 404. Overriding `image.repository` is possible but the chart's templates also assume Bitnami-specific config conventions that diverge from `cp-kafka`'s entrypoint contract. Maintaining a 50-line StatefulSet is cheaper than maintaining override values against a moving chart.

**Reproducing.** Roll back `scripts/kind-up.sh` to the `helm upgrade --install kafka oci://...bitnami/kafka` call; kind-up fails on `helm install` because the kafka controller pod loops on `ImagePullBackOff`.

## ADR-003 — Kafka pubsub: `initialOffset: oldest`

**Decision.** Both Dapr Kafka pubsub components (`components/kafka.yaml`, `compose/components/pubsub.yaml`, `k8s/pubsub.yaml`) set `initialOffset: "oldest"`.

**Rejected.** Dapr's default of `"newest"`.

**Failure mode.** The e2e script publishes a batch of messages, then polls the consumer's stdout for delivery. With `initialOffset: newest`, the consumer's Kafka consumer group can join AFTER the publisher writes — any messages already on the topic are skipped, polling times out, e2e fails. Race-prone even with healthchecks, because `docker compose --wait` returns when the broker port is open, not when the consumer-group rebalance has completed.

**Trade-off.** `oldest` means a long-running consumer that restarts re-reads the topic from offset 0. Acceptable for an e2e demo (topic is recreated each run); would not be acceptable in a long-lived production deployment, where the offset commit story handles this.

## ADR-004 — Producer `/sendasbytes`: explicit camelCase + `application/json`

**Decision.** `producer/Program.cs` serializes the `/sendasbytes` payload with `JsonSerializerDefaults.Web` (camelCase) and passes `dataContentType: "application/json"` to `daprClient.PublishByteEventAsync`.

**Rejected.** Default `JsonSerializer.SerializeToUtf8Bytes(message)` (PascalCase, no content-type).

**Failure mode.** Default System.Text.Json on a `TinyMessage` record produces `{"Id":...,"TimeStamp":...,"Type":"1"}`. The Dapr Subscription routing rule is `event.data.type == "1"` (lowercase). With PascalCase payload, the CEL evaluator errors `no such key: type` and the message is retried indefinitely; the consumer never sees it. The `PublishEventAsync` path (used by `/send`) doesn't hit this because Dapr's SDK camelCases the field names automatically; only the explicit-bytes path needs the workaround.

**Reproducing.** Remove the `bytePayloadOptions` argument; run `make e2e`; the `bytes type '1' -> /handletype1` assertion fails with `consumer never received` and `kubectl logs consumer-dapr` shows the `no such key: type` error.

## ADR-005 — Dapr sidecars in Compose: `network_mode: service:<app>`

**Decision.** Both `producer-dapr` and `consumer-dapr` services declare `network_mode: service:<app>`, sharing the producer/consumer container's network namespace.

**Rejected.** Putting daprd on the same Docker network as the apps, communicating via service DNS.

**Failure mode.** With separate netns, daprd would need to know the app's hostname (`producer:5232`) and the app would need to know daprd's hostname (`producer-dapr:3532`). Dapr's app↔sidecar contract assumes `localhost` resolution (`DAPR_HTTP_PORT=3532`, app talks to `http://localhost:3532`). Shared netns satisfies both directions: `daprd → http://localhost:5232 (the app)` and `app → http://localhost:3532 (daprd)`. This is also the Dapr canonical Compose pattern.

## ADR-006 — `cloud-provider-kind` as a host binary, not a container

**Decision.** `scripts/kind-up.sh` runs `cloud-provider-kind` as a backgrounded host binary (`nohup cloud-provider-kind &`).

**Rejected.** Running it as a Docker container on the `kind` network with `/var/run/docker.sock` mounted.

**Failure mode.** Container mode requires the container to be on the kind Docker network AND have docker.sock access; it works but adds two coupling points to track. Host binary mode is the project's canonical install (the kubernetes-sigs README recommends it), and `mise install` provisions it via `aqua:kubernetes-sigs/cloud-provider-kind`. `scripts/kind-down.sh` cleans up via `pkill -f cloud-provider-kind` + pruning `kindccm-*` envoy sidecar orphans.

**Trap covered.** `kindccm-*` containers (per-Service envoy sidecars created by cloud-provider-kind to expose LoadBalancer IPs) survive `kind delete cluster`. They hold IPs in the kind Docker subnet and the next `kind-up` inherits stale Envoy config pointed at dead pods. `kind-down.sh` runs `docker ps -aq --filter name=kindccm- | xargs -r docker rm -f` to prevent this.

## ADR-007 — KSV-0014 suppression for Kafka

**Decision.** `.trivyignore` lists `AVD-KSV-0014` (container should set `readOnlyRootFilesystem: true`) as suppressed for the Kafka StatefulSet.

**Rejected.** Mounting `/etc/kafka` as `emptyDir` to enable `readOnlyRootFilesystem`.

**Failure mode.** The `cp-kafka` entrypoint renders its `server.properties` into `/etc/kafka` at container start. Mounting an emptyDir over `/etc/kafka` shadows the baked-in startup scripts, and the container fails before reaching the config-write step. The cluster is e2e-only (no PII, no production traffic), so the readOnlyRootFilesystem hardening recommendation does not apply with the same urgency. Producer and consumer images DO set `readOnlyRootFilesystem: true` — only Kafka has the exception.

## ADR-008 — Cosign keyless OIDC, not GPG-signed images

**Decision.** The `docker` CI job signs every pushed digest with cosign **keyless** OIDC, using GitHub Actions's token as the identity proof. No long-lived signing key is stored in the repo or org secrets.

**Rejected.** GPG-signed images via cosign with a static private key stored as a GitHub secret.

**Failure mode of the alternative.** Long-lived signing keys are a high-value rotation target. A leaked key allows anyone to sign images and claim provenance from this workflow indefinitely. Keyless OIDC binds the signature to the specific workflow run via a Sigstore-issued short-lived certificate, with the Rekor transparency log as the audit trail.

**Trade-off.** Verification requires `--certificate-identity-regexp` pinned to this repo's workflow path AND `--certificate-oidc-issuer https://token.actions.githubusercontent.com`. Both flags are required — without the identity binding, anyone with access to GitHub Actions OIDC could sign an image and claim it came from here. The README documents the recipe; downstream consumers need to copy it.

## ADR-009 — Tag-push gating override in CI

**Decision.** Every heavy CI job's `if:` condition is `(needs.changes.outputs.code == 'true' || startsWith(github.ref, 'refs/tags/v'))`.

**Rejected.** Gating purely on `needs.changes.outputs.code == 'true'`.

**Failure mode.** A `v*` tag push commonly points at a SHA already on `main`. `dorny/paths-filter` with `base: main` then computes an empty diff for that tag-push event, sets `code: false`, and the docker job (which is what tags are FOR) gets skipped. The override lets tag pushes bypass the path-filter gate so versioned images always publish.

## ADR-010 — Per-cluster `kubectl --context=kind-<name>`

**Decision.** The Makefile declares `KUBECTL := kubectl --context=kind-$(KIND_CLUSTER_NAME)` and uses `$(KUBECTL)` in every recipe; shell scripts use a `KUBECTL=(kubectl --context="kind-${CLUSTER}")` array.

**Rejected.** Bare `kubectl ...` invocations relying on `~/.kube/config`'s current-context.

**Failure mode.** Two `make` invocations from sibling KinD-using projects share `~/.kube/config`. A bare `kubectl get pods` resolves to whichever cluster was most recently set as current-context globally — even though THIS project's `make kind-up` just created its own cluster. Namespaces "vanish", rollouts wait on non-existent Deployments, e2e tests confidently assert against the wrong cluster. Pinning `--context=kind-<name>` removes the ambiguity.

## ADR-011 — App-side OpenTelemetry, env-gated, alongside Dapr sidecar tracing

**Decision.** The producer and consumer add app-side OpenTelemetry (`AddAspNetCoreInstrumentation` + OTLP exporter) that exports their own HTTP server spans to the same Jaeger OTLP endpoint the Dapr sidecar uses. It is **gated on `OTEL_EXPORTER_OTLP_ENDPOINT`** (set in `compose/docker-compose.yml` and `k8s/*.yaml`, unset for the local `dapr run` flow). `service.name` mirrors the Dapr app-id, so app + sidecar spans share one Jaeger service.

**Rejected.** Relying solely on the Dapr sidecar's tracing.

**Failure mode.** Dapr only traces operations that flow through the sidecar (service-invocation, pub/sub). A direct request to the app's own HTTP endpoint (`POST /send`) never enters the sidecar's traced ingress, so it produced **zero** spans — the app's actual entry point was untraced. Empirically: 13 `/send` calls landed no app spans; a sidecar-API publish landed spans. App-side OTel traces the real `/send` and handler endpoints; the e2e (`scripts/e2e-*.sh`) drives the real `/send` and asserts a `producer` trace lands in Jaeger (two-stage `/api/services` + `/api/traces` check).

**Reproducing.** Unset `OTEL_EXPORTER_OTLP_ENDPOINT` on the producer, `make e2e`; the OTel trace assertion fails (no `producer` service in Jaeger from the app path).

## ADR-012 — No Docker `HEALTHCHECK` in the producer/consumer images

**Decision.** Neither `producer/Dockerfile` nor `consumer/Dockerfile` declares a `HEALTHCHECK`.

**Rejected.** Adding a `HEALTHCHECK CMD curl …/dapr/config` to the runtime images.

**Failure mode (of the rejected option).** Nothing consumes a Docker healthcheck here: Compose gates startup on `kafka`'s healthcheck (not the apps'), and Kubernetes uses the Deployments' `readinessProbe` (`/dapr/config`) + Dapr sidecar readiness — neither reads a container `HEALTHCHECK`. The `mcr.microsoft.com/dotnet/aspnet` runtime has no `curl`/`wget`, so a probe would require an `apt-get install` (added image weight + CVE surface) or a compiled health binary, for zero consumer benefit. The image contract (user, ports, entrypoint, env) is already verified by `make image-test` (container-structure-test) and the runtime is exercised by `make e2e`/`make e2e-kind`. If an orchestrator that gates on Docker health is ever introduced, add a boot-marker-safe probe then.
