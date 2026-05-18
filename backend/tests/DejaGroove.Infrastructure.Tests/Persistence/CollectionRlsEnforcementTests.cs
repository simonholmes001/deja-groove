using Dapper;
using Npgsql;

namespace DejaGroove.Infrastructure.Tests.Persistence;

/// <summary>
/// Blockers C1/H2: prove the RLS *policy* (not a WHERE clause) isolates
/// tenants for the deja_app runtime role, and that GDPR erasure still works
/// after FORCE ROW LEVEL SECURITY.
/// </summary>
[Trait("Category", "Integration")]
[Collection("postgres")]
public sealed class CollectionRlsEnforcementTests(PostgresFixture fx)
{
    /// <summary>Runs work as the non-privileged deja_app role inside one
    /// transaction, with optional RLS / purge GUCs — i.e. the real runtime
    /// path, where RLS policies are actually evaluated.</summary>
    private async Task AsAppRole(
        Guid? currentUser,
        Func<NpgsqlConnection, NpgsqlTransaction, Task> work,
        Guid? purgeUserId = null)
    {
        await using var conn = new NpgsqlConnection(fx.ConnectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await conn.ExecuteAsync(new CommandDefinition("SET LOCAL ROLE deja_app", transaction: tx));
        if (currentUser is not null)
            await conn.ExecuteAsync(new CommandDefinition(
                "SELECT set_config('app.current_user_id', @u, true)",
                new { u = currentUser.ToString() }, tx));
        if (purgeUserId is not null)
            await conn.ExecuteAsync(new CommandDefinition(
                "SELECT set_config('dejagroove.purge_user_id', @p, true)",
                new { p = purgeUserId.ToString() }, tx));
        await work(conn, tx);
        await tx.CommitAsync();
    }

    [Fact]
    public async Task Policy_BlocksCrossTenantSelect_NotJustWhereClause()
    {
        var alice = Guid.NewGuid();
        var bob = Guid.NewGuid();

        await AsAppRole(alice, (c, t) => c.ExecuteAsync(new CommandDefinition(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, @m)",
            new { u = alice, m = $"rls-{alice:N}" }, t)));

        // Bob runs an UNFILTERED select — only the policy can hide Alice's row.
        await AsAppRole(bob, async (c, t) =>
        {
            var visible = await c.ExecuteScalarAsync<int>(new CommandDefinition(
                "SELECT count(*) FROM collection_records", transaction: t));
            Assert.Equal(0, visible);
        });

        await AsAppRole(alice, async (c, t) =>
        {
            var visible = await c.ExecuteScalarAsync<int>(new CommandDefinition(
                "SELECT count(*) FROM collection_records", transaction: t));
            Assert.Equal(1, visible);
        });
    }

    [Fact]
    public async Task Policy_BlocksCrossTenantUpdateAndDelete()
    {
        var alice = Guid.NewGuid();
        var bob = Guid.NewGuid();
        Guid rowId = Guid.Empty;

        await AsAppRole(alice, async (c, t) =>
            rowId = await c.ExecuteScalarAsync<Guid>(new CommandDefinition(
                "INSERT INTO collection_records (user_id, mbid, notes) VALUES (@u,@m,'orig') RETURNING id",
                new { u = alice, m = $"rlsmod-{alice:N}" }, t)));

        await AsAppRole(bob, async (c, t) =>
        {
            var updated = await c.ExecuteAsync(new CommandDefinition(
                "UPDATE collection_records SET notes='hacked' WHERE id=@id",
                new { id = rowId }, t));
            var deleted = await c.ExecuteAsync(new CommandDefinition(
                "DELETE FROM collection_records WHERE id=@id", new { id = rowId }, t));
            Assert.Equal(0, updated);
            Assert.Equal(0, deleted);
        });

        await AsAppRole(alice, async (c, t) =>
        {
            var notes = await c.ExecuteScalarAsync<string>(new CommandDefinition(
                "SELECT notes FROM collection_records WHERE id=@id", new { id = rowId }, t));
            Assert.Equal("orig", notes);
        });
    }

    [Fact]
    public async Task PurgeUser_InvokedAsAppRole_ErasesTargetButNotBystander()
    {
        // Production-faithful: the app calls SELECT purge_user(...) via its
        // granted EXECUTE. Under FORCE RLS this must still erase the target
        // user completely (H2) while leaving other users untouched.
        var target = Guid.NewGuid();
        var bystander = Guid.NewGuid();

        await AsAppRole(target, (c, t) => c.ExecuteAsync(new CommandDefinition(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u,@m)",
            new { u = target, m = $"purge-{target:N}" }, t)));
        await AsAppRole(bystander, (c, t) => c.ExecuteAsync(new CommandDefinition(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u,@m)",
            new { u = bystander, m = $"keep-{bystander:N}" }, t)));

        await AsAppRole(currentUser: null, work: (c, t) => c.ExecuteAsync(
            new CommandDefinition("SELECT purge_user(@u)", new { u = target }, t)));

        await using var su = new NpgsqlConnection(fx.ConnectionString);
        await su.OpenAsync();
        var targetRows = await su.ExecuteScalarAsync<int>(
            "SELECT count(*) FROM collection_records WHERE user_id=@u", new { u = target });
        var bystanderRows = await su.ExecuteScalarAsync<int>(
            "SELECT count(*) FROM collection_records WHERE user_id=@u", new { u = bystander });

        Assert.Equal(0, targetRows);
        Assert.Equal(1, bystanderRows);
    }

    [Fact]
    public async Task PurgeUser_AfterForceRls_StillFullyErases()
    {
        await using var conn = new NpgsqlConnection(fx.ConnectionString);
        await conn.OpenAsync();
        var user = Guid.NewGuid();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u,'force-purge')", new { u = user });
        await conn.ExecuteAsync(
            @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
              VALUES (@u, gen_random_uuid(), 'NoMatch', 0.0)", new { u = user });
        await conn.ExecuteAsync(
            @"INSERT INTO scan_results_cache (user_id, phash, result_status, confidence, expires_at)
              VALUES (@u, 99, 'NoMatch', 0.0, now() + interval '1 hour')", new { u = user });

        await conn.ExecuteAsync("SELECT purge_user(@u)", new { u = user });

        foreach (var table in new[] { "collection_records", "scan_events", "scan_results_cache",
                     "collection_audit_log", "collection_idempotency_keys" })
        {
            var count = await conn.ExecuteScalarAsync<int>(
                $"SELECT count(*) FROM {table} WHERE user_id=@u", new { u = user });
            Assert.Equal(0, count);
        }
    }
}
