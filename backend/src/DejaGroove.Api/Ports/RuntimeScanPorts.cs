using System.Security.Cryptography;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;

namespace DejaGroove.Api.Ports;

public sealed class ImageHeaderValidationPort : IImageValidationPort
{
    public Task<ValidationResult> ValidateAsync(ReadOnlyMemory<byte> imageBytes, string? contentType, CancellationToken ct = default)
    {
        var header = imageBytes.Span;
        var read = header.Length;

        if (IsJpeg(header, read) || IsPng(header, read))
            return Task.FromResult(ValidationResult.Ok());

        return Task.FromResult(ValidationResult.Fail("unsupported_image", "Image must be a JPEG or PNG file."));
    }

    private static bool IsJpeg(ReadOnlySpan<byte> header, int read) =>
        read >= 3 && header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;

    private static bool IsPng(ReadOnlySpan<byte> header, int read) =>
        read >= 8 &&
        header[0] == 0x89 &&
        header[1] == 0x50 &&
        header[2] == 0x4E &&
        header[3] == 0x47 &&
        header[4] == 0x0D &&
        header[5] == 0x0A &&
        header[6] == 0x1A &&
        header[7] == 0x0A;
}

public sealed class Sha256PerceptualHashPort : IPerceptualHashPort
{
    public async Task<PerceptualHash> ComputeAsync(Stream imageStream, CancellationToken ct = default)
    {
        using var ms = new MemoryStream();
        await imageStream.CopyToAsync(ms, ct);
        var hash = SHA256.HashData(ms.ToArray());
        return new PerceptualHash(BitConverter.ToUInt64(hash, 0));
    }
}
