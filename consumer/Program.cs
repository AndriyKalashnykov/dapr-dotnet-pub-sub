using System.Text.Json.Serialization;
using Dapr;
using PubSub.Common;

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

// Dapr will send serialized event object vs. being raw CloudEvent
app.UseCloudEvents();

// needed for Dapr pub/sub routing
app.MapSubscribeHandler();

if (app.Environment.IsDevelopment()) {app.UseDeveloperExceptionPage();}

// Dapr subscription in [Topic] routes orders topic to this route
app.MapPost("/orders", [Topic("orderpubsub-kafka", "orders")] (Order order) => {
    Console.WriteLine(" received : " + order);
    return Results.Ok(order);
});

await app.RunAsync();

