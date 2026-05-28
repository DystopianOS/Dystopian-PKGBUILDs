# Dystopian PKGBUILDS - Automated Package Management System

🚀 **An intelligent, automated system for managing Arch Linux PKGBUILD packages with support for multiple update strategies including GitHub releases, git commits, submodules, and forked repositories.**

## 🎯 Features

### 🔄 **Multi-Source Package Updates**
- **GitHub Releases**: Automatically detects and updates to latest releases
- **Git Tags**: Falls back to latest tags when releases aren't available  
- **Git Commits**: Date-based versioning for bleeding-edge packages
- **Submodules**: Smart submodule update detection and synchronization
- **Forked Repositories**: Automatic upstream synchronization

### 🤖 **Intelligent Automation**
- **Priority-based Updates**: Release → Tag → Head commit detection
- **Package Type Detection**: Supports Python, Node.js, Rust, Go, CMake projects
- **Build System Recognition**: Automatic detection of build requirements
- **Parallel Processing**: Concurrent package updates for efficiency
- **Dry Run Mode**: Test updates without making changes

### 🛡️ **Safety & Validation**
- **Syntax Validation**: PKGBUILD syntax checking before commits
- **Non-destructive Operations**: Backup and rollback capabilities
- **Configurable Automation**: Fine-grained control over update behavior
- **Manual Override**: Force updates or disable automation per package

## 📁 Repository Structure

```
Dystopian-PKGBUILDS/
├── .github/workflows/
│   ├── package-auto-update.yml     # Main package update workflow
│   └── submodule-fork-monitor.yml  # Submodule and fork synchronization
├── scripts/
│   └── package-analyzer.sh         # Local analysis and management script
├── package-config.yml              # Global configuration
├── copilot-api-proxy/              # Example package directory
│   └── PKGBUILD                    # Package build script
└── README.md                       # This file
```

## 🚀 Quick Start

### 1. **Initialize Repository**
```bash
# Clone or create your PKGBUILD repository
git clone <your-repo-url>
cd your-pkgbuild-repo

# Initialize with default configuration
./scripts/package-analyzer.sh init
```

### 2. **Add Your Packages**
Create package directories with PKGBUILD files:
```bash
mkdir my-package
cd my-package
# Create PKGBUILD file (see example below)
```

### 3. **Scan Packages**
```bash
# Analyze all packages in repository
./scripts/package-analyzer.sh scan

# Check for updates
./scripts/package-analyzer.sh check

# Validate all PKGBUILDs
./scripts/package-analyzer.sh validate
```

### 4. **Enable Automation**
The GitHub Actions workflows will automatically:
- Run every 6 hours to check for updates
- Update packages based on their configuration
- Commit changes with descriptive messages
- Generate update summaries

## 📦 Example PKGBUILD

The included `copilot-api-proxy` package demonstrates a git-based package:

```bash
# Maintainer: Dystopian <dystopian@example.com>
pkgname=claude-api-proxy
pkgver=0.1.0
pkgrel=1
pkgdesc="API proxy for Claude AI services"
arch=('any')
url="https://github.com/DCx7C5/claude-api-proxy"
license=('MIT')
depends=('python' 'python-pip')
source=("${pkgname}::git+${url}.git#branch=main")
sha256sums=('SKIP')

pkgver() {
    cd "${pkgname}"
    printf "0.1.0.r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

# ... rest of PKGBUILD
```

## ⚙️ Configuration

### Package-Specific Configuration
Edit `package-config.yml` to customize behavior per package:

```yaml
packages:
  copilot-api-proxy:
    type: "git"
    source: "https://github.com/DCx7C5/claude-api-proxy"
    update_method: "git-commit"
    build_method: "python"
    auto_update: true
    update_frequency: "daily"
    semantic_versioning: true        # NEW: Enable semantic versioning
    gpg_signing: false              # NEW: Enable package signing
    run_validation: true            # NEW: Run comprehensive validation
```

### Global Settings
```yaml
global:
  default_update_frequency: "daily"
  max_parallel_updates: 5
  require_manual_approval: false
  create_pull_requests: false
  use_semantic_versioning: true     # NEW: Global semantic versioning
  
  # NEW: Dystopian Actions Integration
  dystopian_actions:
    version: "v1"                   # Dystopian actions version to use
    enable_gpg: true               # Enable GPG-related actions
    enable_validation: true        # Enable package validation actions
    
  # NEW: Build and Validation Settings
  validation:
    run_namcap: true               # Run namcap validation
    verify_sources: true           # Verify source checksums
    build_packages: false          # Build packages during validation
    upload_artifacts: false        # Upload build artifacts
```

## 🔧 Local Management

### Package Analyzer Script
The included script provides comprehensive local management:

