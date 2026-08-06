FROM mcr.microsoft.com/dotnet/sdk:9.0@sha256:e9d888fb3df1e29121eeab438a20f1354a42d5d453b83f979cde633ed6da1948 AS build
WORKDIR /src

COPY backend/DejaGroove.sln ./backend/
COPY backend/src/DejaGroove.Api/DejaGroove.Api.csproj ./backend/src/DejaGroove.Api/
COPY backend/src/DejaGroove.Application/DejaGroove.Application.csproj ./backend/src/DejaGroove.Application/
COPY backend/src/DejaGroove.Domain/DejaGroove.Domain.csproj ./backend/src/DejaGroove.Domain/
COPY backend/src/DejaGroove.Infrastructure/DejaGroove.Infrastructure.csproj ./backend/src/DejaGroove.Infrastructure/

RUN dotnet restore ./backend/DejaGroove.sln

COPY backend ./backend
WORKDIR /src/backend
RUN dotnet publish src/DejaGroove.Api/DejaGroove.Api.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:9.0@sha256:8567214d8c1de2a7f6c3341a3d42367eb7d1be5a28c90bdbd8cf1cf71f319630 AS final
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "DejaGroove.Api.dll"]
