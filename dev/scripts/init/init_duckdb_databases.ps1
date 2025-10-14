# Initialisation des bases DuckDB pour le projet CHU
$ErrorActionPreference = "Stop"

Write-Host "Initialisation des bases DuckDB..." -ForegroundColor Cyan

# Créer le dossier si nécessaire
$duckdbPath = "data\duckdb"
if (-not (Test-Path $duckdbPath)) {
    New-Item -ItemType Directory -Path $duckdbPath -Force | Out-Null
}

# Chemins absolus
$projectRoot = Get-Location
$stagingPath = Join-Path $projectRoot "data\duckdb\staging.duckdb"
$odsPath = Join-Path $projectRoot "data\duckdb\ods.duckdb"
$initStagingScript = Join-Path $projectRoot "scripts\init_staging.sql"
$initOdsScript = Join-Path $projectRoot "scripts\init_ods.sql"

# 1. Initialiser STAGING (raw data)
Write-Host "`n[1/2] Initialisation de la base STAGING (raw data)..." -ForegroundColor Yellow
Write-Host "Chemin: $stagingPath"

if (Test-Path $initStagingScript) {
    Get-Content $initStagingScript | duckdb $stagingPath
    Write-Host "OK - STAGING creee" -ForegroundColor Green
} else {
    Write-Host "ERREUR: Script $initStagingScript introuvable!" -ForegroundColor Red
    exit 1
}

# 2. Initialiser ODS (cleaned data)
Write-Host "`n[2/2] Initialisation de la base ODS (cleaned data)..." -ForegroundColor Yellow
Write-Host "Chemin: $odsPath"

if (Test-Path $initOdsScript) {
    Get-Content $initOdsScript | duckdb $odsPath
    Write-Host "OK - ODS creee" -ForegroundColor Green
} else {
    Write-Host "ERREUR: Script $initOdsScript introuvable!" -ForegroundColor Red
    exit 1
}

# Vérification
Write-Host "`nVerification des bases..." -ForegroundColor Cyan

if (Test-Path $stagingPath) {
    $stagingSize = (Get-Item $stagingPath).Length / 1MB
    Write-Host "  - STAGING (raw) : $([math]::Round($stagingSize, 2)) MB"
} else {
    Write-Host "  - STAGING : Non trouvee" -ForegroundColor Red
}

if (Test-Path $odsPath) {
    $odsSize = (Get-Item $odsPath).Length / 1MB
    Write-Host "  - ODS (cleaned) : $([math]::Round($odsSize, 2)) MB"
} else {
    Write-Host "  - ODS : Non trouvee" -ForegroundColor Red
}

Write-Host "`nBases DuckDB initialisees avec succes!" -ForegroundColor Green
Write-Host "`nPour verifier :" -ForegroundColor White
Write-Host "  duckdb data\duckdb\staging.duckdb -c 'SELECT * FROM metadata.data_quality_check;'"
Write-Host "  duckdb data\duckdb\ods.duckdb -c 'SELECT * FROM metadata.data_quality_check;'"