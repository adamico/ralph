#!/usr/bin/env bash
# Build the `<repo>-dragonruby` sbx template (ADR-0016).
#
# Snapshots an agent-specific sandbox template with CRuby 4.0.3 and the
# project bundle pre-installed so ralph can run lint without per-iteration setup
# cost. Default AGENT_CLI is codex, which starts from Docker's Codex sandbox
# template; set AGENT_CLI=claude only for legacy Claude-oriented imports.
#
# Re-run any time .ruby-version, Gemfile, or system deps change.

set -euo pipefail

AGENT_CLI="${AGENT_CLI:-codex}"
case "$AGENT_CLI" in
  codex|claude|pi) ;;
  *)
    echo "Error: unsupported AGENT_CLI '$AGENT_CLI' (expected codex, claude, or pi)." >&2
    exit 1
    ;;
esac

SANDBOX_NAME="${SANDBOX_NAME:-dragonruby}"
TEMPLATE_TAG="${TEMPLATE_TAG:-dragonruby}"
RUBY_VERSION="$(cat .ruby-version)"
RUBY_INSTALL_VERSION="${RUBY_INSTALL_VERSION:-0.10.2}"

echo ">> building $TEMPLATE_TAG (ruby $RUBY_VERSION)"

# --- network policy --------------------------------------------------
# cache.ruby-lang.org is not covered by the default `ruby-lang.org` rule
# (bare domain, no subdomain wildcard). Allow all ruby-lang.org subdomains
# globally so the template build (and future ralph iterations) can reach
# the CRuby source mirror and rubygems CDN.
sbx policy allow network -g "*.ruby-lang.org" 2>/dev/null || true
sbx policy allow network -g "*.rubygems.org" 2>/dev/null || true
sbx policy allow network -g "*.global.ssl.fastly.net" 2>/dev/null || true

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

EXISTING_RUBY=""
if sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SANDBOX_NAME"; then
  EXISTING_RUBY="$(sbx exec -i "$SANDBOX_NAME" bash -c 'ruby -v 2>/dev/null || true' 2>/dev/null || true)"
fi

if ! sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SANDBOX_NAME"; then
  echo ">> creating base sandbox from $AGENT_CLI template"
  sbx create --name "$SANDBOX_NAME" "$AGENT_CLI" .
fi

if [[ "$EXISTING_RUBY" == *"$RUBY_VERSION"* ]]; then
  echo ">> ruby $RUBY_VERSION already provisioned ($EXISTING_RUBY), skipping apt + compile"
  SKIP_RUBY=1
else
  SKIP_RUBY=0
fi

# --- in-sandbox provisioning -----------------------------------------
if [[ "$SKIP_RUBY" == "0" ]]; then
sbx exec -i -u root "$SANDBOX_NAME" bash -se <<EOF
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# wait for the upstream entrypoint's apt run to release the lock
for _ in \$(seq 1 120); do
  if ! fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    break
  fi
  echo "waiting for apt lock..."
  sleep 5
done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install -y --no-install-recommends \
  build-essential ca-certificates curl wget \
  libssl-dev libreadline-dev zlib1g-dev libyaml-dev \
  libffi-dev libgmp-dev libncurses-dev

# diag: can the container reach the cache?
curl -fsSL -A "ruby-build-script" -o /dev/null "https://cache.ruby-lang.org/pub/ruby/index.txt" || {
  echo "!!! container cannot reach cache.ruby-lang.org" >&2
  exit 1
}

# fetch + build CRuby directly (no ruby-install)
MAJOR_MINOR="\$(echo "${RUBY_VERSION}" | cut -d. -f1,2)"
TARBALL="ruby-${RUBY_VERSION}.tar.xz"
URL="https://cache.ruby-lang.org/pub/ruby/\${MAJOR_MINOR}/\${TARBALL}"

cd /usr/local/src
echo ">> downloading \$URL"
curl -fL --retry 5 --retry-delay 5 -A "ruby-build-script" -o "\$TARBALL" "\$URL"
tar -xJf "\$TARBALL"
cd "ruby-${RUBY_VERSION}"
./configure --prefix=/usr/local --disable-install-doc --enable-shared
make -j"\$(nproc)"
make install
cd /
rm -rf "/usr/local/src/ruby-${RUBY_VERSION}" "/usr/local/src/\$TARBALL"
ruby -v

# bundle dir must be writable by the default (non-root) sandbox user
mkdir -p /usr/local/bundle
chmod 1777 /usr/local/bundle
EOF
fi

# always re-assert perms (covers the SKIP_RUBY=1 path)
sbx exec -i -u root "$SANDBOX_NAME" bash -c 'mkdir -p /usr/local/bundle && chmod 1777 /usr/local/bundle'

# --- bundle ----------------------------------------------------------
sbx exec -i -w "$PWD" "$SANDBOX_NAME" bash -se <<'EOF'
set -euo pipefail
export BUNDLE_PATH=/usr/local/bundle
bundle config set --local path /usr/local/bundle
bundle config set --local without 'development'
bundle install --jobs 4
bundle exec rubocop -v
# drop bundler's compact_index cache — snapshot trips on its etag dirs
rm -rf "$HOME/.bundle/cache" /root/.bundle/cache 2>/dev/null || true
EOF

# --- dragonruby binary provisioning -----------------------------------
# Bake the linux-arm64 DragonRuby binary into the template.
# This is copied from the host and cached in the template, so run_tests
# never needs to download (sandbox is isolated; no credentials).
# Source path is overridable via DR_LINUX_ARM64_SRC env var.
# (Default: ~/Downloads/dragonruby-linux-arm64, matching user's unzipped install)
echo ">> provisioning dragonruby-linux-arm64 binary"

DR_SRC="${DR_LINUX_ARM64_SRC:-~/Downloads/dragonruby-linux-arm64}"
# Expand ~ to home directory
DR_SRC="${DR_SRC/#\~/$HOME}"

if [[ ! -d "$DR_SRC" ]]; then
  echo "ERROR: DragonRuby linux-arm64 source not found at: $DR_SRC" >&2
  echo "       Set DR_LINUX_ARM64_SRC to the unzipped engine directory" >&2
  exit 1
fi

sbx cp "$DR_SRC" "$SANDBOX_NAME":/opt/dragonruby-linux-arm64
sbx exec -i -u root "$SANDBOX_NAME" bash -c 'chmod -R a+rx /opt/dragonruby-linux-arm64'

# --- dr-update provisioning -------------------------------------------
# Install the sandbox-specific dr-update script that copies from
# /opt/dragonruby-linux-arm64 instead of downloading (no credentials needed).
echo ">> provisioning sandbox dr-update"
sbx cp .sbx/dr-update-sandbox "$SANDBOX_NAME":/tmp/dr-update
sbx exec -i -u root "$SANDBOX_NAME" bash -c 'chmod +x /tmp/dr-update && mv /tmp/dr-update /usr/local/bin/dr-update'

# --- snapshot --------------------------------------------------------
echo ">> snapshotting -> $TEMPLATE_TAG"
sbx stop "$SANDBOX_NAME" 2>/dev/null || true
printf 'y\n' | sbx template save "$SANDBOX_NAME" "$TEMPLATE_TAG"

if [[ "$KEEP" == "1" ]]; then
  echo ">> --keep: leaving scratch sandbox $SANDBOX_NAME running"
else
  echo ">> removing scratch sandbox (use --keep to retain for fast re-builds)"
  sbx rm --force "$SANDBOX_NAME"
fi

echo ">> done. template $TEMPLATE_TAG ready."
sbx template ls | grep -E "REPOSITORY|$TEMPLATE_TAG" || true
