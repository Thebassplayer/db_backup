#!/usr/bin/env bash
set -euo pipefail

# 0) Load .env if it exists (and export all its variables)
if [ -f .env ]; then
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

# 1) If the first argument is a valid env, use it as environment selector
case "${1:-}" in
  PROD|DEV|BOTH)
    env="$1"
    shift
    ;;
  *)
    env=""
    ;;
esac

# 2) Select environment interactively if not passed
if [ -z "$env" ]; then
    echo "Select environment to back up:"
    options=("PROD" "DEV" "BOTH" "EXIT")
    PS3="Enter choice (1–4): "
    select env in "${options[@]}"; do
      case $env in
        PROD|DEV|BOTH) break ;;
        EXIT) exit 0 ;;
        *) echo "Invalid choice, try again." ;;
      esac
    done
fi

# 4) Now capture ARG_CONN and ARG_OUT → after we shifted the args
ARG_CONN="${1:-}"
ARG_OUT="${2:-}"



# 5) Build timestamp
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# 6) Helper: perform backup for one environment
backup_env() {
  local env="$1"
  local var_name="${env}_DATABASE_URL"

  # Ensure URL provided
  if [ -z "$ARG_CONN" ] && [ -z "${!var_name:-}" ]; then
    echo "ERROR: Neither script argument nor \$$var_name is set for $env." >&2
    return 1
  fi

  # Determine connection string
  local conn="${ARG_CONN:-${!var_name}}"

  # Build lowercase env for paths
  local env_lower
  env_lower=$(echo "$env" | tr '[:upper:]' '[:lower:]')

  # Build output file path (using ARG_OUT if provided)
  local outfile="${ARG_OUT:-${env_lower}/${env_lower}_backup_${TIMESTAMP}.sql}"

  # Make sure the parent directory exists
  mkdir -p "$(dirname "$outfile")"

  # Extract password from connection string
  local password=""
  if [[ "$conn" =~ postgresql://[^:]+:([^@]+)@ ]]; then
    password="${BASH_REMATCH[1]}"
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [START] Full‐cluster dump of $env → $outfile"

  if [ -n "$password" ]; then
    PGPASSWORD="$password" pg_dumpall --dbname="$conn" > "$outfile"
  else
    pg_dumpall --dbname="$conn" > "$outfile"
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [DONE]  Full‐cluster dump of $env → $outfile"

  # ── rotate old backups: delete SQL >30 days old in this env’s folder
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CLEANUP] Removing $env_lower backups older than 30 days"
  find "${outfile%/*}" -type f -name "${env_lower}_backup_*.sql" -mtime +30 -delete
}


# 7) Build the list of environments to back up
if [ "$env" = "BOTH" ]; then
  envs=(PROD DEV)
else
  envs=("$env")
fi

# 8) Run backup for each selected environment
for e in "${envs[@]}"; do
  backup_env "$e" || exit 1
done
