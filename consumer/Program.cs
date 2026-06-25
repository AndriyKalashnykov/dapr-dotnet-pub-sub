// SPDX-License-Identifier: MIT

using Dapr.Client;
using Common;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

// Configure Kestrel to listen on the port from DAPR_APP_PORT
var daprPort = Environment.GetEnvironmentVariable("DAPR_APP_PORT");
var port = !string.IsNullOrEmpty(daprPort) ? int.Parse(daprPort) : 5231;
builder.WebHost.UseUrls($"http://*:{port}");

// Add services for handling Dapr pub/sub
builder.Services.AddDaprClient();
builder.Services.AddControllers().AddDapr();

// App-side OpenTelemetry tracing — exports the consumer's own HTTP handler spans
// (/handletype1, /handletype2, /dafault-messagehandler) to the OTLP endpoint
// (Jaeger). Gated on OTEL_EXPORTER_OTLP_ENDPOINT so the local `dapr run` flow
// stays noise-free. service.name mirrors the Dapr app-id.
if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT")))
{
    var serviceName = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "consumer";
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService(serviceName))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddOtlpExporter());
}

var app = builder.Build();
app.UseCloudEvents();

// For debugging purposes, add request logging
app.Use(async (context, next) =>
{
    Console.WriteLine($"Request received: {context.Request.Method} {context.Request.Path}");
    await next();
});

app.MapPost("/handletype1", (TinyMessage message) =>
{
    Console.WriteLine($"/handletype1 - Received message {message.Id}, timestamp: {message.TimeStamp}");
    return Results.Accepted();
});

app.MapPost("/handletype2", (TinyMessage message) =>
{
    Console.WriteLine($"/handletype2 - Received message {message.Id}, timestamp: {message.TimeStamp}");
    return Results.Accepted();
});

app.MapPost("/dafault-messagehandler", (TinyMessage message) =>
{
    Console.WriteLine($"/dafault-messagehandler - Received message {message.Id}, timestamp: {message.TimeStamp}");
    return Results.Accepted();
});

// Explicitly map Dapr subscription endpoints
app.MapControllers();

app.Run();

namespace Consumer { public partial class Program { } }