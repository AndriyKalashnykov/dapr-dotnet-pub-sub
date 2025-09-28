using System.Text;
using System.Text.Json;
using Dapr.Client;
// Replace PubSub.Common with the correct namespace
// Looking at your project structure, this is likely just "Common"
using Common;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDaprClient();
builder.Services.AddLogging(logging => { logging.AddConsole(); });

// Configure Kestrel to listen on the port from DAPR_APP_PORT
var daprPort = Environment.GetEnvironmentVariable("DAPR_APP_PORT");
var port = !string.IsNullOrEmpty(daprPort) ? int.Parse(daprPort) : 5231;
builder.WebHost.UseUrls($"http://*:{port}");

var app = builder.Build();

const string PubSubComponentName = "message-pubsub-kafka";
const string TopicName = "incoming-messages";  // Changed from "orders" to match subscription.yaml

// Dummy endpoint for /dapr/config to avoid 404 log noise
app.MapGet("/dapr/config", () => Results.Json(new { }));
// Dummy endpoint for /dapr/subscribe to avoid 404 log noise
app.MapGet("/dapr/subscribe", () => Results.Json(Array.Empty<object>()));

// Add the request body logging middleware
app.Use(async (context, next) =>
{
    // Only log POST requests
    if (context.Request.Method == "POST")
    {
        // Enable buffering so we can read the body multiple times
        context.Request.EnableBuffering();
        
        if (context.Request.ContentLength > 0)
        {
            // Remember position
            var position = context.Request.Body.Position;
            
            // Read the body
            using var reader = new StreamReader(
                context.Request.Body,
                encoding: Encoding.UTF8,
                detectEncodingFromByteOrderMarks: false,
                leaveOpen: true);
                
            var requestBody = await reader.ReadToEndAsync();
            Console.WriteLine($"Received request body: {requestBody}");
            
            // Reset the position
            context.Request.Body.Position = position;
        }
    }
    
    await next();
});

app.MapPost("/send", async (
        TinyMessageDto messageDto,
        DaprClient daprClient,
        ILogger<Program> logger) =>
    {
        try {
            var message = messageDto.ToMessage();
            await daprClient.PublishEventAsync(
                PubSubComponentName,
                TopicName,
                message);
            Console.WriteLine($"Sent message {message.Id}, timestamp: {message.TimeStamp}");

            return Results.Accepted(string.Empty, message.Id);
        }
        catch (Exception ex) {
            logger.LogError(ex, "Failed to publish message");
            return Results.Problem(
                detail: $"Failed to publish message: {ex.Message}", 
                statusCode: 500);
        }
    }
);

app.MapPost("/sendasbytes", async (
        TinyMessageDto messageDto,
        DaprClient daprClient,
        ILogger<Program> logger) => {
        try {
            var message = messageDto.ToMessage();
            var content = JsonSerializer.SerializeToUtf8Bytes(message);
            await daprClient.PublishByteEventAsync(
                pubsubName: PubSubComponentName,
                topicName: TopicName,
                data: content.AsMemory());
            Console.WriteLine($"Sent message {message.Id}.");

            return Results.Accepted(string.Empty, message.Id);
        }
        catch (Exception ex) {
            logger.LogError(ex, "Failed to publish message as bytes");
            return Results.Problem(
                detail: $"Failed to publish message: {ex.Message}",
                statusCode: 500);
        }
    }
);

app.Run();

// for (int i = 1; i <= 100; i++) {
//     var order = new Order(i);
//     using var client = new DaprClientBuilder().Build();
//
//     // Publish an event/message using Dapr PubSub
//     await client.PublishEventAsync("message-pubsub-kafka", "orders", order);
//     Console.WriteLine(" sent: " + order);
//
//     await Task.Delay(TimeSpan.FromSeconds(1));
// }