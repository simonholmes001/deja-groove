using Dapper;
using Npgsql;

namespace DejaGroove.Infrastructure.Tests.Persistence;

/// <summary>Issue #46: the V007 trigger must record every collection_records
/// mutation with operation, actor, timestamp and before/after snapshots, and
/// must stay silent during GDPR erasure (V008).</summary>
[Trait("Category", "Integration")]
[Collection("postgres")]
public sealed class CollectionAuditTriggerTests(PostgresFixture fx)
{
    private NpgsqlConnection Connect() => new(fx.ConnectionString);

    private sealed class AuditRow
    {
        public string operation { get; init; } = "";
        public Guid user_id { get; init; }
        public string? before_state { get; init; }
        public string? after_state { get; init; }
        public DateTimeOffset occurred_at { get; init; }
    }

    private static Task<AuditRow> AuditFor(NpgsqlConnection conn, Guid id, string op) =>
        conn.QuerySingleAsync<AuditRow>(
            @"SELECT operation, user_id, before_state::text AS before_state,
                     after_state::text AS after_state, occurred_at
              FROM collection_audit_log
              WHERE collection_record_id = @id AND operation = @op",
            new { id, op });

    [Fact]
    public async Task Insert_WritesInsertAuditRowWithAfterSnapshotAndActor()
    {
        await using var conn = Connect();
        var user = Guid.NewGuid();

        var id = await conn.ExecuteScalarAsync<Guid>(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'audit-ins') RETURNING id",
            new { u = user });

        var audit = await AuditFor(conn, id, "INSERT");

        Assert.Equal(user, audit.user_id);
        Assert.Null(audit.before_state);
        Assert.Contains("audit-ins", audit.after_state);
        Assert.NotEqual(default, audit.occurred_at);
    }

    [Fact]
    public async Task Update_WritesUpdateAuditRowWithBeforeAndAfter()
    {
        await using var conn = Connect();
        var user = Guid.NewGuid();
        var id = await conn.ExecuteScalarAsync<Guid>(
            "INSERT INTO collection_records (user_id, mbid, notes) VALUES (@u, 'audit-upd', 'old') RETURNING id",
            new { u = user });

        await conn.ExecuteAsync(
            "UPDATE collection_records SET notes = 'new' WHERE id = @id", new { id });

        var audit = await AuditFor(conn, id, "UPDATE");

        Assert.Contains("old", audit.before_state);
        Assert.Contains("new", audit.after_state);
    }

    [Fact]
    public async Task Delete_WritesDeleteAuditRowWithBeforeSnapshot()
    {
        await using var conn = Connect();
        var user = Guid.NewGuid();
        var id = await conn.ExecuteScalarAsync<Guid>(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'audit-del') RETURNING id",
            new { u = user });

        await conn.ExecuteAsync("DELETE FROM collection_records WHERE id = @id", new { id });

        var audit = await AuditFor(conn, id, "DELETE");

        Assert.Equal("DELETE", audit.operation);
        Assert.Null(audit.after_state);
        Assert.Contains("audit-del", audit.before_state);
    }

    [Fact]
    public async Task PurgeUser_LeavesNoAuditRows_EvenThoughDeleteFiresTrigger()
    {
        await using var conn = Connect();
        var user = Guid.NewGuid();
        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'purge-audit')",
            new { u = user });

        await conn.ExecuteAsync("SELECT purge_user(@u)", new { u = user });

        var auditCount = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM collection_audit_log WHERE user_id = @u", new { u = user });
        Assert.Equal(0, auditCount);
    }
}
