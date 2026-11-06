# Sourced by the build scripts: loads .env from the repo root (copy .env.example).
# Variables already set in the environment take precedence over .env.
# Expects the caller to have cd'ed into the repo root.

if [[ -f .env ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        key="${key#export }"
        [[ -z "$key" || "$key" == \#* ]] && continue
        [[ -n "${(P)key:-}" ]] || export "$key=${(Q)value%$'\r'}"
    done < .env
fi

require() { [[ -n "${(P)1:-}" ]] || { echo "error: $1 is not set (see .env.example)" >&2; exit 1; }; }

require BUNDLE_ID
export TEAM_ID="${TEAM_ID:-}"
export ORGANIZATION="${ORGANIZATION:-${BUNDLE_ID%.*}}"
