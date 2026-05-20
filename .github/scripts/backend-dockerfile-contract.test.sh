#!/usr/bin/env bash
set -euo pipefail

DOCKERFILE="backend/src/DejaGroove.Api/Dockerfile"

[ -f "$DOCKERFILE" ] || { echo "Missing Dockerfile: $DOCKERFILE" >&2; exit 1; }

grep -Eq '^FROM mcr.microsoft.com/dotnet/sdk:9.0@sha256:[a-f0-9]{64} AS build$' "$DOCKERFILE" || { echo "SDK base image must be digest pinned" >&2; exit 1; }
grep -Eq '^FROM mcr.microsoft.com/dotnet/aspnet:9.0@sha256:[a-f0-9]{64} AS final$' "$DOCKERFILE" || { echo "ASP.NET base image must be digest pinned" >&2; exit 1; }
grep -q 'dotnet publish src/DejaGroove.Api/DejaGroove.Api.csproj' "$DOCKERFILE" || { echo "Missing publish target contract" >&2; exit 1; }
grep -q 'ENV ASPNETCORE_URLS=http://+:8080' "$DOCKERFILE" || { echo "Missing ASPNETCORE_URLS contract" >&2; exit 1; }
grep -q '^EXPOSE 8080' "$DOCKERFILE" || { echo "Missing EXPOSE 8080" >&2; exit 1; }
grep -q 'ENTRYPOINT \["dotnet", "DejaGroove.Api.dll"\]' "$DOCKERFILE" || { echo "Missing entrypoint contract" >&2; exit 1; }

echo "backend Dockerfile contract tests passed."
