<#
Deploy helper for AlertLauk AI proxy.
This script will:
- prompt for GCP project, region, Studio endpoint and Studio API key
- create or add a Secret Manager secret `STUDIO_API_KEY`
- deploy the Cloud Function `chatProxy`
- update the repository `.env` `CHAT_BACKEND_URL` entry with deployed endpoint

Run in PowerShell (Windows):
  cd functions
  pwsh .\deploy.ps1

You must have `gcloud` installed and authenticated (or run in Cloud Shell).
#>

# Ensure gcloud exists
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  Write-Error "gcloud CLI not found. Install Google Cloud SDK or use Cloud Shell."
  exit 1
}

$project = Read-Host "GCP project id (e.g., gitlauk-e752f)"
if ([string]::IsNullOrWhiteSpace($project)) { Write-Error "Project id required"; exit 1 }

$region = Read-Host "Region (default: us-central1)"
if ([string]::IsNullOrWhiteSpace($region)) { $region = 'us-central1' }

$studioEndpoint = Read-Host "AI Studio / Generative endpoint URL (full url)"
if ([string]::IsNullOrWhiteSpace($studioEndpoint)) { Write-Error "Studio endpoint required"; exit 1 }

Write-Host "Enter your Studio API key (input hidden)"
$secureKey = Read-Host -AsSecureString "Studio API key"
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

Write-Host "Using project: $project, region: $region"

Write-Host "Setting gcloud project..."
gcloud config set project $project

Write-Host "Creating or updating Secret Manager secret STUDIO_API_KEY..."
$tmp = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmp -Value $plainKey -NoNewline

$describe = & gcloud secrets describe STUDIO_API_KEY --project=$project 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Secret exists — adding a new version..."
  & gcloud secrets versions add STUDIO_API_KEY --data-file=$tmp --project=$project
} else {
  Write-Host "Creating secret STUDIO_API_KEY..."
  & gcloud secrets create STUDIO_API_KEY --data-file=$tmp --replication-policy="automatic" --project=$project
}

Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Host "Deploying Cloud Function 'chatProxy'... this may take a minute"
& gcloud functions deploy chatProxy `
  --entry-point=app `
  --runtime=nodejs18 `
  --trigger-http `
  --allow-unauthenticated `
  --region=$region `
  --set-env-vars=STUDIO_API_URL="$studioEndpoint",MAX_PER_MINUTE=30 `
  --set-secrets=STUDIO_API_KEY=projects/$project/secrets/STUDIO_API_KEY:latest `
  --project=$project

if ($LASTEXITCODE -ne 0) { Write-Error "Deployment failed"; exit 1 }

Write-Host "Retrieving function URL..."
$funcUrl = & gcloud functions describe chatProxy --region=$region --format="value(httpsTrigger.url)" --project=$project
$funcUrl = $funcUrl.Trim()
if (-not $funcUrl) { Write-Error "Could not retrieve function URL"; exit 1 }

$chatEndpoint = "$funcUrl`/chat"
Write-Host "Deployed. Chat endpoint: $chatEndpoint"

# Update .env in repo root (one level up from functions)
$envPath = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envPath) {
  $lines = Get-Content $envPath
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^CHAT_BACKEND_URL=') {
      $lines[$i] = "CHAT_BACKEND_URL=$chatEndpoint"
      $found = $true
      break
    }
  }
  if (-not $found) { $lines += "`n# Added by deploy script"; $lines += "CHAT_BACKEND_URL=$chatEndpoint" }
  Set-Content -Path $envPath -Value $lines
  Write-Host ".env updated with CHAT_BACKEND_URL"
} else {
  Write-Host ".env not found at $envPath — create one and add: CHAT_BACKEND_URL=$chatEndpoint"
}

Write-Host "Done. You can now update your local .env or run the Flutter app."
