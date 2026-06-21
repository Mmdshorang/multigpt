param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [switch]$Publish,
    [switch]$Run,
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "MultiCodex.Windows\MultiCodex.Windows.csproj"
$output = Join-Path $PSScriptRoot "dist"

if ($SelfContained) {
    $Publish = $true
}

if ($Publish) {
    New-Item -ItemType Directory -Force -Path $output | Out-Null

    if ($SelfContained) {
        dotnet publish $project `
            -c Release `
            -r win-x64 `
            --self-contained true `
            -p:PublishSingleFile=true `
            -p:IncludeNativeLibrariesForSelfExtract=true `
            -o $output
    } else {
        dotnet publish $project -c Release -o $output
    }

    Write-Host "MultiCodex Windows publish: $output\MultiCodex.exe"
} elseif ($Run) {
    dotnet run --project $project -c $Configuration
} else {
    dotnet build $project -c $Configuration
    Write-Host "MultiCodex Windows build: $Configuration"
}

if ($Run -and $Publish) {
    Start-Process -FilePath (Join-Path $output "MultiCodex.exe")
}
