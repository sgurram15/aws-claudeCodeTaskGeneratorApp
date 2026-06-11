<#
Configure Claude Code + Claude Cowork for Amazon Bedrock on Windows.
Discovers workshop CloudFormation outputs, then writes the AWS profile,
Claude Code settings.json, and Cowork registry configuration on this laptop.
#>
$ErrorActionPreference = "Stop"

# --- Refresh PATH from registry -----------------------------------------------
# On the workshop Windows desktop, DCV sessions start before Phase 2 finishes
# installing software (AWS CLI, Git, Node, etc.), so the session PATH is stale.
# Re-read the machine + user PATH from the registry to pick up all installed tools.
$machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$env:PATH    = ($machinePath, $userPath | Where-Object { $_ }) -join ";"

# --- Model IDs (global cross-Region inference profiles) -----------------------
$SONNET = "global.anthropic.claude-sonnet-4-6"                     # primary
$HAIKU  = "global.anthropic.claude-haiku-4-5-20251001-v1:0"        # small/fast
$OPUS   = "global.anthropic.claude-opus-4-6-v1"

$PROFILE_NAME = "workshop"
$installDir = Join-Path $env:USERPROFILE "claude-code-with-bedrock"
$wsConfig   = Join-Path $env:USERPROFILE ".claude-workshop"
$awsDir     = Join-Path $env:USERPROFILE ".aws"
$claudeDir  = Join-Path $env:USERPROFILE ".claude"

# --- Discover CloudFormation outputs ------------------------------------------
$region = "us-east-1"
Write-Host "Discovering workshop resources in $region..."
$exports = aws cloudformation list-exports --region $region --output text --query "Exports[?starts_with(Name, 'Workshop-')].[Name,Value]" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: could not query CloudFormation exports in ${region}:"
    Write-Host "  $exports"
    Write-Host "Check that the AWS CLI is authenticated to the workshop account/region."
    Write-Host ("Current identity: " + (aws sts get-caller-identity --query Arn --output text 2>&1))
    exit 1
}
function Get-Export($name) {
    foreach ($line in @($exports)) {
        $parts = $line -split "`t"
        if ($parts[0] -eq $name) { return $parts[1] }
    }
}
$userPoolId   = Get-Export "Workshop-UserPoolId"
$clientId     = Get-Export "Workshop-AppClientId"
$roleArn      = Get-Export "Workshop-BedrockRoleArn"
$otelEndpoint = Get-Export "Workshop-OtelEndpoint"

if (-not $userPoolId -or -not $clientId -or -not $roleArn) {
    Write-Error "Could not find workshop CloudFormation exports in $region. Configure AWS CLI for the workshop account/region."
    exit 1
}
Write-Host "  User Pool: $userPoolId"
Write-Host "  OTEL endpoint: $otelEndpoint"

# --- Gather Cognito credentials -----------------------------------------------
$username = Read-Host "Cognito username (email)"
$securePw = Read-Host "Cognito password" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePw))

# --- Install helper scripts (written inline so this is the only file needed) --
New-Item -ItemType Directory -Force -Path $installDir, $wsConfig, $awsDir, $claudeDir | Out-Null

$credHelper = @'
$ErrorActionPreference = "Stop"
$configPath = if ($env:CLAUDE_WORKSHOP_CONFIG) { $env:CLAUDE_WORKSHOP_CONFIG } else { Join-Path $env:USERPROFILE ".claude-workshop\config.json" }
try {
    $cfg = Get-Content -Raw $configPath | ConvertFrom-Json
    $region = $cfg.region
    $authBody = @{ AuthFlow = "USER_PASSWORD_AUTH"; ClientId = $cfg.client_id; AuthParameters = @{ USERNAME = $cfg.username; PASSWORD = $cfg.password } } | ConvertTo-Json
    $auth = Invoke-RestMethod -Method Post -Uri "https://cognito-idp.$region.amazonaws.com/" -Headers @{ "X-Amz-Target" = "AWSCognitoIdentityProviderService.InitiateAuth" } -ContentType "application/x-amz-json-1.1" -Body $authBody
    $idToken = $auth.AuthenticationResult.IdToken
    $session = ($cfg.username -split "@")[0]
    $stsParams = @{ Action = "AssumeRoleWithWebIdentity"; Version = "2011-06-15"; RoleArn = $cfg.role_arn; RoleSessionName = $session; WebIdentityToken = $idToken }
    $sts = Invoke-RestMethod -Method Post -Uri "https://sts.$region.amazonaws.com/" -ContentType "application/x-www-form-urlencoded" -Body $stsParams
    $c = $sts.AssumeRoleWithWebIdentityResponse.AssumeRoleWithWebIdentityResult.Credentials
    [ordered]@{ Version = 1; AccessKeyId = $c.AccessKeyId; SecretAccessKey = $c.SecretAccessKey; SessionToken = $c.SessionToken; Expiration = $c.Expiration } | ConvertTo-Json -Compress
    exit 0
} catch { [Console]::Error.WriteLine("credential-process: $_"); exit 1 }
'@
Set-Content -Encoding ASCII (Join-Path $installDir "credential-process.ps1") $credHelper

$otelHelper = @'
$configPath = if ($env:CLAUDE_WORKSHOP_CONFIG) { $env:CLAUDE_WORKSHOP_CONFIG } else { Join-Path $env:USERPROFILE ".claude-workshop\config.json" }
try { $email = (Get-Content -Raw $configPath | ConvertFrom-Json).username } catch { $email = "unknown" }
[ordered]@{ "x-user-email" = $email; "x-user-id" = $email; "x-user-name" = $email } | ConvertTo-Json -Compress
'@
Set-Content -Encoding ASCII (Join-Path $installDir "otel-helper.ps1") $otelHelper

