#!/usr/bin/env bash
set -euo pipefail

# Directory for test libraries
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$TEST_DIR/libs"

echo "🧪 Setting up BATS testing environment in $LIBS_DIR..."
mkdir -p "$LIBS_DIR"

# Helper to clone or update
clone_or_update() {
	local repo_url="$1"
	local dest_dir="$2"
	local name
	name="$(basename "$dest_dir")"

	if [ -d "$dest_dir" ]; then
		echo "   🔄 Updating $name..."
		git -C "$dest_dir" pull --quiet
	else
		echo "   📥 Cloning $name..."
		git clone --quiet --depth 1 "$repo_url" "$dest_dir"
	fi
}

# Install Core & Helpers
clone_or_update "https://github.com/bats-core/bats-core.git" "$LIBS_DIR/bats-core"
clone_or_update "https://github.com/bats-core/bats-support.git" "$LIBS_DIR/bats-support"
clone_or_update "https://github.com/bats-core/bats-assert.git" "$LIBS_DIR/bats-assert"

# Create a symlink for easy access if not exists
if [ ! -f "$TEST_DIR/bats" ]; then
	ln -s "$LIBS_DIR/bats-core/bin/bats" "$TEST_DIR/bats"
	echo "   🔗 Created symlink: $TEST_DIR/bats -> bats-core/bin/bats"
fi

echo "✅ BATS setup complete. Run tests with: ./testing/bats testing/*.bats"
