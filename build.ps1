#---------------------------------------------------------------------------------------------
#  Copyright (c) Ian Lucas. All rights reserved.
#  Licensed under the MIT License. See License.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$SourceModRoot = (Join-Path $PSScriptRoot ".deps/sourcemod"),
    [string]$SourceModPackageRoot = (Join-Path $PSScriptRoot ".deps/sourcemod-package"),
    [string]$SourceModBranch = $env:SOURCEMOD_BRANCH,
    [string]$SourceModPackage = $env:SOURCEMOD_PACKAGE,
    [string]$Version = $env:VERSION
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceModBranch)) {
    $SourceModBranch = "1.12"
}
if ([string]::IsNullOrWhiteSpace($SourceModPackage)) {
    $SourceModPackage = "sourcemod-1.12.0-git7246"
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "0.1.0"
}
if ($Version -notmatch "^[0-9A-Za-z]+([._+-][0-9A-Za-z]+)*$") {
    throw "Invalid version: $Version"
}

function Get-AbsolutePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

function Invoke-NativeCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

$SourceModRoot = Get-AbsolutePath $SourceModRoot
$SourceModPackageRoot = Get-AbsolutePath $SourceModPackageRoot
$extensionRoot = Join-Path $PSScriptRoot "extensions/inventorysimulator"
$extensionBuild = Join-Path $extensionRoot "build"
$buildRoot = Join-Path $PSScriptRoot "build"
$packageRoot = Join-Path $buildRoot "package"
$extensionBinary = Join-Path $extensionBuild "inventorysimulator.ext.2.csgo.dll"
$pluginBinary = Join-Path $buildRoot "inventorysimulator.smx"
$archive = Join-Path $buildRoot "InventorySimulator-v$Version-windows.zip"
$sourceModSdk = Join-Path $SourceModRoot "public/smsdk_ext.cpp"

if (!(Test-Path -LiteralPath $sourceModSdk -PathType Leaf)) {
    throw "SourceMod SDK not found at $SourceModRoot"
}

Get-Command "cl.exe" -ErrorAction Stop | Out-Null
Get-Command "link.exe" -ErrorAction Stop | Out-Null

$sourcePawnCompiler = Join-Path $SourceModPackageRoot "addons/sourcemod/scripting/spcomp64.exe"
$sourcePawnInclude = Join-Path $SourceModPackageRoot "addons/sourcemod/scripting/include"
if (!(Test-Path -LiteralPath $sourcePawnCompiler -PathType Leaf)) {
    $dependencyRoot = Split-Path $SourceModPackageRoot -Parent
    $sourceModArchive = Join-Path $dependencyRoot "$SourceModPackage-windows.zip"
    $sourceModUrl = "https://sm.alliedmods.net/smdrop/$SourceModBranch/$SourceModPackage-windows.zip"

    New-Item -ItemType Directory -Force $dependencyRoot | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $sourceModUrl -OutFile $sourceModArchive
    Expand-Archive -Path $sourceModArchive -DestinationPath $SourceModPackageRoot -Force
}
if (!(Test-Path -LiteralPath $sourcePawnCompiler -PathType Leaf)) {
    throw "SourcePawn compiler not found at $sourcePawnCompiler"
}
if (!(Test-Path -LiteralPath $sourcePawnInclude -PathType Container)) {
    throw "SourcePawn includes not found at $sourcePawnInclude"
}

if (Test-Path -LiteralPath $extensionBuild) {
    Remove-Item -LiteralPath $extensionBuild -Recurse -Force
}
New-Item -ItemType Directory -Force $extensionBuild | Out-Null

$extensionIncludes = @(
    "/I$extensionRoot",
    "/I$(Join-Path $extensionRoot "sdk")",
    "/I$(Join-Path $SourceModRoot "public")",
    "/I$(Join-Path $SourceModRoot "sourcepawn/include")",
    "/I$(Join-Path $SourceModRoot "public/amtl")",
    "/I$(Join-Path $SourceModRoot "public/amtl/amtl")"
)
$compileArguments = @(
    "/nologo",
    "/c",
    "/std:c++17",
    "/W4",
    "/MT",
    "/GR-",
    "/DWIN32",
    "/D_WINDOWS"
)
$extensionObject = Join-Path $extensionBuild "extension.obj"
$attributeListObject = Join-Path $extensionBuild "attribute_list.obj"
$sourceModObject = Join-Path $extensionBuild "smsdk_ext.obj"

$extensionArguments = @(
    $compileArguments
    $extensionIncludes
    "/Fo$extensionObject"
    (Join-Path $extensionRoot "extension.cpp")
)
Invoke-NativeCommand -Command "cl.exe" -Arguments $extensionArguments

$attributeListArguments = @(
    $compileArguments
    $extensionIncludes
    "/Fo$attributeListObject"
    (Join-Path $extensionRoot "attribute_list.cpp")
)
Invoke-NativeCommand -Command "cl.exe" -Arguments $attributeListArguments

$sourceModArguments = @(
    $compileArguments
    $extensionIncludes[1..($extensionIncludes.Count - 1)]
    "/Fo$sourceModObject"
    $sourceModSdk
)
Invoke-NativeCommand -Command "cl.exe" -Arguments $sourceModArguments

$linkArguments = @(
    "/nologo",
    "/dll",
    "/machine:x86",
    "/out:$extensionBinary",
    $attributeListObject,
    $extensionObject,
    $sourceModObject
)
Invoke-NativeCommand -Command "link.exe" -Arguments $linkArguments
if (!(Test-Path -LiteralPath $extensionBinary -PathType Leaf)) {
    throw "Windows extension was not built"
}

New-Item -ItemType Directory -Force $buildRoot | Out-Null
$sourcePawnArguments = @(
    "-i",
    $sourcePawnInclude,
    "-i",
    (Join-Path $PSScriptRoot "scripting/include"),
    "-o",
    $pluginBinary,
    (Join-Path $PSScriptRoot "scripting/inventorysimulator.sp")
)
Invoke-NativeCommand -Command $sourcePawnCompiler -Arguments $sourcePawnArguments

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
$packageFiles = @(
    @{
        Source = $pluginBinary
        Destination = "addons/sourcemod/plugins/inventorysimulator.smx"
    },
    @{
        Source = $extensionBinary
        Destination = "addons/sourcemod/extensions/inventorysimulator.ext.2.csgo.dll"
    },
    @{
        Source = (Join-Path $PSScriptRoot "gamedata/inventorysimulator.games.txt")
        Destination = "addons/sourcemod/gamedata/inventorysimulator.games.txt"
    },
    @{
        Source = (Join-Path $PSScriptRoot "translations/inventorysimulator.phrases.txt")
        Destination = "addons/sourcemod/translations/inventorysimulator.phrases.txt"
    }
)
foreach ($file in $packageFiles) {
    if (!(Test-Path -LiteralPath $file.Source -PathType Leaf)) {
        throw "Package input not found: $($file.Source)"
    }
    $destination = Join-Path $packageRoot $file.Destination
    New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $file.Source -Destination $destination
}

if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive `
    -Path (Join-Path $packageRoot "*") `
    -DestinationPath $archive `
    -CompressionLevel Optimal
if (!(Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Windows release archive was not built"
}

Write-Host "Built $archive"
