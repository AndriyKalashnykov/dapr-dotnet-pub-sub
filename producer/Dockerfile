# syntax=docker/dockerfile:1.7
ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS build
WORKDIR /src

COPY Directory.Build.props ./
COPY common/common.csproj common/packages.lock.json common/
COPY producer/producer.csproj producer/packages.lock.json producer/

RUN dotnet restore producer/producer.csproj --locked-mode

COPY common/ common/
COPY producer/ producer/

RUN dotnet publish producer/producer.csproj \
    -c Release \
    --no-restore \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION} AS runtime
WORKDIR /app
COPY --from=build /app/publish .

USER 1000:1000

ENV ASPNETCORE_URLS=http://+:5232 \
    DAPR_APP_PORT=5232
EXPOSE 5232

ENTRYPOINT ["dotnet", "producer.dll"]
