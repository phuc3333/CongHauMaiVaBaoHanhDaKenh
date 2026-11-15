#!/usr/bin/env bash
set -Eeuo pipefail

: "${HAU_MAI_APP_PASSWORD:?HAU_MAI_APP_PASSWORD must be set}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=ON_ERROR_STOP=1 <<'SQL'
\getenv app_password HAU_MAI_APP_PASSWORD
CREATE ROLE hau_mai_owner NOLOGIN;
CREATE ROLE hau_mai_app LOGIN PASSWORD :'app_password';
SQL
