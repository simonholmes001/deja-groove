using DejaGroove.Application.Commands;
using DejaGroove.Domain.Scanning;

namespace DejaGroove.Application.UseCases;

public interface IResolveAmbiguousScanUseCase
{
    Task<ScanResult> ExecuteAsync(ResolveAmbiguousScanCommand command, CancellationToken ct = default);
}
