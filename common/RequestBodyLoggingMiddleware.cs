using System.Text;

public class RequestBodyLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestBodyLoggingMiddleware> _logger;

    public RequestBodyLoggingMiddleware(RequestDelegate next, ILogger<RequestBodyLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Enable buffering so the request body can be read multiple times
        context.Request.EnableBuffering();

        // Log the request body
        if (context.Request.ContentLength > 0)
        {
            var originalPosition = context.Request.Body.Position;

            using var reader = new StreamReader(
                context.Request.Body,
                Encoding.UTF8,
                false,
                leaveOpen: true);

            var requestBody = await reader.ReadToEndAsync();
            _logger.LogInformation($"Request Body: {requestBody}");

            // Reset the position to the beginning for subsequent reads
            context.Request.Body.Position = originalPosition;
        }

        // Call the next middleware in the pipeline
        await _next(context);
    }
}