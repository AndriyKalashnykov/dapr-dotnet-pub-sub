using System.Net;
using System.Net.Http.Json;
using Common;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Tests;

public class ProducerEndpointTests : IClassFixture<WebApplicationFactory<Producer.Program>>
{
    private readonly HttpClient _client;

    public ProducerEndpointTests(WebApplicationFactory<Producer.Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetDaprConfig_Returns200WithEmptyJson()
    {
        var response = await _client.GetAsync("/dapr/config");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var content = await response.Content.ReadAsStringAsync();
        Assert.Equal("{}", content);
    }

    [Fact]
    public async Task GetDaprSubscribe_Returns200WithEmptyArray()
    {
        var response = await _client.GetAsync("/dapr/subscribe");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var content = await response.Content.ReadAsStringAsync();
        Assert.Equal("[]", content);
    }
}
