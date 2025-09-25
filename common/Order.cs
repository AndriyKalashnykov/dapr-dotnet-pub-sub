using System.Text.Json.Serialization;

namespace PubSub.Common;

public record Order([property: JsonPropertyName("orderId")] int OrderId);