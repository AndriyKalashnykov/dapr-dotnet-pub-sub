using Dapr.Client;
using Common;

var builder = WebApplication.CreateBuilder(args);

// Configure Kestrel to listen on the port from DAPR_APP_PORT
var daprPort = Environment.GetEnvironmentVariable("DAPR_APP_PORT");
var port = !string.IsNullOrEmpty(daprPort) ? int.Parse(daprPort) : 5231;
builder.WebHost.UseUrls($"http://*:{port}");

// Add services for handling Dapr pub/sub
builder.Services.AddDaprClient();
builder.Services.AddControllers().AddDapr();

var app = builder.Build();
app.UseCloudEvents();

// For debugging purposes, add request logging
app.Use(async (context, next) => {
    Console.WriteLine($"Request received: {context.Request.Method} {context.Request.Path}");
    await next();
});

app.MapPost("/messagehandler", (TinyMessage message) =>
{
    Console.WriteLine($"Received message {message.Id}, timestamp: {message.TimeStamp}");
    return Results.Accepted();
});

// Explicitly map Dapr subscription endpoints
app.MapControllers();

app.Run();