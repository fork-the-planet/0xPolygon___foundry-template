#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <tag>" >&2
    exit 1
fi

tag="$1"
solc_version="0.8.34"
evm_version="prague"

repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")
job_name="${repo_name}-${tag}"
live_contracts_dir="${LIVE_CONTRACTS_DIR:-$repo_root/../live-contracts}"
target_dir="$live_contracts_dir/jobs/$job_name/build-info"

if [[ ! -d "$live_contracts_dir/jobs" ]]; then
    echo "live-contracts repo not found at $live_contracts_dir (make sure it's checked out or override with LIVE_CONTRACTS_DIR)" >&2
    exit 1
fi

cd "$repo_root"

if [[ -n $(git status --porcelain -- src foundry.toml soldeer.lock) ]]; then
    echo "src/, foundry.toml or soldeer.lock have uncommitted changes; commit first so source.yaml pins a commit that matches the build" >&2
    exit 1
fi

commit=$(git rev-parse HEAD)
repo_url=$(git remote get-url origin)
repo_url=${repo_url%.git}
repo_url=${repo_url/#git@github.com:/https:\/\/github.com\/}
forge_version=$(forge --version | sed -n 's/^forge Version: \([0-9][0-9.]*\).*/\1/p')
build_cmd="forge soldeer install && forge build src --build-info --evm-version $evm_version --use $solc_version"

forge clean
forge build src --build-info --evm-version "$evm_version" --use "$solc_version"

json_files=(out/build-info/*.json)
if [[ ${#json_files[@]} -ne 1 ]]; then
    echo "expected exactly one build-info file, found ${#json_files[@]}: ${json_files[*]}" >&2
    exit 1
fi

mkdir -p "$target_dir"
rm -f "$target_dir"/*.json
cp "${json_files[0]}" "$target_dir/$job_name.json"

cat > "$target_dir/source.yaml" <<EOF
type: source

# Provenance for the committed build-info. \`catapult provenance verify\` rebuilds
# the MeshPool contracts from the pinned commit and checks they byte-match. Deploys
# use the committed JSON; nothing is rebuilt during \`run\`.
build_info:
  "./$job_name.json":
    repo: "$repo_url"
    commit: "$commit"
    image: "ghcr.io/foundry-rs/foundry:v$forge_version"
    # foundry.toml pins neither solc nor evm-version, so both are pinned here.
    build: "$build_cmd"
EOF

echo "Exported to $target_dir:"
ls "$target_dir"
