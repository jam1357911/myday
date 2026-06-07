param(
  [string]$ProjectId,
  [string]$Region = "asia-east1",
  [string]$ServiceName = "daily-board",
  [string]$RepoName = "daily-board",
  [string]$ImageName = "daily-board"
)

$ErrorActionPreference = "Stop"

function Invoke-Gcloud([string]$ArgsLine) {
  $cmd = "gcloud $ArgsLine 2>&1"
  $output = & cmd.exe /d /s /c $cmd
  $code = $LASTEXITCODE
  $text = ($output | Out-String).TrimEnd()
  if ($code -ne 0) {
    throw "gcloud $ArgsLine failed ($code): $text"
  }
  return $text
}

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  throw "gcloud not found. Install Google Cloud SDK and ensure gcloud is in PATH."
}

if (-not $ProjectId) {
  $ProjectId = Read-Host "Enter Google Cloud Project ID"
}
if (-not $ProjectId) {
  throw "Project ID must not be empty."
}

$activeAccountRaw = ""
try {
  $activeAccountRaw = (& gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null | Select-Object -First 1)
} catch {}

$activeAccount = ""
if ($null -ne $activeAccountRaw) { $activeAccount = "$activeAccountRaw".Trim() }

if ([string]::IsNullOrWhiteSpace($activeAccount)) {
  Write-Host "No active gcloud login. Running: gcloud auth login"
  & gcloud auth login | Out-Host
}

if (-not [string]::IsNullOrWhiteSpace($activeAccount)) {
  $ans = Read-Host "Active account: $activeAccount. Use this account? (Y/N)"
  if ($ans.Trim().ToUpper() -ne "Y") {
    & gcloud auth login | Out-Host
  }
}

Invoke-Gcloud "config set project $ProjectId" | Out-Null

Write-Host "Enabling required services (Cloud Run / Artifact Registry / Cloud Build)..."
Invoke-Gcloud "services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com" | Out-Null

$repoExists = $true
try {
  Invoke-Gcloud "artifacts repositories describe $RepoName --location=$Region" | Out-Null
} catch {
  $repoExists = $false
}

if (-not $repoExists) {
  Write-Host "Creating Artifact Registry repository: $RepoName ($Region)..."
  Invoke-Gcloud "artifacts repositories create $RepoName --repository-format=docker --location=$Region" | Out-Null
}

$imageTag = "$Region-docker.pkg.dev/$ProjectId/$RepoName/${ImageName}:latest"

Write-Host "Build and push image: $imageTag"
Invoke-Gcloud "builds submit --tag `"$imageTag`" --suppress-logs --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET ." | Out-Host

Write-Host "Deploying Cloud Run service: $ServiceName ($Region)"
Invoke-Gcloud "run deploy $ServiceName --image `"$imageTag`" --region $Region --allow-unauthenticated" | Out-Host

$urlRaw = (& gcloud run services describe $ServiceName --region $Region --format="value(status.url)" 2>$null | Select-Object -First 1)
$url = if ($null -ne $urlRaw) { $urlRaw.Trim() } else { "" }
if ($url) {
  Write-Host "Done: $url"
} else {
  Write-Host "Done: Deployed to Cloud Run."
}
