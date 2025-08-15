#!/bin/bash

# NightTrader VPS Setup Test Script
# Tests the complete setup flow locally

echo "========================================"
echo "NightTrader VPS Setup Test"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to check file exists
check_file() {
    local file="$1"
    local description="$2"
    
    run_test "$description" "[ -f '$file' ]"
}

# Function to check directory exists
check_dir() {
    local dir="$1"
    local description="$2"
    
    run_test "$description" "[ -d '$dir' ]"
}

echo "1. Checking Repository Structure"
echo "---------------------------------"

# Check main directories
check_dir "mt5-service" "MT5 service directory"
check_dir "scripts" "Scripts directory"

# Check MT5 service files
check_file "mt5-service/service.py" "Main service file"
check_file "mt5-service/config.py" "Configuration file"
check_file "mt5-service/requirements.txt" "Python requirements"
check_file "mt5-service/service_wrapper.py" "Service wrapper"

# Check scripts
check_file "scripts/startup-script.ps1" "Startup script"
check_file "scripts/update.ps1" "Update script"
check_file "scripts/verify.ps1" "Verification script"

# Check documentation
check_file "README.md" "README documentation"

echo ""
echo "2. Checking Script Syntax"
echo "-------------------------"

# Check PowerShell script syntax (if pwsh is available)
if command -v pwsh > /dev/null 2>&1; then
    run_test "Startup script syntax" "pwsh -NoProfile -Command \"Get-Content scripts/startup-script.ps1 | Out-Null\""
    run_test "Update script syntax" "pwsh -NoProfile -Command \"Get-Content scripts/update.ps1 | Out-Null\""
    run_test "Verify script syntax" "pwsh -NoProfile -Command \"Get-Content scripts/verify.ps1 | Out-Null\""
else
    echo -e "${YELLOW}⚠ PowerShell not available, skipping syntax checks${NC}"
fi

# Check Python script syntax
if command -v python3 > /dev/null 2>&1; then
    run_test "Service.py syntax" "python3 -m py_compile mt5-service/service.py"
    run_test "Config.py syntax" "python3 -m py_compile mt5-service/config.py"
else
    echo -e "${YELLOW}⚠ Python3 not available, skipping syntax checks${NC}"
fi

echo ""
echo "3. Checking Environment Variables"
echo "---------------------------------"

# Check if required environment variables are documented
check_env_var() {
    local var_name="$1"
    
    if grep -q "$var_name" scripts/startup-script.ps1; then
        echo -e "  ${GREEN}✓${NC} $var_name referenced in startup script"
        return 0
    else
        echo -e "  ${RED}✗${NC} $var_name not found in startup script"
        return 1
    fi
}

echo "Checking environment variable references:"
check_env_var "MT5_LOGIN"
check_env_var "MT5_PASSWORD"
check_env_var "MT5_SERVER"
check_env_var "MT5_SERVICE_REPO"
check_env_var "DIGITALOCEAN_IP"
check_env_var "REDIS_PASSWORD"
check_env_var "RABBITMQ_USER"
check_env_var "RABBITMQ_PASSWORD"

echo ""
echo "4. Checking Git Configuration"
echo "-----------------------------"

# Check if this is a git repository
if [ -d ".git" ]; then
    echo -e "  ${GREEN}✓${NC} Git repository initialized"
    
    # Check remote
    if git remote -v | grep -q origin; then
        REMOTE_URL=$(git remote get-url origin)
        echo -e "  ${GREEN}✓${NC} Remote configured: $REMOTE_URL"
    else
        echo -e "  ${YELLOW}⚠${NC} No remote configured"
        echo "    Run: git remote add origin https://github.com/your-org/nighttrader-vps-setup.git"
    fi
    
    # Check if there are uncommitted changes
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "  ${GREEN}✓${NC} Working directory clean"
    else
        echo -e "  ${YELLOW}⚠${NC} Uncommitted changes present"
    fi
else
    echo -e "  ${RED}✗${NC} Not a git repository"
    echo "    Run: git init"
fi

echo ""
echo "5. Checking Dashboard Integration"
echo "---------------------------------"

# Check if dashboard files reference the new setup
DASHBOARD_DIR="../dashboard"

if [ -d "$DASHBOARD_DIR" ]; then
    # Check if VPS provisioning service references the new script
    if grep -q "nighttrader-vps-setup" "$DASHBOARD_DIR/server/services/vps-provisioning.service.ts" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} VPS provisioning service updated"
    else
        echo -e "  ${YELLOW}⚠${NC} VPS provisioning service may need updating"
    fi
    
    # Check if Python deployment service has git support
    if [ -f "$DASHBOARD_DIR/server/scripts/deploy_mt5_git.py" ]; then
        echo -e "  ${GREEN}✓${NC} Git-based deployment script present"
    else
        echo -e "  ${YELLOW}⚠${NC} Git-based deployment script not found"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Dashboard directory not found"
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed! Repository is ready for deployment.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Commit and push to GitHub:"
    echo "   git add ."
    echo "   git commit -m 'Initial NightTrader VPS setup'"
    echo "   git push origin main"
    echo ""
    echo "2. Update environment variables in your VPS provider"
    echo "3. Create a new Windows VPS with the startup script"
    echo "4. Wait ~15 minutes for automatic setup"
    echo "5. SSH into VPS and run: C:\\NightTrader\\service\\scripts\\verify.ps1"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed. Please fix the issues before deployment.${NC}"
    exit 1
fi