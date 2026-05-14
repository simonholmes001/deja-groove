using DejaGroove.Domain.Scanning;
using DejaGroove.Application.Commands;

namespace DejaGroove.Application.UseCases;

public interface IScanWorkflowUseCase
{
    Task<ScanResult> ExecuteAsync(ScanCommand command, CancellationToken ct = default);
}
