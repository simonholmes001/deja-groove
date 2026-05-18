using System.Security.Cryptography;
using System.Text;

namespace DejaGroove.Domain.Shared;

/// <summary>
/// Maps an external identity provider subject (Entra External ID <c>sub</c>) to
/// a stable internal user id. Uses an RFC 4122 version 5 (SHA-1, name-based)
/// UUID so the same subject always yields the same id without a lookup table.
/// </summary>
public static class DeterministicUserId
{
    // Fixed namespace UUID for the Déjà Groove identity space. Changing this
    // value would re-key every existing user, so it must never change.
    private static readonly Guid Namespace =
        Guid.Parse("6f9c3a1e-2b4d-5e6f-8a0b-1c2d3e4f5a6b");

    public static Guid FromSubject(string subject)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(subject);

        var namespaceBytes = ToRfcByteOrder(Namespace);
        var nameBytes = Encoding.UTF8.GetBytes(subject);

        Span<byte> hash = stackalloc byte[20];
        using (var sha1 = SHA1.Create())
        {
            var input = new byte[namespaceBytes.Length + nameBytes.Length];
            Buffer.BlockCopy(namespaceBytes, 0, input, 0, namespaceBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, input, namespaceBytes.Length, nameBytes.Length);
            sha1.TryComputeHash(input, hash, out _);
        }

        Span<byte> guidBytes = stackalloc byte[16];
        hash[..16].CopyTo(guidBytes);

        // Set the version (5) and the RFC 4122 variant in the canonical layout.
        guidBytes[6] = (byte)((guidBytes[6] & 0x0F) | 0x50);
        guidBytes[8] = (byte)((guidBytes[8] & 0x3F) | 0x80);

        return FromRfcByteOrder(guidBytes);
    }

    // .NET stores the first three Guid groups little-endian; RFC 4122 hashing
    // requires big-endian. These two helpers convert in both directions so the
    // produced id is interoperable with any RFC-compliant implementation.
    private static byte[] ToRfcByteOrder(Guid guid)
    {
        var bytes = guid.ToByteArray();
        SwapEndianGroups(bytes);
        return bytes;
    }

    private static Guid FromRfcByteOrder(ReadOnlySpan<byte> rfcBytes)
    {
        var bytes = rfcBytes.ToArray();
        SwapEndianGroups(bytes);
        return new Guid(bytes);
    }

    private static void SwapEndianGroups(byte[] bytes)
    {
        (bytes[0], bytes[3]) = (bytes[3], bytes[0]);
        (bytes[1], bytes[2]) = (bytes[2], bytes[1]);
        (bytes[4], bytes[5]) = (bytes[5], bytes[4]);
        (bytes[6], bytes[7]) = (bytes[7], bytes[6]);
    }
}
