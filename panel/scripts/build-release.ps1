# Windows 构建 release 包（无 bash 时使用）
param([string]$Version = "v0.3.1")

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $Root "panel\controller"))) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$Commit = (git -C $Root rev-parse --short HEAD)
$BuildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Dist = Join-Path $Root "panel\dist"
$Work = Join-Path $Dist "work"

Write-Host "[build-release] web..."
Push-Location (Join-Path $Root "panel\controller\web")
if (Test-Path "package-lock.json") { npm ci } else { npm install }
npm run build
Pop-Location

if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$controllerLd = "-X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Version=$Version -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Commit=$Commit -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Date=$BuildDate -X main.version=$Version"
$agentLd = "-X main.version=$Version"

function Build-Arch([string]$arch) {
    $stage = Join-Path $Work "linux-$arch"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $env:CGO_ENABLED = "0"
    $env:GOOS = "linux"
    $env:GOARCH = $arch
    Push-Location (Join-Path $Root "panel\controller")
    go build -trimpath -ldflags $controllerLd -o (Join-Path $stage "edge-tunnel-controller") ./cmd/edge-tunnel-controller
    Pop-Location
    Push-Location (Join-Path $Root "panel\agent")
    go build -trimpath -ldflags $agentLd -o (Join-Path $stage "edge-tunnel-agent") ./cmd/edge-tunnel-agent
    Pop-Location
    Copy-Item -Recurse (Join-Path $Root "panel\controller\web\dist") (Join-Path $stage "web")
    Copy-Item -Recurse (Join-Path $Root "panel\docs") (Join-Path $stage "docs")
    Copy-Item -Recurse (Join-Path $Root "panel\examples") (Join-Path $stage "examples")
    Copy-Item -Recurse (Join-Path $Root "panel\scripts") (Join-Path $stage "scripts")
    Set-Content -Path (Join-Path $stage "VERSION") -Value $Version -NoNewline
    $tar = Join-Path $Dist "edge-tunnel-panel-$Version-linux-$arch.tar.gz"
    Push-Location $stage
    tar -czf $tar .
    Pop-Location
    Write-Host "[build-release] $tar"
}

Build-Arch "amd64"
Build-Arch "arm64"

Push-Location $Dist
Get-ChildItem "edge-tunnel-panel-$Version-linux-*.tar.gz" | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    "$hash  $($_.Name)"
} | Set-Content SHA256SUMS
Pop-Location

Write-Host "[build-release] created:"
Get-ChildItem $Dist -File | Format-Table Name, Length