$credCmd = "powershell -NoProfile -File `"$installDir\credential-process.ps1`" --profile $PROFILE_NAME"
$otelCmd = "powershell -NoProfile -File `"$installDir\otel-helper.ps1`""

# --- Shared workshop config ---------------------------------------------------
@{
    region = $region; user_pool_id = $userPoolId; client_id = $clientId
    role_arn = $roleArn; username = $username; password = $password
} | ConvertTo-Json | Set-Content -Encoding ASCII (Join-Path $wsConfig "config.json")

# --- AWS named profile --------------------------------------------------------
$awsConfigPath = Join-Path $awsDir "config"
$existing = if (Test-Path $awsConfigPath) { Get-Content $awsConfigPath -Raw } else { "" }
$existing = [regex]::Replace($existing, "(?ms)^\[profile $PROFILE_NAME\].*?(?=^\[|\Z)", "")
$stanza = "[profile $PROFILE_NAME]`r`ncredential_process = $credCmd`r`nregion = $region`r`n"
Set-Content -Encoding ASCII $awsConfigPath ($existing.TrimEnd() + "`r`n`r`n" + $stanza)

# --- Claude Code settings.json ------------------------------------------------
$env = [ordered]@{
    AWS_REGION                     = $region
    CLAUDE_CODE_USE_BEDROCK        = "1"
    AWS_PROFILE                    = $PROFILE_NAME
    AWS_CREDENTIAL_PROCESS         = $credCmd
    ANTHROPIC_MODEL                = $SONNET
    ANTHROPIC_SMALL_FAST_MODEL     = $HAIKU
    ANTHROPIC_DEFAULT_HAIKU_MODEL  = $HAIKU
    ANTHROPIC_DEFAULT_SONNET_MODEL = $SONNET
    ANTHROPIC_DEFAULT_OPUS_MODEL   = $OPUS
}
$settings = [ordered]@{ awsAuthRefresh = $credCmd; env = $env; includeCoAuthoredBy = $false; model = "sonnet" }
if ($otelEndpoint) {
    $env.CLAUDE_CODE_ENABLE_TELEMETRY = "1"
    $env.OTEL_METRICS_EXPORTER = "otlp"
    $env.OTEL_LOGS_EXPORTER = "otlp"
    $env.OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    $env.OTEL_EXPORTER_OTLP_ENDPOINT = $otelEndpoint
    $settings.otelHeadersHelper = $otelCmd
}
$settingsPath = Join-Path $claudeDir "settings.json"
if (Test-Path $settingsPath) {
    $ans = Read-Host "$settingsPath already exists. Overwrite? [y/N]"
    if ($ans -notmatch '^[Yy]') {
        $settingsPath = Join-Path $claudeDir "settings.workshop.json"
        Write-Host "  Keeping your existing settings.json; writing workshop settings to $settingsPath instead."
        Write-Host "  Merge the env / awsAuthRefresh / otelHeadersHelper keys into your settings.json."
    } else {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        Write-Host "  Backed up existing settings.json to settings.json.bak"
    }
}
$settings | ConvertTo-Json -Depth 5 | Set-Content -Encoding ASCII $settingsPath

# --- Claude Cowork configuration (saved for manual import; no lockdown) --------
# We deliberately do NOT write the managed policy key: a managed source makes Cowork
# read-only ("managed by your organization"). Instead we save the values and the user
# applies them once via Cowork's in-app window, which keeps the config editable.
# Undo any lockdown / broken local config a previous script version created.
Remove-Item "HKCU:\SOFTWARE\Policies\Claude" -Recurse -Force -ErrorAction SilentlyContinue
$cwLocal = Join-Path $env:LOCALAPPDATA "Claude-3p\configLibrary"
Remove-Item (Join-Path $cwLocal "workshop-bedrock.json"), (Join-Path $cwLocal "_meta.json") -Force -ErrorAction SilentlyContinue

$coworkCfg = [ordered]@{
    inferenceProvider             = "bedrock"
    inferenceBedrockRegion        = $region
    inferenceBedrockProfile       = $PROFILE_NAME
    inferenceModels               = @($SONNET, $OPUS, $HAIKU)
    isClaudeCodeForDesktopEnabled = $true
}
if ($otelEndpoint) {
    $coworkCfg.otlpEndpoint = $otelEndpoint
    $coworkCfg.otlpProtocol = "http/protobuf"
}
$coworkPath = Join-Path $wsConfig "cowork-config.json"
$coworkCfg | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $coworkPath

# Also keep an easy-to-find copy in the home directory for the Cowork import step.
$coworkHome = Join-Path $env:USERPROFILE "claude-cowork-config.json"
Copy-Item $coworkPath $coworkHome -Force

Write-Host ""
Write-Host "Claude Cowork - import this configuration (keeps it editable):"
Write-Host "  Saved config to: $coworkHome"
Write-Host "  1. Open Claude Cowork (do NOT sign in to Anthropic)."
Write-Host "  2. Help -> Troubleshooting -> Enable Developer Mode."
Write-Host "  3. Developer -> Configure third-party inference."
Write-Host "  4. Click 'Import configuration...' and choose $coworkHome."
Write-Host "  5. Click 'Apply Changes' and relaunch Cowork."

Write-Host "`nDone. Restart Claude Code/Cowork, then run 'claude' to start."
