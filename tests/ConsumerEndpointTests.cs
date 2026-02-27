using System.Net;
using System.Net.Http.Json;
using Common;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Tests;

public class ConsumerEndpointTests : IClassFixture<WebApplicationFactory<Consumer.Program>>
{
    private readonly HttpClient _client;

    public ConsumerEndpointTests(WebApplicationFactory<Consumer.Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task PostHandleType1_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "1");

        var response = await _client.PostAsJsonAsync("/handletype1", message);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
    }

    [Fact]
    public async Task PostHandleType2_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "2");

        var response = await _client.PostAsJsonAsync("/handletype2", message);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
    }

    [Fact]
    public async Task PostDefaultMessageHandler_WithValidMessage_Returns202()
    {
        var message = new TinyMessage(Guid.NewGuid(), DateTimeOffset.UtcNow, "0");

        var response = await _client.PostAsJsonAsync("/dafault-messagehandler", message);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
    }
}
