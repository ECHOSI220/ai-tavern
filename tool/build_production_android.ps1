param(
  [switch]$SkipPub
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$asciiProjectRoot = 'D:\AI_Tavern_Project'
if ($projectRoot -match '[^\x00-\x7F]' -and
    (Test-Path -LiteralPath (Join-Path $asciiProjectRoot 'pubspec.yaml'))) {
  $projectRoot = $asciiProjectRoot
}
$configPath = Join-Path $projectRoot 'server\.env.production.local'

if (-not (Test-Path -LiteralPath $configPath)) {
  throw "Missing production configuration: $configPath"
}

$config = @{}
foreach ($rawLine in Get-Content -LiteralPath $configPath) {
  $line = $rawLine.Trim()
  if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) {
    continue
  }
  $parts = $line.Split('=', 2)
  $config[$parts[0].Trim()] = $parts[1].Trim()
}

$required = @('GAME_SERVER_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY')
foreach ($name in $required) {
  if (-not $config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($config[$name])) {
    throw "Production configuration is missing $name"
  }
}

foreach ($name in @('GAME_SERVER_URL', 'SUPABASE_URL')) {
  $uri = $null
  if (-not [Uri]::TryCreate($config[$name], [UriKind]::Absolute, [ref]$uri) -or
      $uri.Scheme -ne 'https') {
    throw "$name must be an absolute HTTPS URL"
  }
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExecutable = if ($flutterCommand) {
  $flutterCommand.Source
} else {
  'D:\AI_Tavern_Tools\flutter\bin\flutter.bat'
}
if (-not (Test-Path -LiteralPath $flutterExecutable)) {
  throw 'Flutter was not found on PATH or in D:\AI_Tavern_Tools\flutter.'
}

$flutterArgs = @(
  'build',
  'apk',
  '--release',
  '--target-platform',
  'android-arm64',
  '--dart-define=APP_ENV=production',
  "--dart-define=GAME_SERVER_URL=$($config['GAME_SERVER_URL'])",
  "--dart-define=SUPABASE_URL=$($config['SUPABASE_URL'])",
  "--dart-define=SUPABASE_ANON_KEY=$($config['SUPABASE_ANON_KEY'])"
)
if ($SkipPub) {
  $flutterArgs += '--no-pub'
}

Write-Host 'Building production Android APK with validated public server configuration.'
Push-Location $projectRoot
try {
  & $flutterExecutable @flutterArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter build failed with exit code $LASTEXITCODE"
  }

  $apkPath = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "Flutter reported success but the APK is missing: $apkPath"
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($apkPath)
  try {
    $assetEntries = @(
      $archive.Entries | Where-Object {
        $_.FullName.StartsWith('assets/flutter_assets/', [StringComparison]::Ordinal)
      }
    )
    $assetManifest = $archive.GetEntry('assets/flutter_assets/AssetManifest.bin')
    $appLibrary = $archive.GetEntry('lib/arm64-v8a/libapp.so')
    if ($assetEntries.Count -lt 20 -or $null -eq $assetManifest) {
      throw "APK validation failed: Flutter assets were not packaged ($($assetEntries.Count) entries)."
    }
    if ($null -eq $appLibrary) {
      throw 'APK validation failed: arm64 libapp.so is missing.'
    }
  } finally {
    $archive.Dispose()
  }
  Write-Host "APK validation passed: $($assetEntries.Count) Flutter asset entries."
} finally {
  Pop-Location
}
