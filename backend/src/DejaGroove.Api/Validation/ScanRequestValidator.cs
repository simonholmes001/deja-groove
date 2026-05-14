using FluentValidation;
using DejaGroove.Api.Requests;

namespace DejaGroove.Api.Validation;

public sealed class ScanRequestValidator : AbstractValidator<ScanRequest>
{
    // JPEG magic bytes: FF D8 FF
    private static readonly byte[] JpegMagic = [0xFF, 0xD8, 0xFF];

    public ScanRequestValidator()
    {
        RuleFor(x => x.Image)
            .NotNull().WithMessage("Image is required.")
            .Must(f => f == null || f.ContentType == "image/jpeg")
                .WithMessage("Image must be JPEG (image/jpeg).")
            .Must(f => f == null || f.Length > 0)
                .WithMessage("Image must not be empty.")
            .Must(f => f == null || HasJpegMagicBytes(f.OpenReadStream()))
                .WithMessage("Image content does not appear to be a valid JPEG file.");

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

    private static bool HasJpegMagicBytes(Stream stream)
    {
        try
        {
            Span<byte> header = stackalloc byte[3];
            var read = stream.Read(header);
            return read == 3
                && header[0] == JpegMagic[0]
                && header[1] == JpegMagic[1]
                && header[2] == JpegMagic[2];
        }
        finally
        {
            stream.Dispose();
        }
    }
}
