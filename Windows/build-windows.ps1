param(
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "MultiCodex.Windows\MultiCodex.Windows.csproj"
$output = Join-Path $PSScriptRoot "dist"
if ($SelfContained) {
    dotnet publish $project `
        -c Release `
        -r win-x64 `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -o $output
} else {
    dotnet publish $project -c Release --no-restore -o $output
}

Write-Host "MultiCodex Windows build: $output\MultiCodex.exe"
