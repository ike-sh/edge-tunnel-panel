# 发布 GitHub Release 资产（Windows PowerShell）
# 前置：gh auth login  或  $env:GH_TOKEN = "ghp_..."
# 用法：
#   .\panel\scripts\publish-release.ps1 -Version v0.3.1
#   .\panel\scripts\publish-release.ps1 -Version v0.3.1 -SkipBuild

param(
    [string]$Version = "v0.3.1",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $Root ".git"))) {
    $Root = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
}
$Dist = Join-Path $Root "panel\dist"

function Require-Gh {
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error @"
未检测到 gh 登录。请先执行：
  gh auth login
或设置环境变量：
  `$env:GH_TOKEN = '你的 GitHub PAT（需 repo 权限）'
"@
    }
}

if (-not $SkipBuild) {
    Write-Host "[publish] building release packages..."
    $env:VERSION = $Version
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        bash (Join-Path $Root "panel\scripts\build-release.sh")
    } else {
        & (Join-Path $PSScriptRoot "build-release.ps1") -Version $Version
    }
}

$amd = Join-Path $Dist "edge-tunnel-panel-$Version-linux-amd64.tar.gz"
$arm = Join-Path $Dist "edge-tunnel-panel-$Version-linux-arm64.tar.gz"
$sums = Join-Path $Dist "SHA256SUMS"
foreach ($f in @($amd, $arm, $sums)) {
    if (-not (Test-Path $f)) { throw "缺少构建产物: $f" }
}

Require-Gh

Write-Host "[publish] creating release $Version (if not exists)..."
$notes = Join-Path $Root "CHANGELOG.md"
$releaseExists = $false
gh release view $Version 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $releaseExists = $true }

if (-not $releaseExists) {
    if (Test-Path $notes) {
        gh release create $Version --title "$Version — 一键安装与生产部署" --notes-file $notes
    } else {
        gh release create $Version --title "$Version" --notes "Edge Tunnel Panel $Version"
    }
    if ($LASTEXITCODE -ne 0) { throw "gh release create 失败" }
}

Write-Host "[publish] uploading assets..."
gh release upload $Version $amd $arm $sums --clobber
if ($LASTEXITCODE -ne 0) { throw "gh release upload 失败" }

Write-Host "[publish] done: https://github.com/ike-sh/edge-tunnel-panel/releases/tag/$Version"
