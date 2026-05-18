using DejaGroove.Application.Collection;
using DejaGroove.Domain.Collection;

namespace DejaGroove.Application.UseCases;

public interface IAddToCollectionUseCase
{
    Task<AddToCollectionResult> ExecuteAsync(AddToCollectionCommand command, CancellationToken ct = default);
}

public interface ICollectionQueryUseCase
{
    Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default);
    Task<CollectionRecord?> GetAsync(Guid userId, Guid id, CancellationToken ct = default);
}
