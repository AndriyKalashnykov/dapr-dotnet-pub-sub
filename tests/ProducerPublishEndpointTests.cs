using System.Net;
using System.Net.Http.Json;
using Common;
using Dapr.Client;
using FakeItEasy;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Tests;

public class ProducerPublishEndpointTests
{
    private static WebApplicationFactory<Producer.Program> _factory = null!;
    private static HttpClient _client = null!;
    private static DaprClient _fakeDaprClient = null!;

    [Before(Class)]
    public static void Setup()
    {
        _fakeDaprClient = A.Fake<DaprClient>();
        _factory = new WebApplicationFactory<Producer.Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureTestServices(services =>
                {
                    services.RemoveAll<DaprClient>();
                    services.AddSingleton<DaprClient>(_fakeDaprClient);
                });
            });
        _client = _factory.CreateClient();
    }

    [After(Class)]
    public static async Task Cleanup()
    {
        _client.Dispose();
        await _factory.DisposeAsync();
    }

    [Test]
    public async Task PostSend_WithValidMessage_Returns202AndPublishes()
    {
        var dto = new TinyMessageDto
        {
            Id = "a1cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var response = await _client.PostAsJsonAsync("/send", dto);

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.Accepted);
        A.CallTo(_fakeDaprClient)
            .Where(call => call.Method.Name == nameof(DaprClient.PublishEventAsync))
            .MustHaveHappened();
    }

    [Test]
    public async Task PostSendAsBytes_WithValidMessage_Returns202AndPublishes()
    {
        var dto = new TinyMessageDto
        {
            Id = "b1cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-27T02:52:04.835Z",
            Type = "2"
        };

        var response = await _client.PostAsJsonAsync("/sendasbytes", dto);

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.Accepted);
        A.CallTo(_fakeDaprClient)
            .Where(call => call.Method.Name == nameof(DaprClient.PublishByteEventAsync))
            .MustHaveHappened();
    }

    [Test]
    public async Task PostSend_WithInvalidJson_Returns400()
    {
        var response = await _client.PostAsync("/send",
            new StringContent("{not-json}", System.Text.Encoding.UTF8, "application/json"));

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.BadRequest);
    }
}