```bash
# Show help
./scripts/package-analyzer.sh --help

# Scan with filters
./scripts/package-analyzer.sh scan --filter "^copilot.*" --type git

# Check specific package
./scripts/package-analyzer.sh check copilot-api-proxy

# Validate all PKGBUILDs
./scripts/package-analyzer.sh validate

# Show configuration
./scripts/package-analyzer.sh config
```

### Verbose Logging
```bash
# Enable debug logging
./scripts/package-analyzer.sh scan --verbose

# Quiet mode (errors only)
./scripts/package-analyzer.sh check --quiet
```

## 🤖 GitHub Actions Workflows

### 1. **Package Auto-Update** (`package-auto-update.yml`)

**Enhanced with Dystopian Actions Integration:**

**Triggers:**
- Schedule: Every 6 hours
- Manual: With comprehensive options

**Key Improvements:**
- **Dystopian Actions Integration**: Uses `aur-get-version`, `aur-updpkgsums`, `aur-validate-pkg`, `git-commit`, `git-stage-changes`, and `git-push-changes`
- **Semantic Versioning**: Integrated with `thenativeweb/get-next-version` for conventional commits
- **Enhanced Validation**: Automatic checksum updates and namcap validation
- **Smart Version Detection**: Multi-layered approach with fallbacks
- **Professional Commits**: Detailed commit messages with metadata

**Manual Trigger Options:**
```yaml
package_filter: "copilot.*"           # Filter by package name pattern
force_update: true                    # Force update even if no changes
dry_run: true                         # Show what would be updated
use_semantic_versioning: true         # Enable semantic versioning
```

### 2. **Submodule & Fork Monitor** (`submodule-fork-monitor.yml`)

**Enhanced with Advanced Git Operations:**

**Triggers:**
- Schedule: Every 4 hours
- Manual: With sync and versioning options

**Key Improvements:**
- **Automated Issue Creation**: Creates GitHub issues for manual intervention using `gh-create-issue`
- **Semantic Versioning**: Optional conventional commit integration
- **Enhanced Commit Messages**: Detailed metadata and co-author attribution
- **Smart Fork Sync**: Detects divergence and handles fast-forward merges
- **PKGBUILD Integration**: Automatic `_commit` variable updates

### 3. **Package Build & Validation** (`package-build-validation.yml`) - NEW!

**Comprehensive Package Testing Pipeline:**

**Features:**
- **Full GPG Integration**: Complete GPG setup, import, and signing pipeline
- **Multi-Stage Validation**: namcap, checksum verification, and build testing
- **Artifact Management**: Optional build artifact upload and archival
- **Professional Reporting**: Detailed build summaries and package information
- **Reusable Workflow**: Can be called from other workflows

**Usage:**
```yaml
# Call from another workflow
jobs:
  test-package:
    uses: ./.github/workflows/package-build-validation.yml
    with:
      package_name: "copilot-api-proxy"
      run_tests: true
      upload_artifacts: true
      sign_packages: true
    secrets:
      GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
```

## 📊 Package Types Supported

| Type | Source | Update Method | Example |
|------|---------|---------------|---------|
| **GitHub Release** | GitHub repos with releases | Latest release detection | `https://github.com/user/repo/releases` |
| **GitHub Tag** | GitHub repos with tags | Latest tag detection | `https://github.com/user/repo/tags` |
| **Git Commit** | Any git repository | Date-based versioning | `git+https://github.com/user/repo.git` |
| **Submodule** | Git submodules | Upstream commit tracking | Submodule directories |
| **Tarball** | HTTP archives | Version extraction (manual) | `https://example.com/archive.tar.gz` |

## 🏗️ Build System Detection

The system automatically detects build systems based on configuration files:

| Build System | Detection Files | Auto Dependencies |
|--------------|-----------------|-------------------|
| **Python** | `setup.py`, `pyproject.toml`, `requirements.txt` | `python-build`, `python-installer` |
| **Node.js** | `package.json`, `yarn.lock` | `nodejs`, `npm` |
| **Rust** | `Cargo.toml`, `Cargo.lock` | `rust`, `cargo` |
| **Go** | `go.mod`, `go.sum` | `go` |
| **CMake** | `CMakeLists.txt` | `cmake`, `make` |

## 🚨 Update Strategies

### 1. **Release-First Strategy** (Recommended)
```
Priority: GitHub Release → GitHub Tag → Git Commit
Best for: Stable packages with regular releases
```

### 2. **Git-First Strategy**
```
Priority: Git Commit → GitHub Tag → GitHub Release  
Best for: Development packages, bleeding-edge software
```

### 3. **Manual Strategy**
```
Priority: Manual updates only
Best for: Critical packages requiring human oversight
```

## 🔍 Monitoring & Notifications

