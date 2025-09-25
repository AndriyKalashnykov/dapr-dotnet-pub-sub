using System;
using Dapr.Client;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

using PubSub.Common;

for (int i = 1; i <= 100; i++) {
    var order = new Order(i);
    using var client = new DaprClientBuilder().Build();

    // Publish an event/message using Dapr PubSub
    await client.PublishEventAsync("orderpubsub-kafka", "orders", order);
    Console.WriteLine(" sent: " + order);

    await Task.Delay(TimeSpan.FromSeconds(1));
}