@echo off
REM Export du schéma RAW vers Markdown
echo ================================================
echo Export schema RAW de DuckDB vers Markdown
echo ================================================
echo.

python scripts/export_schema_to_md.py raw data/duckdb/staging.duckdb

echo.
echo ================================================
echo Export termine !
echo Fichier genere : SCHEMA_RAW_columns.md
echo ================================================
pause


