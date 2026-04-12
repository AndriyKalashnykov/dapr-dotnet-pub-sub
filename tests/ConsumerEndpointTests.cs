using System.Net;
using System.Net.Http.Json;
using Common;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Tests;

public class ConsumerEndpointTests
{
    private static WebApplicationFactory<Consumer.Program> _factory = null!;
    private static HttpClient _client = null!;

    [Before(Class)]
    public static void Setup()
    {
        _factory = new WebApplicationFactory<Consumer.Program>();
        _client = _factory.CreateClient();
    }

    [After(Class)]
    public static async Task Cleanup()
    {
        _client.Dispose();
        await _factory.DisposeAsync();
    }

    [Test]
    public async Task PostHandleType1_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "1");

        var response = await _client.PostAsJsonAsync("/handletype1", message);

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.Accepted);
    }

    [Test]
    public async Task PostHandleType2_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "2");

        var response = await _client.PostAsJsonAsync("/handletype2", message);

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.Accepted);
    }

    [Test]
    public async Task PostDefaultMessageHandler_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "0");

        var response = await _client.PostAsJsonAsync("/dafault-messagehandler", message);

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.Accepted);
    }

    [Test]
    public async Task PostHandleType1_WithInvalidJson_Returns400()
    {
        var response = await _client.PostAsync("/handletype1",
            new StringContent("{not-json}", System.Text.Encoding.UTF8, "application/json"));

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.BadRequest);
    }

    [Test]
    public async Task PostHandleType1_WithEmptyBody_Returns400()
    {
        var response = await _client.PostAsync("/handletype1",
            new StringContent("", System.Text.Encoding.UTF8, "application/json"));

        await Assert.That(response.StatusCode).IsEqualTo(HttpStatusCode.BadRequest);
    }
}