### Workflow Summaries
Each workflow run generates detailed summaries including:
- **Package Scan Results**: Total packages, types distribution
- **Update Status**: What was updated, what failed
- **Version Changes**: Before/after version comparisons
- **Error Reports**: Detailed failure information

### Custom Notifications
Configure webhooks in `package-config.yml`:
```yaml
global:
  notification_webhook: "https://discord.com/api/webhooks/..."
```

## 🛠️ Advanced Usage

### Custom Version Patterns
Define custom version extraction patterns:
```yaml
packages:
  my-package:
    custom_version_pattern: '^release-(\d+\.\d+\.\d+)'
```

### Pre/Post Update Hooks
```yaml
hooks:
  pre_update:
    - "scripts/pre-update-hook.sh"
  post_update:
    - "scripts/post-update-hook.sh"
```

### Security Settings
```yaml
global:
  security:
    verify_signatures: true
    check_checksums: true
    trusted_sources:
      - "github.com"
      - "gitlab.com"
```

## 🧪 Testing

### Dry Run Mode
Test updates without making changes:
```bash
# Local testing
./scripts/package-analyzer.sh check --dry-run

# Workflow testing (manual trigger with dry_run: true)
```

### Validation
```bash
# Validate all PKGBUILDs
./scripts/package-analyzer.sh validate

# Check specific package
./scripts/package-analyzer.sh check copilot-api-proxy --force
```

## 🔧 Troubleshooting

### Common Issues

**1. Package Not Detected**
```bash
# Check package structure
./scripts/package-analyzer.sh scan --verbose --filter "package-name"
```

**2. Update Detection Fails**
```bash
# Debug update method
./scripts/package-analyzer.sh check package-name --verbose
```

**3. PKGBUILD Validation Errors**
```bash
# Validate syntax
./scripts/package-analyzer.sh validate
```

### Debug Mode
Enable verbose logging for detailed troubleshooting:
```bash
export LOG_LEVEL=debug
./scripts/package-analyzer.sh scan
```

## 🤝 Contributing

### Adding New Package Types
1. Update `detect_package_type()` in `package-analyzer.sh`
2. Add corresponding update method in workflows
3. Update configuration schema
4. Add tests and documentation

### Extending Build Systems
1. Add detection logic to `detect_build_method()`
2. Update dependencies in `package-config.yml`
3. Test with representative packages

## 📄 License

This package management system is designed for Arch Linux PKGBUILD automation. Individual packages maintain their own licenses as specified in their respective PKGBUILD files.

## 🔗 Related Projects

- **Arch User Repository (AUR)**: https://aur.archlinux.org/
- **PKGBUILD Documentation**: https://wiki.archlinux.org/title/PKGBUILD
- **Arch Linux Packaging Guidelines**: https://wiki.archlinux.org/title/Arch_package_guidelines
- **Dystopian Actions**: https://github.com/DCx7C5/actions
- **Get Next Version**: https://github.com/marketplace/actions/get-next-version

## 🎯 Key System Improvements

### 🔧 **Dystopian Actions Integration**
- **Professional Git Operations**: Uses `git-commit`, `git-stage-changes`, `git-push-changes` for robust version control
- **Comprehensive Validation**: Leverages `aur-validate-pkg`, `aur-updpkgsums` for package quality
- **GPG Signing Pipeline**: Complete GPG setup with `gpg-setup-home`, `gpg-import`, `gpg-set-ownertrust`, `gpg-preset-pass`
- **Version Management**: Smart version detection with `aur-get-version`, `tag-get-latest`

### 📈 **Semantic Versioning Support**
- **Conventional Commits**: Integration with `thenativeweb/get-next-version`
- **Automatic Version Bumping**: Smart version increments based on commit history
- **Release Management**: Automated release preparation with proper versioning

### 🛡️ **Enhanced Security & Validation**
- **Multi-Layer Validation**: namcap, checksum verification, source validation
- **GPG Package Signing**: Optional cryptographic package signing
- **Issue Automation**: Automatic GitHub issues for manual intervention scenarios
- **Artifact Management**: Secure build artifact handling and storage

### 🚀 **Advanced Automation Features**
- **Intelligent Fallbacks**: Release → Tag → Commit → Semantic versioning priority
- **Parallel Processing**: Concurrent package updates with conflict resolution
- **Professional Reporting**: Comprehensive workflow summaries and build reports
- **Reusable Components**: Modular workflow design for easy integration

### 🔄 **Complete Automation Pipeline**
```
1. Package Detection & Analysis
2. Multi-Source Update Checking
3. Semantic Version Calculation
4. PKGBUILD Updates & Validation
5. Checksum Updates
6. Package Building (optional)
7. GPG Signing (optional)
8. Professional Git Commits
9. Artifact Upload & Archival
10. Comprehensive Reporting
```

---

**🚀 Happy packaging with automated intelligence! 🤖**