# syntax=docker/dockerfile:1.7
# SPDX-License-Identifier: MIT
ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS build
WORKDIR /src

COPY Directory.Build.props ./
COPY common/common.csproj common/packages.lock.json common/
COPY consumer/consumer.csproj consumer/packages.lock.json consumer/

RUN dotnet restore consumer/consumer.csproj --locked-mode

COPY common/ common/
COPY consumer/ consumer/

RUN dotnet publish consumer/consumer.csproj \
    -c Release \
    --no-restore \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION} AS runtime
WORKDIR /app
COPY --from=build /app/publish .

USER 1000:1000

ENV ASPNETCORE_URLS=http://+:5231 \
    DAPR_APP_PORT=5231
EXPOSE 5231

ENTRYPOINT ["dotnet", "consumer.dll"]
