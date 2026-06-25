# syntax=docker/dockerfile:1.7
# SPDX-License-Identifier: MIT
ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}@sha256:ea8bde36c11b6e7eec2656d0e59101d4462f6bd630730f2c8201ed0572b295d5 AS build
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

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}@sha256:7644f992230d35cf230017189d4038c0ae0f7388b13f4f7ae1900a155bafb597 AS runtime
WORKDIR /app
COPY --chown=1000:1000 --from=build /app/publish .

USER 1000:1000

# App listen port — operator-tunable at build time; mirrors compose/.env.example.
ARG APP_INTERNAL_PORT=5232
ENV ASPNETCORE_URLS=http://+:${APP_INTERNAL_PORT} \
    DAPR_APP_PORT=${APP_INTERNAL_PORT}
EXPOSE ${APP_INTERNAL_PORT}

ENTRYPOINT ["dotnet", "producer.dll"]
