$ErrorActionPreference='Stop'
$projectRoot='D:\AI_Tavern_Project'
$config=@{}
foreach($line in Get-Content -LiteralPath (Join-Path $projectRoot 'server/.env.production.local')){if($line -match '^([A-Z_]+)=(.*)$'){$config[$matches[1]]=$matches[2].Trim()}}
foreach($key in @('GAME_SERVER_URL','SUPABASE_URL','SUPABASE_ANON_KEY')){if(!$config[$key]){throw "Missing $key"}}
foreach($key in @('GAME_SERVER_URL','SUPABASE_URL')){if($config[$key] -notmatch '^https://'){throw "Invalid $key"}}
Push-Location $projectRoot
try {
 & 'D:\AI_Tavern_Tools\flutter\bin\flutter.bat' build windows --release '--dart-define=APP_ENV=production' "--dart-define=GAME_SERVER_URL=$($config['GAME_SERVER_URL'])" "--dart-define=SUPABASE_URL=$($config['SUPABASE_URL'])" "--dart-define=SUPABASE_ANON_KEY=$($config['SUPABASE_ANON_KEY'])"
 if($LASTEXITCODE -ne 0){throw 'Windows build failed'}
 if(!(Test-Path -LiteralPath 'build/windows/x64/runner/Release/ai_tavern.exe')){throw 'Windows executable missing'}
}finally{Pop-Location}
