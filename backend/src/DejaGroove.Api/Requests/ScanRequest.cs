namespace DejaGroove.Api.Requests;

public sealed class ScanRequest
{
    public IFormFile? Image { get; set; }
    public string? ClientScanId { get; set; }
    public string? CapturedAt { get; set; }
}
