using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Tests;

public class ProducerEndpointTests
{
    private static WebApplicationFactory<Producer.Program> _factory = null!;
    private static HttpClient _client = null!;

    [Before(Class)]
    public static void Setup()
    {
        _factory = new WebApplicationFactory<Producer.Program>();
        _client = _factory.CreateClient();
    }

    [After(Class)]
    public static async Task Cleanup()
    {
        _client.Dispose();
        await _factory.DisposeAsync();
    }

    [Test]
    public async Task GetDaprConfig_Returns200WithEmptyJson()
    {
        var response = await _client.GetAsync("/dapr/config");

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.OK);
        var content = await response.Content.ReadAsStringAsync();
        await Assert.That(content).IsEqualTo("{}");
    }

    [Test]
    public async Task GetDaprSubscribe_Returns200WithEmptyArray()
    {
        var response = await _client.GetAsync("/dapr/subscribe");

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.OK);
        var content = await response.Content.ReadAsStringAsync();
        await Assert.That(content).IsEqualTo("[]");
    }
}
