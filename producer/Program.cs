using System.Text.Json;
using Dapr.Client;
using PubSub.Common;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDaprClient();

// Configure Kestrel to listen on the port from DAPR_APP_PORT
var daprPort = Environment.GetEnvironmentVariable("DAPR_APP_PORT");
var port = !string.IsNullOrEmpty(daprPort) ? int.Parse(daprPort) : 5231;
builder.WebHost.UseUrls($"http://*:{port}");

var app = builder.Build();

const string PubSubComponentName = "orderpubsub-kafka";
const string TopicName = "orders";

// Dummy endpoint for /dapr/config to avoid 404 log noise
app.MapGet("/dapr/config", () => Results.Json(new { }));
// Dummy endpoint for /dapr/subscribe to avoid 404 log noise
app.MapGet("/dapr/subscribe", () => Results.Json(Array.Empty<object>()));

app.MapPost("/send", async (
        TinyMessage message,
        DaprClient daprClient) =>
    {
        await daprClient.PublishEventAsync(
            PubSubComponentName,
            TopicName,
            message);
        Console.WriteLine($"Sent message {message.Id}.");

        return Results.Accepted(string.Empty, message.Id);
    }
);

app.MapPost("/sendasbytes", async (
        TinyMessage message,
        DaprClient daprClient) =>
    {
        var content = JsonSerializer.SerializeToUtf8Bytes(message);
        await daprClient.PublishByteEventAsync(
            PubSubComponentName,
            TopicName,
            content.AsMemory());
        Console.WriteLine($"Sent message {message.Id}.");

        return Results.Accepted(string.Empty, message.Id);
    }
);

app.Run();

// for (int i = 1; i <= 100; i++) {
//     var order = new Order(i);
//     using var client = new DaprClientBuilder().Build();
//
//     // Publish an event/message using Dapr PubSub
//     await client.PublishEventAsync("orderpubsub-kafka", "orders", order);
//     Console.WriteLine(" sent: " + order);
//
//     await Task.Delay(TimeSpan.FromSeconds(1));
// }