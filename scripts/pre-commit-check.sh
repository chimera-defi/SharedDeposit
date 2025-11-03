#!/bin/bash

# Pre-commit hook that ensures code quality checks pass
# This script runs before every commit and will fail if checks don't pass
#
# The hook automatically runs:
# 1. Prettier formatting (with auto-fix)
# 2. Solidity linting (solhint)
# 3. TypeScript linting (eslint)
# 4. Solidity compilation (hardhat compile)
#
# If any check fails, the commit is blocked.

set -e  # Exit on any error

echo "?? Running pre-commit checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if npm is available
if ! command -v npm &> /dev/null; then
    echo -e "${RED}? Error: npm is not installed or not in PATH${NC}"
    echo -e "${YELLOW}?? Install Node.js and npm: https://nodejs.org/${NC}"
    exit 1
fi

# Step 1: Run prettier (format code)
echo -e "${YELLOW}?? Step 1/4: Running Prettier (formatting code)...${NC}"
if ! npm run prettier; then
    echo -e "${RED}? Prettier formatting failed. Please fix the errors above.${NC}"
    echo -e "${YELLOW}?? Tip: Run 'npm run pre-commit:fix' to see detailed errors${NC}"
    exit 1
fi

# Step 2: Run prettier check (verify formatting)
echo -e "${YELLOW}?? Step 2/4: Checking Prettier formatting...${NC}"
if ! npm run prettier:check; then
    echo -e "${RED}? Prettier check failed. Some files are not properly formatted.${NC}"
    echo -e "${YELLOW}?? Tip: Run 'npm run prettier' to auto-format, then run 'npm run pre-commit:fix'${NC}"
    exit 1
fi

# Step 3: Run linting (Solidity + TypeScript)
echo -e "${YELLOW}?? Step 3/4: Running linters (Solidity + TypeScript)...${NC}"
if ! npm run lint; then
    echo -e "${RED}? Linting failed. Please fix the errors above.${NC}"
    echo -e "${YELLOW}?? Tip: Run 'npm run pre-commit:fix' to see detailed errors${NC}"
    exit 1
fi

# Step 4: Run compilation
echo -e "${YELLOW}?? Step 4/4: Compiling Solidity contracts...${NC}"
if ! npm run compile; then
    echo -e "${RED}? Compilation failed. Please fix the errors above.${NC}"
    echo -e "${YELLOW}?? Tip: Run 'npm run pre-commit:fix' to see detailed errors${NC}"
    exit 1
fi

echo -e "${GREEN}? All pre-commit checks passed!${NC}"
exit 0
