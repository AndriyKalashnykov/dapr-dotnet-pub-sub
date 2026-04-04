using Common;

namespace Tests;

public class TinyMessageDtoTests
{
    [Test]
    public async Task ToMessage_ValidGuidAndTimestamp_ReturnsCorrectMessage()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        await Assert.That(message.Id).IsEqualTo(Guid.Parse("e9cdd036-c529-4bf9-bd59-d7148ef9237d"));
        await Assert.That(message.TimeStamp.UtcDateTime).IsEqualTo(new DateTime(2025, 9, 26, 2, 52, 4, 835, DateTimeKind.Utc));
        await Assert.That(message.Type).IsEqualTo("1");
    }

    [Test]
    public async Task ToMessage_InvalidGuid_GeneratesNewGuid()
    {
        var dto = new TinyMessageDto
        {
            Id = "not-a-guid",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        await Assert.That(message.Id).IsNotEqualTo(Guid.Empty);
    }

    [Test]
    public async Task ToMessage_EmptyGuid_GeneratesNewGuid()
    {
        var dto = new TinyMessageDto
        {
            Id = "",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        await Assert.That(message.Id).IsNotEqualTo(Guid.Empty);
    }

    [Test]
    public async Task ToMessage_GuidWithTrailingBrace_CleansAndParses()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d}",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "1"
        };

        var message = dto.ToMessage();

        await Assert.That(message.Id).IsEqualTo(Guid.Parse("e9cdd036-c529-4bf9-bd59-d7148ef9237d"));
    }

    [Test]
    public async Task ToMessage_InvalidTimestamp_FallsBackToUtcNow()
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

        await Assert.That(message.TimeStamp.UtcDateTime).IsGreaterThanOrEqualTo(before.AddSeconds(-1));
        await Assert.That(message.TimeStamp.UtcDateTime).IsLessThanOrEqualTo(after.AddSeconds(1));
    }

    [Test]
    public async Task ToMessage_EmptyTimestamp_FallsBackToUtcNow()
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

        await Assert.That(message.TimeStamp.UtcDateTime).IsGreaterThanOrEqualTo(before.AddSeconds(-1));
        await Assert.That(message.TimeStamp.UtcDateTime).IsLessThanOrEqualTo(after.AddSeconds(1));
    }

    [Test]
    public async Task ToMessage_TypeFieldPassesThroughAsIs()
    {
        var dto = new TinyMessageDto
        {
            Id = "e9cdd036-c529-4bf9-bd59-d7148ef9237d",
            TimeStamp = "2025-09-26T02:52:04.835Z",
            Type = "custom-type"
        };

        var message = dto.ToMessage();

        await Assert.That(message.Type).IsEqualTo("custom-type");
    }

    [Test]
    public async Task ToMessage_DefaultDto_ReturnsValidMessageWithGeneratedIdAndCurrentTime()
    {
        var before = DateTime.UtcNow;

        var dto = new TinyMessageDto();

        var message = dto.ToMessage();
        var after = DateTime.UtcNow;

        await Assert.That(message.Id).IsNotEqualTo(Guid.Empty);
        await Assert.That(message.TimeStamp.UtcDateTime).IsGreaterThanOrEqualTo(before.AddSeconds(-1));
        await Assert.That(message.TimeStamp.UtcDateTime).IsLessThanOrEqualTo(after.AddSeconds(1));
        await Assert.That(message.Type).IsEqualTo(string.Empty);
    }
}
