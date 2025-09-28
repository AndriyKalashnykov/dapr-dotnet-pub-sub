namespace Common;

public record TinyMessage(Guid Id, DateTimeOffset TimeStamp);

// The DTO for incoming HTTP requests
public class TinyMessageDto
{
    public string Id { get; set; } = string.Empty;
    public string TimeStamp { get; set; } = string.Empty;

    public TinyMessage ToMessage()
    {
        Guid id;
        // Clean up potential formatting issues in the ID string
        string cleanedId = Id?.Trim().TrimEnd('}');
        if (string.IsNullOrEmpty(cleanedId) || !Guid.TryParse(cleanedId, out id))
        {
            id = Guid.NewGuid(); // Use a fallback if parsing fails
            Console.WriteLine($"Failed to parse ID: {Id}, using generated ID: {id}");
        }

        DateTime timestamp;
        Console.WriteLine($"Attempting to parse timestamp value: {TimeStamp}");
        
        if (!DateTime.TryParse(TimeStamp, out timestamp))
        {
            timestamp = DateTime.UtcNow; // Use current time if parsing fails
            Console.WriteLine($"Failed to parse timestamp: {TimeStamp}, using current UTC time: {timestamp}");
        }

        return new TinyMessage(id, timestamp);
    }
}