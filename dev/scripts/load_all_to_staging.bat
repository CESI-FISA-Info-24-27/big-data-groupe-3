@echo off
echo ================================================================================
echo CHARGEMENT COMPLET DU STAGING
echo ================================================================================
echo.

python "%~dp0load_all_to_staging.py"

echo.
pause

