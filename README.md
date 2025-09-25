# Dapr DotNet pub/sub

In this quickstart, you'll create a publisher microservice and a subscriber microservice to demonstrate how Dapr enables
a publish-subcribe pattern. The publisher will generate messages of a specific topic, while subscribers will listen for
messages of specific topics.
See [Why Pub-Sub](https://docs.dapr.io/developing-applications/building-blocks/pubsub/pubsub-overview/) to understand
when this pattern might be a good choice for your software architecture.

Visit [this](https://docs.dapr.io/developing-applications/building-blocks/pubsub/) link for more information about Dapr
and Pub-Sub.

> **Note:** This example leverages the Dapr client SDK. If you are looking for the example using only
> HTTP [click here](../http).

This quickstart includes one publisher:

- Dotnet client message generator `producer`

And one subscriber:

- Dotnet subscriber `consumer`

## Run all apps with multi-app run template file:

This section shows how to run both applications at once
using [multi-app run template files](https://docs.dapr.io/developing-applications/local-development/multi-app-dapr-run/multi-app-overview/)
with `dapr run -f .`. This enables to you test the interactions between multiple applications.

1. Open a new terminal window and run the multi app run template:

```bash
make run
```

The terminal console output should look similar to this:

```text
== APP - producer-sdk ==  sent: Order { OrderId = 1 
== APP - consumer-sdk ==  received : Order { OrderId = 1 }
...
```

2. Stop and clean up application processes

```bash
dapr stop -f .
```

## Run a single app at a time with Dapr (Optional)

An alternative to running all or multiple applications at once is to run single apps one-at-a-time using multiple
`dapr run .. -- dotnet run` commands. This next section covers how to do this.

### Run Dotnet message subscriber with Dapr

1. Run the Dotnet subscriber app with Dapr:

```bash
cd ./consumer
dapr run --app-id consumer-sdk --resources-path ./components/ --app-port 7006 -- dotnet run
```

### Run Dotnet message publisher with Dapr

1. Run the Dotnet publisher app with Dapr:

```bash
cd ./producer
dapr run --app-id producer-sdk --resources-path ../components/ --app-port 7007 -- dotnet run
```

2. Stop and clean up application processes

```bash
dapr stop --app-id consumer-sdk
dapr stop --app-id producer-sdk
```
