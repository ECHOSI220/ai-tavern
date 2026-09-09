param([switch]$BuildOnly,[string]$ProjectName='ai-tavern-cloud')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$envFile=Join-Path $projectRoot 'server/.env.production.local'
if(!(Test-Path -LiteralPath $envFile)){throw 'Missing server/.env.production.local'}
$config=@{}
foreach($line in Get-Content -LiteralPath $envFile){if($line -match '^([A-Z_]+)=(.*)$'){$config[$matches[1]]=$matches[2].Trim().Trim('"').Trim("'")}}
$env:VITE_SUPABASE_URL=$config['SUPABASE_URL']
$env:VITE_SUPABASE_ANON_KEY=$config['SUPABASE_ANON_KEY']
$env:VITE_GAME_SERVER_URL=$config['GAME_SERVER_URL']
if(!$env:VITE_SUPABASE_URL -or !$env:VITE_SUPABASE_ANON_KEY){throw 'Missing public Supabase configuration'}
if($env:VITE_SUPABASE_URL -notmatch '^https://[a-z0-9]+\.supabase\.co$'){throw 'Invalid production Supabase URL'}
Push-Location (Join-Path $projectRoot 'community')
try {
 pnpm run build
 if($LASTEXITCODE -ne 0){throw 'Community build failed'}
 pnpm test
 if($LASTEXITCODE -ne 0){throw 'Community tests failed'}
 # Never bundle an admin secret, even if a future build script regresses.
 $secret=$config['SUPABASE_SERVICE_ROLE_KEY']
 if($secret){foreach($file in Get-ChildItem dist -Recurse -File){if([IO.File]::ReadAllText($file.FullName).Contains($secret)){throw 'Admin secret detected in public build'}}}
 if(!$BuildOnly){
  Push-Location (Join-Path $projectRoot 'server')
  try {pnpm exec wrangler --cwd ../community pages deploy dist --project-name $ProjectName --branch main
   if($LASTEXITCODE -ne 0){throw 'Pages deployment failed'}
  } finally {Pop-Location}
 }
} finally {Pop-Location;Remove-Item Env:VITE_SUPABASE_URL,Env:VITE_SUPABASE_ANON_KEY,Env:VITE_GAME_SERVER_URL -ErrorAction SilentlyContinue}
