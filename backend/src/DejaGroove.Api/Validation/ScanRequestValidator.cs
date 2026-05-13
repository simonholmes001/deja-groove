using FluentValidation;
using DejaGroove.Api.Requests;

namespace DejaGroove.Api.Validation;

public sealed class ScanRequestValidator : AbstractValidator<ScanRequest>
{
    private const long MaxImageBytes = 10 * 1024 * 1024; // 10 MB

    public ScanRequestValidator()
    {
        RuleFor(x => x.Image)
            .NotNull().WithMessage("Image is required.")
            .Must(f => f == null || f.ContentType == "image/jpeg")
                .WithMessage("Image must be JPEG (image/jpeg).")
            .Must(f => f == null || f.Length > 0)
                .WithMessage("Image must not be empty.");

        RuleFor(x => x.ClientScanId)
            .NotEmpty().WithMessage("client_scan_id is required.")
            .Must(id => id == null || Guid.TryParse(id, out _))
                .WithMessage("client_scan_id must be a valid UUID.");

        When(x => x.CapturedAt != null, () =>
        {
            RuleFor(x => x.CapturedAt)
                .Must(s => s == null || DateTimeOffset.TryParse(s, out _))
                    .WithMessage("captured_at must be a valid ISO-8601 date-time.");
        });
    }
}
