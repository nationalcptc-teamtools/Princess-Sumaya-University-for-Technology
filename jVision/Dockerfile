FROM mcr.microsoft.com/dotnet/aspnet:5.0 AS base
WORKDIR /app
EXPOSE 7777

FROM mcr.microsoft.com/dotnet/sdk:5.0 AS build
WORKDIR /src
COPY ["Server/jVision.Server.csproj", "Server/"]
COPY ["Shared/jVision.Shared.csproj", "Shared/"]
COPY ["Client/jVision.Client.csproj", "Client/"]
RUN dotnet restore "Server/jVision.Server.csproj"
COPY . .

WORKDIR "/src/Server"
RUN dotnet build "jVision.Server.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "jVision.Server.csproj" -c Release -o /app/publish
COPY Server/jvis.db /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENV ASPNETCORE_URLS=http://+:7777 
ENV ASPNETCORE_ENVIRONMENT=DEVELOPMENT
ENTRYPOINT ["dotnet", "jVision.Server.dll"]