#!/usr/bin/env bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🧪 Running BATS Tests...${NC}"

# Check if bats is available
if [ ! -f "testing/bats" ]; then
	echo -e "${YELLOW}BATS not found. Installing...${NC}"
	./testing/setup_bats.sh
fi

./testing/bats testing/*.bats

echo ""
echo -e "${YELLOW}📊 Test Coverage Info:${NC}"
if command -v kcov >/dev/null 2>&1; then
	echo "   Using kcov for coverage..."
	mkdir -p coverage
	kcov --include-pattern=k8s_ops_menu.sh coverage ./testing/bats testing/*.bats
	echo -e "${GREEN}   ✅ Coverage report generated in coverage/index.html${NC}"
else
	echo "   ❌ kcov not found. To enable coverage metrics:"
	echo "      sudo apt-get install kcov"
	echo ""
	echo "   (Without kcov, we only see Pass/Fail results)"
fi
