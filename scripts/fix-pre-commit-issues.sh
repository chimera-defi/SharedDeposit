#!/bin/bash

# Auto-fix script for pre-commit issues
# This script attempts to automatically fix common issues that cause pre-commit failures
# The agent should run this when pre-commit checks fail
# This script will show all errors clearly so the agent can fix them

set +e  # Don't exit on error - we want to see all errors

echo "?? Attempting to fix pre-commit issues..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Maximum number of fix attempts
MAX_ATTEMPTS=3
ATTEMPT=1

# Track which checks are failing
PRETTIER_FAILED=false
LINT_FAILED=false
COMPILE_FAILED=false

# Main fix loop
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo ""
    echo -e "${BLUE}????????????????????????????????????????${NC}"
    echo -e "${BLUE}Fix Attempt $ATTEMPT of $MAX_ATTEMPTS${NC}"
    echo -e "${BLUE}????????????????????????????????????????${NC}"
    
    # Step 1: Run prettier (auto-fix formatting)
    echo ""
    echo -e "${YELLOW}?? Step 1: Running Prettier (auto-fixing formatting)...${NC}"
    if npm run prettier; then
        echo -e "${GREEN}? Prettier formatting passed${NC}"
        PRETTIER_FAILED=false
    else
        echo -e "${RED}? Prettier formatting has errors (shown above)${NC}"
        PRETTIER_FAILED=true
    fi
    
    # Step 2: Run prettier check
    echo ""
    echo -e "${YELLOW}?? Step 2: Checking Prettier formatting...${NC}"
    if npm run prettier:check 2>&1; then
        echo -e "${GREEN}? Prettier check passed${NC}"
        PRETTIER_FAILED=false
    else
        echo -e "${RED}? Prettier check has errors (shown above)${NC}"
        PRETTIER_FAILED=true
    fi
    
    # Step 3: Run linting
    echo ""
    echo -e "${YELLOW}?? Step 3: Running linters (Solidity + TypeScript)...${NC}"
    if npm run lint 2>&1; then
        echo -e "${GREEN}? Linting passed${NC}"
        LINT_FAILED=false
    else
        echo -e "${RED}? Linting has errors (shown above)${NC}"
        LINT_FAILED=true
    fi
    
    # Step 4: Run compilation
    echo ""
    echo -e "${YELLOW}?? Step 4: Compiling Solidity contracts...${NC}"
    if npm run compile 2>&1; then
        echo -e "${GREEN}? Compilation passed${NC}"
        COMPILE_FAILED=false
    else
        echo -e "${RED}? Compilation has errors (shown above)${NC}"
        COMPILE_FAILED=true
    fi
    
    # Check if all checks passed
    if [ "$PRETTIER_FAILED" = false ] && [ "$LINT_FAILED" = false ] && [ "$COMPILE_FAILED" = false ]; then
        echo ""
        echo -e "${GREEN}?? All checks passed after $ATTEMPT attempt(s)! ??${NC}"
        exit 0
    fi
    
    # Show summary of what's still failing
    echo ""
    echo -e "${YELLOW}?? Summary of failures:${NC}"
    [ "$PRETTIER_FAILED" = true ] && echo -e "${RED}  ? Prettier${NC}" || echo -e "${GREEN}  ? Prettier${NC}"
    [ "$LINT_FAILED" = true ] && echo -e "${RED}  ? Linting${NC}" || echo -e "${GREEN}  ? Linting${NC}"
    [ "$COMPILE_FAILED" = true ] && echo -e "${RED}  ? Compilation${NC}" || echo -e "${GREEN}  ? Compilation${NC}"
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo ""
        echo -e "${YELLOW}?? Please review the errors above and fix them. The agent should read the linter errors and fix them programmatically.${NC}"
        echo -e "${YELLOW}   After fixing, run this script again or run 'npm run pre-commit' to verify.${NC}"
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

# If we get here, we've exhausted all attempts
echo ""
echo -e "${RED}? Failed to fix all issues after $MAX_ATTEMPTS attempts${NC}"
echo -e "${YELLOW}????????????????????????????????????????${NC}"
echo -e "${YELLOW}The following checks are still failing:${NC}"
[ "$PRETTIER_FAILED" = true ] && echo -e "${RED}  ? Prettier${NC}"
[ "$LINT_FAILED" = true ] && echo -e "${RED}  ? Linting${NC}"
[ "$COMPILE_FAILED" = true ] && echo -e "${RED}  ? Compilation${NC}"
echo ""
echo -e "${YELLOW}?? The agent should:${NC}"
echo -e "${YELLOW}   1. Read the linter errors using read_lints tool${NC}"
echo -e "${YELLOW}   2. Fix the issues in the code${NC}"
echo -e "${YELLOW}   3. Run 'npm run pre-commit' again to verify${NC}"
exit 1
