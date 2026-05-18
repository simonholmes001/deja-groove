using DejaGroove.Application.Collection;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Collection;

namespace DejaGroove.Application.UseCases;

/// <summary>
/// Read side of the collection (issue #16). Thin today, but a named seam so
/// list/detail policy (quota-aware projections, enrichment fan-out) has a home
/// without reshaping controllers later.
/// </summary>
public sealed class CollectionQueryUseCase(ICollectionRepository repository)
    : ICollectionQueryUseCase
{
    public Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(query);
        return repository.ListAsync(query, ct);
    }

    public Task<CollectionRecord?> GetAsync(Guid userId, Guid id, CancellationToken ct = default) =>
        repository.GetByIdAsync(userId, id, ct);
}
