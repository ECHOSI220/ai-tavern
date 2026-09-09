param(
  [string]$ProjectRef = 'gveqrxurrvqfjawejwuh',
  [string]$GameServerUrl = 'https://gveqrxurrvqfjawejwuh.supabase.co/functions/v1/game-server-proxy',
  [switch]$SkipMigrations,
  [switch]$SkipSecrets
)

$ErrorActionPreference = 'Stop'

if (-not ('AiTavern.CredentialReader' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AiTavern {
  public static class CredentialReader {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential {
      public uint Flags; public uint Type; public IntPtr TargetName; public IntPtr Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist;
      public uint AttributeCount; public IntPtr Attributes; public IntPtr TargetAlias; public IntPtr UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", SetLastError = true)] private static extern void CredFree(IntPtr credential);
    public static string Read(string target) {
      IntPtr pointer;
      if (!CredRead(target, 1, 0, out pointer)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      try {
        var value = Marshal.PtrToStructure<Credential>(pointer);
        var bytes = new byte[value.CredentialBlobSize];
        Marshal.Copy(value.CredentialBlob, bytes, 0, bytes.Length);
        return System.Text.Encoding.UTF8.GetString(bytes).TrimEnd('\0');
      } finally { CredFree(pointer); }
    }
  }
}
'@
}

$accessToken = [AiTavern.CredentialReader]::Read('Supabase CLI:supabase')
if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'Supabase CLI 凭据为空' }
$headers = @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' }
$apiBase = 'https://api.supabase.com/v1'
$project = Invoke-RestMethod -Uri "$apiBase/projects/$ProjectRef" -Headers $headers -TimeoutSec 30
if ($project.status -notin @('ACTIVE_HEALTHY', 'COMING_UP')) { throw "Supabase 项目状态异常：$($project.status)" }

$keyResponse = Invoke-RestMethod -Uri "$apiBase/projects/$ProjectRef/api-keys" -Headers $headers -TimeoutSec 30
$keys = @()
foreach ($keyRecord in $keyResponse) { $keys += $keyRecord }
Write-Host "API key records: $((@($keys | ForEach-Object { "$($_.name)[$(($_.PSObject.Properties.Name -join '|'))]" }) -join ', '))"
$anon = ($keys | Where-Object { $_.name -in @('anon', 'publishable') } | Select-Object -First 1).api_key
$service = ($keys | Where-Object { $_.name -in @('service_role', 'secret') } | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($anon) -or [string]::IsNullOrWhiteSpace($service)) { throw 'Supabase 未返回客户端和服务器 API Key' }
$supabaseUrl = "https://$ProjectRef.supabase.co"

$migrationFiles = @(
  (Join-Path $PSScriptRoot '..\..\supabase\migrations\202609030001_production_multiplayer.sql'),
  (Join-Path $PSScriptRoot '..\..\supabase\migrations\202609050002_authority_hardening.sql')
)
if (-not $SkipMigrations) {
  foreach ($migrationFile in $migrationFiles) {
    $sql = [IO.File]::ReadAllText((Resolve-Path $migrationFile))
    $body = @{ query = $sql; read_only = $false } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri "$apiBase/projects/$ProjectRef/database/query" -Headers $headers -Body $body -TimeoutSec 180 | Out-Null
    Write-Host "Migration applied: $([IO.Path]::GetFileName($migrationFile))"
  }
}

$pnpm = 'C:\Users\私塾童鞋\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd'
if (-not $SkipSecrets) {
  Push-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
  try {
    foreach ($entry in @(
      @{ Name = 'SUPABASE_URL'; Value = $supabaseUrl },
      @{ Name = 'SUPABASE_ANON_KEY'; Value = $anon },
      @{ Name = 'SUPABASE_SERVICE_ROLE_KEY'; Value = $service }
    )) {
      $entry.Value | & $pnpm exec wrangler secret put $entry.Name --env production | Out-Host
      if ($LASTEXITCODE -ne 0) { throw "Cloudflare Secret 写入失败：$($entry.Name)" }
    }
  } finally { Pop-Location }
}

$verification = @{ query = "select to_regclass('public.room_metadata') as room_metadata, to_regprocedure('public.save_multiplayer_checkpoint(uuid,text,bigint,jsonb)') as checkpoint_rpc"; read_only = $true } | ConvertTo-Json -Compress
$result = @(Invoke-RestMethod -Method Post -Uri "$apiBase/projects/$ProjectRef/database/query" -Headers $headers -Body $verification -TimeoutSec 60)
if (-not $result[0].room_metadata -or -not $result[0].checkpoint_rpc) { throw '数据库验收失败：表或 checkpoint RPC 缺失' }

$localConfig = Join-Path $PSScriptRoot '..\.env.production.local'
[IO.File]::WriteAllLines($localConfig, @(
  '# 自动生成的本地正式环境公开配置；已被 .gitignore 排除。',
  "SUPABASE_PROJECT_REF=$ProjectRef",
  "GAME_SERVER_URL=$GameServerUrl",
  "SUPABASE_URL=$supabaseUrl",
  "SUPABASE_ANON_KEY=$anon",
  'SUPABASE_SERVICE_ROLE_KEY='
), [Text.UTF8Encoding]::new($false))

Write-Host "Production configured: project=$ProjectRef url=$supabaseUrl keys=hidden"
