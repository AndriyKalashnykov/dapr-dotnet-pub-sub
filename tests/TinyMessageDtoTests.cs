using Common;
using Xunit;

namespace Tests;

public class TinyMessageDtoTests
{
    [Fact]
    public void ToMessage_ValidGuidAndTimestamp_ReturnsCorrectMessage()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        Assert.Equal(Guid.Parse("e9cdd036-c529-4bf9-bd59-d7148ef9237d"), message.Id);
        Assert.Equal(new DateTime(2025, 9, 26, 2, 52, 4, 835, DateTimeKind.Utc), message.TimeStamp.UtcDateTime);
        Assert.Equal("1", message.Type);
    }

    [Fact]
    public void ToMessage_InvalidGuid_GeneratesNewGuid()
    {
        var dto = new TinyMessageDto
        {
            Id = "not-a-guid",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        Assert.NotEqual(Guid.Empty, message.Id);
    }

    [Fact]
    public void ToMessage_EmptyGuid_GeneratesNewGuid()
    {
        var dto = new TinyMessageDto
        {
            Id = "",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        Assert.NotEqual(Guid.Empty, message.Id);
    }

    [Fact]
    public void ToMessage_GuidWithTrailingBrace_CleansAndParses()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d}",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        Assert.Equal(Guid.Parse("e9cdd036-c529-4bf9-bd59-d7148ef9237d"), message.Id);
    }

    [Fact]
    public void ToMessage_InvalidTimestamp_FallsBackToUtcNow()
    {
        var before = DateTime.UtcNow;

        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "not-a-timestamp",
            Type = "1"
        };

        var message = dto.ToMessage();
        var after = DateTime.UtcNow;

        Assert.InRange(message.TimeStamp.UtcDateTime, before.AddSeconds(-1), after.AddSeconds(1));
    }

    [Fact]
    public void ToMessage_EmptyTimestamp_FallsBackToUtcNow()
    {
        var before = DateTime.UtcNow;

        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "",
            Type = "1"
        };

        var message = dto.ToMessage();
        var after = DateTime.UtcNow;

        Assert.InRange(message.TimeStamp.UtcDateTime, before.AddSeconds(-1), after.AddSeconds(1));
    }

    [Fact]
    public void ToMessage_TypeFieldPassesThroughAsIs()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "custom-type"
        };

        var message = dto.ToMessage();

        Assert.Equal("custom-type", message.Type);
    }

    [Fact]
    public void ToMessage_DefaultDto_ReturnsValidMessageWithGeneratedIdAndCurrentTime()
    {
        var before = DateTime.UtcNow;

        var dto = new TinyMessageDto();

        var message = dto.ToMessage();
        var after = DateTime.UtcNow;

        Assert.NotEqual(Guid.Empty, message.Id);
        Assert.InRange(message.TimeStamp.UtcDateTime, before.AddSeconds(-1), after.AddSeconds(1));
        Assert.Equal(string.Empty, message.Type);
    }
}
