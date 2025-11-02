# Pre-commit Hook Setup

This project uses a git pre-commit hook to ensure code quality before commits. The hook **automatically runs** formatting, linting, and compilation checks before allowing a commit to proceed.

## How Git Hooks Work

Git hooks are executable scripts in `.git/hooks/` that run automatically at specific git events. The `pre-commit` hook runs **automatically** every time you run `git commit` - there's no way to miss it (unless you use `--no-verify`).

**This is a standard git feature**: When you have an executable file at `.git/hooks/pre-commit`, git will run it automatically before every commit.

## What Happens When You Commit

When you try to commit code with `git commit`, the pre-commit hook **automatically** runs:

1. **Run Prettier** (with auto-fix) - Formats code to match project style
2. **Check Prettier** - Verifies all files are properly formatted
3. **Run Linters** - Checks Solidity (solhint) and TypeScript (eslint) code quality
4. **Compile Contracts** - Ensures all Solidity contracts compile successfully

If any of these checks fail, the commit will be blocked until the issues are fixed.

## Scripts Available

- `npm run pre-commit` - Manually run the pre-commit checks
- `npm run pre-commit:fix` - Attempt to auto-fix issues (shows errors for agent to fix)
- `npm run pre-commit:install` - Install/reinstall the git hook

## For LLM Agents

**IMPORTANT**: The pre-commit hook runs **automatically** on every `git commit`. You cannot forget about it - git will run it automatically.

**When committing code:**
1. Run `git commit` as normal
2. Git **automatically** runs `.git/hooks/pre-commit` before the commit
3. Hook runs: `prettier`, `prettier:check`, `lint`, `compile`
4. If all pass, commit proceeds
5. If any fail, commit is **blocked** and you see error messages

**When pre-commit hook fails:**

1. The hook outputs clear error messages showing what failed (you'll see this automatically)
2. Run `npm run pre-commit:fix` to see all errors clearly in one place
3. Use the `read_lints` tool to read linter errors programmatically
4. Fix the issues in the code using your editing tools
5. Run `npm run pre-commit` manually to verify fixes before committing again
6. Once all checks pass, run `git commit` again (hook runs automatically and should pass)

**Remember**: You don't need to manually run the hook - it runs automatically. But you can test it with `npm run pre-commit` before committing.

## Common Issues and Fixes

### Prettier Errors
- Most formatting errors can be auto-fixed by running `npm run prettier`
- Remaining errors will be shown and need manual fixes
- Check `.prettierrc.yaml` for formatting rules

### Linting Errors

#### Solidity Linting
- Solidity linting is done by `solhint` (configured in `.solhint.json`)
- Run `npm run lint:sol` to see Solidity-specific errors
- Some errors can be auto-fixed with `npm run sol:fix`
- Common issues: missing SPDX license, incorrect import order, function visibility

#### TypeScript/JavaScript Linting
- TypeScript linting is done by `eslint` (configured in `.eslintrc.yaml`)
- Run `npm run lint:ts` to see TypeScript-specific errors
- Common issues: unused imports, type errors, code style violations

### Compilation Errors
- Compilation errors usually indicate syntax errors or missing dependencies
- Check the compilation output for specific file and line numbers
- Ensure all Solidity imports resolve correctly
- Verify all interfaces match their implementations

## Disabling the Hook (Not Recommended)

If you absolutely need to bypass the hook (e.g., for emergency hotfixes):

```bash
git commit --no-verify -m "your message"
```

**Warning**: Only use `--no-verify` when absolutely necessary. It bypasses all quality checks and can lead to broken builds or code that doesn't meet project standards.

## Automatic Installation

The hook is automatically installed when you run:
- `npm install` (via postinstall script)
- `npm run setup` (if you add this script)

## Manual Installation

If you need to manually install or reinstall the hook:

```bash
npm run pre-commit:install
# or
bash scripts/install-pre-commit-hook.sh
```

## Project-Specific Checks

This project performs the following checks:

1. **Prettier Formatting** - Ensures consistent code formatting
   - Formats: `.js`, `.json`, `.md`, `.sol`, `.ts`
   - Config: `.prettierrc.yaml`

2. **Solidity Linting** - Ensures Solidity code quality
   - Tool: `solhint`
   - Config: `.solhint.json`
   - Checks: License, imports, visibility, complexity, etc.

3. **TypeScript Linting** - Ensures TypeScript/JavaScript code quality
   - Tool: `eslint`
   - Config: `.eslintrc.yaml`
   - Checks: Code style, unused variables, type safety

4. **Compilation** - Ensures contracts compile successfully
   - Tool: `hardhat compile`
   - Validates: Syntax, imports, types, interfaces

## Troubleshooting

### Hook not running
- Verify the hook is installed: `ls -la .git/hooks/pre-commit`
- Ensure it's executable: `chmod +x .git/hooks/pre-commit`
- Reinstall: `npm run pre-commit:install`

### Hook runs but checks fail
- Run `npm run pre-commit:fix` to see detailed errors
- Fix issues manually or use auto-fix commands
- Verify all dependencies are installed: `npm install`

### Hook is too slow
- The hook runs all checks which can take time
- Consider running checks manually before committing: `npm run pre-commit`
- For emergency commits, use `--no-verify` (not recommended)
