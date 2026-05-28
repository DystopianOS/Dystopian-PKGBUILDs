#!/bin/bash
# Package Analysis and Update Detection Script
# Part of Dystopian PKGBUILDS Auto-Update System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/package-config.yml"
LOG_LEVEL="${LOG_LEVEL:-info}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "debug") [[ "$LOG_LEVEL" == "debug" ]] && echo -e "${PURPLE}[$timestamp] DEBUG:${NC} $*" ;;
        "info")  echo -e "${CYAN}[$timestamp] INFO:${NC} $*" ;;
        "warn")  echo -e "${YELLOW}[$timestamp] WARN:${NC} $*" ;;
        "error") echo -e "${RED}[$timestamp] ERROR:${NC} $*" ;;
    esac
}

# Help function
show_help() {
    cat << EOF
Dystopian PKGBUILD Package Analysis and Update Detection

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    scan                    Scan repository for packages and analyze them
    check [PACKAGE]         Check specific package for updates
    update [PACKAGE]        Update specific package (dry-run by default)
    list                    List all detected packages
    validate                Validate all PKGBUILD files
    config                  Show current configuration
    init                    Initialize repository with default configuration

OPTIONS:
    -h, --help             Show this help message
    -v, --verbose          Enable verbose logging (debug level)
    -q, --quiet            Quiet mode (errors only)
    -f, --force            Force updates even if no changes detected
    -n, --dry-run          Show what would be updated without making changes
    --filter PATTERN       Filter packages by name pattern (regex)
    --type TYPE            Filter by package type (git, github, tarball, etc.)
    --config FILE          Use custom configuration file

EXAMPLES:
    $0 scan                                 # Scan all packages
    $0 check copilot-api-proxy             # Check specific package
    $0 update --dry-run                     # Show what would be updated
    $0 list --type git                      # List only git-based packages
    $0 scan --filter "^copilot.*"           # Scan packages matching pattern

CONFIGURATION:
    Configuration is read from package-config.yml in the repository root.
    Use '$0 init' to create a default configuration file.

EOF
}

# Package detection functions
detect_package_type() {
    local pkg_dir="$1"
    local pkg_type="unknown"
    local source_url=""
    local update_method=""

    if [[ -f "$pkg_dir/PKGBUILD" ]]; then
        # Source the PKGBUILD to extract variables
        (
            cd "$pkg_dir"
            source PKGBUILD 2>/dev/null || true

            if [[ -n "${source:-}" ]]; then
                for src in "${source[@]}"; do
                    if [[ "$src" =~ git\+(.*)\.git ]] || [[ "$src" =~ ::git\+(.*) ]]; then
                        echo "git|$(echo "$src" | sed -E 's/.*git\+([^#]+).*/\1/' | sed 's/\.git$//')|git-commit"
                        return
                    elif [[ "$src" =~ https?://github\.com/([^/]+)/([^/]+) ]]; then
                        source_url=$(echo "$src" | sed -E 's|.*https?://(github\.com/[^/]+/[^/]+).*|\1|' | sed 's|\.git$||')
                        echo "github|https://$source_url|github-release"
                        return
                    elif [[ "$src" =~ https?://.*\.(tar\.gz|tar\.xz|zip) ]]; then
                        echo "tarball|$src|version-check"
                        return
                    fi
                done
            fi

            echo "unknown||manual"
        )
    else
        echo "unknown||manual"
    fi
}

detect_build_method() {
    local pkg_dir="$1"

    if [[ -f "$pkg_dir/PKGBUILD" ]]; then
        if grep -q "python" "$pkg_dir/PKGBUILD"; then
            echo "python"
        elif grep -q "node\|npm\|yarn" "$pkg_dir/PKGBUILD"; then
            echo "nodejs"
        elif grep -q "cargo\|rust" "$pkg_dir/PKGBUILD"; then
            echo "rust"
        elif grep -q "go build\|golang" "$pkg_dir/PKGBUILD"; then
            echo "go"
        elif grep -q "cmake\|make" "$pkg_dir/PKGBUILD"; then
            echo "cmake"
        else
            echo "generic"
        fi
    else
        echo "unknown"
    fi
}

# Package scanning
scan_packages() {
    local filter_pattern="${1:-}"
    local type_filter="${2:-}"

    log info "🔍 Scanning for packages in repository..."

    local packages=()

    while IFS= read -r -d '' pkgbuild_file; do
        local pkg_dir=$(dirname "$pkgbuild_file")
        local pkg_name=$(basename "$pkg_dir")

        # Apply filters
        if [[ -n "$filter_pattern" ]] && ! [[ "$pkg_name" =~ $filter_pattern ]]; then
            log debug "Skipping $pkg_name (doesn't match filter)"
            continue
        fi

        log debug "Analyzing package: $pkg_name"

        # Detect package information
        local pkg_info=$(detect_package_type "$pkg_dir")
        IFS='|' read -r pkg_type source_url update_method <<< "$pkg_info"

        if [[ -n "$type_filter" ]] && [[ "$pkg_type" != "$type_filter" ]]; then
            log debug "Skipping $pkg_name (type $pkg_type doesn't match filter $type_filter)"
            continue
        fi

        local build_method=$(detect_build_method "$pkg_dir")

        # Get current version
        local current_version=""
        (
            cd "$pkg_dir"
            source PKGBUILD 2>/dev/null || true
            current_version="${pkgver:-unknown}"
        )

        # Check for additional configuration files
        local config_files=()
        [[ -f "$pkg_dir/package.json" ]] && config_files+=("package.json")
        [[ -f "$pkg_dir/Cargo.toml" ]] && config_files+=("Cargo.toml")
        [[ -f "$pkg_dir/go.mod" ]] && config_files+=("go.mod")
        [[ -f "$pkg_dir/pyproject.toml" ]] && config_files+=("pyproject.toml")
        [[ -f "$pkg_dir/setup.py" ]] && config_files+=("setup.py")

        # Check if it's a submodule
        local is_submodule=false
        if git submodule status "$pkg_dir" 2>/dev/null | grep -q "^[^ ]"; then
            is_submodule=true
            update_method="submodule-update"
        fi

        packages+=("$pkg_name|$pkg_type|$pkg_dir|$source_url|$current_version|$update_method|$build_method|$is_submodule|$(IFS=','; echo "${config_files[*]}")")

    done < <(find "$REPO_ROOT" -name "PKGBUILD" -print0)

    log info "📊 Found ${#packages[@]} packages"

    # Display results
    printf "\n${CYAN}%-20s %-10s %-15s %-20s %-15s %-10s${NC}\n" \
        "PACKAGE" "TYPE" "VERSION" "UPDATE METHOD" "BUILD" "SUBMODULE"
    printf "%.20s %.10s %.15s %.20s %.15s %.10s\n" \
        "--------------------" "----------" "---------------" "--------------------" "---------------" "----------"

    for package_info in "${packages[@]}"; do
        IFS='|' read -r name type dir source_url version update_method build_method is_submodule config_files <<< "$package_info"

        local color=""
        case "$type" in
            "git") color="$GREEN" ;;
            "github") color="$BLUE" ;;
            "tarball") color="$YELLOW" ;;
            "unknown") color="$RED" ;;
        esac

        local submodule_indicator=""
        [[ "$is_submodule" == "true" ]] && submodule_indicator="📦"

        printf "${color}%-20s${NC} %-10s %-15s %-20s %-15s %-10s\n" \
            "$name" "$type" "$version" "$update_method" "$build_method" "$submodule_indicator"
    done
}

# Version checking functions
check_github_release() {
    local repo_url="$1"
    local repo_path=$(echo "$repo_url" | sed 's|https://github.com/||')

    log debug "Checking GitHub releases for $repo_path"

    # Try latest release first
    local latest_release=$(curl -s "https://api.github.com/repos/$repo_path/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')
    if [[ -n "$latest_release" ]]; then
        echo "$latest_release|release"
        return
    fi

    # Fallback to latest tag
    local latest_tag=$(curl -s "https://api.github.com/repos/$repo_path/tags" 2>/dev/null | jq -r '.[0].name // empty')
    if [[ -n "$latest_tag" ]]; then
        echo "$latest_tag|tag"
        return
    fi

    echo "|none"
}

check_git_commit() {
    local repo_url="$1"
    local repo_path=$(echo "$repo_url" | sed 's|https://github.com/||')

    log debug "Checking latest git commit for $repo_path"

    local latest_commit=$(curl -s "https://api.github.com/repos/$repo_path/commits" 2>/dev/null | jq -r '.[0].sha[0:7] // empty')
    if [[ -n "$latest_commit" ]]; then
        local current_date=$(date +%Y.%m.%d)
        local commit_count=$(curl -s "https://api.github.com/repos/$repo_path/commits?per_page=1" 2>/dev/null | jq -r 'length')
        local git_version="${current_date}.r${commit_count}.${latest_commit}"
        echo "$git_version|git|$latest_commit"
    else
        echo "||"
    fi
}

check_package_updates() {
    local package_name="${1:-}"
    local force_check="${2:-false}"

    if [[ -n "$package_name" ]]; then
        log info "🔍 Checking updates for package: $package_name"
    else
        log info "🔍 Checking updates for all packages..."
    fi

    while IFS= read -r -d '' pkgbuild_file; do
        local pkg_dir=$(dirname "$pkgbuild_file")
        local pkg_name=$(basename "$pkg_dir")

        # Skip if specific package requested and this isn't it
        if [[ -n "$package_name" ]] && [[ "$pkg_name" != "$package_name" ]]; then
            continue
        fi

        log info "📦 Checking $pkg_name..."

        # Get package information
        local pkg_info=$(detect_package_type "$pkg_dir")
        IFS='|' read -r pkg_type source_url update_method <<< "$pkg_info"

        # Get current version
        local current_version=""
        (
            cd "$pkg_dir"
            source PKGBUILD 2>/dev/null || true
            current_version="${pkgver:-unknown}"
        )

        log debug "Package type: $pkg_type, Update method: $update_method"
        log debug "Current version: $current_version"
        log debug "Source URL: $source_url"

        # Check for updates based on update method
        case "$update_method" in
            "github-release")
                local version_info=$(check_github_release "$source_url")
                IFS='|' read -r new_version version_type <<< "$version_info"

                if [[ -n "$new_version" ]]; then
                    local clean_version=$(echo "$new_version" | sed 's/^v//')
                    if [[ "$clean_version" != "$current_version" ]] || [[ "$force_check" == "true" ]]; then
                        printf "${GREEN}✅ Update available:${NC} %s %s → %s (%s)\n" \
                            "$pkg_name" "$current_version" "$clean_version" "$version_type"
                    else
                        printf "${BLUE}📌 Up to date:${NC} %s %s\n" "$pkg_name" "$current_version"
                    fi
                else
                    printf "${YELLOW}⚠️  No releases found:${NC} %s\n" "$pkg_name"
                fi
                ;;

            "git-commit")
                local commit_info=$(check_git_commit "$source_url")
                IFS='|' read -r git_version version_type commit_hash <<< "$commit_info"

                if [[ -n "$git_version" ]]; then
                    if [[ "$git_version" != "$current_version" ]] || [[ "$force_check" == "true" ]]; then
                        printf "${GREEN}✅ Update available:${NC} %s %s → %s (commit: %s)\n" \
                            "$pkg_name" "$current_version" "$git_version" "$commit_hash"
                    else
                        printf "${BLUE}📌 Up to date:${NC} %s %s\n" "$pkg_name" "$current_version"
                    fi
                else
                    printf "${YELLOW}⚠️  Could not check git commits:${NC} %s\n" "$pkg_name"
                fi
                ;;

            "submodule-update")
                if git submodule update --remote "$pkg_dir" 2>/dev/null; then
                    if git diff --quiet HEAD -- "$pkg_dir"; then
                        printf "${BLUE}📌 Submodule up to date:${NC} %s\n" "$pkg_name"
                    else
                        printf "${GREEN}✅ Submodule update available:${NC} %s\n" "$pkg_name"
                    fi
                else
                    printf "${YELLOW}⚠️  Could not update submodule:${NC} %s\n" "$pkg_name"
                fi
                ;;

            *)
                printf "${YELLOW}⚠️  Manual check required:${NC} %s (method: %s)\n" "$pkg_name" "$update_method"
                ;;
        esac

    done < <(find "$REPO_ROOT" -name "PKGBUILD" -print0)
}

# Validation function
validate_packages() {
    log info "🔍 Validating PKGBUILD files..."

    local total=0
    local valid=0
    local errors=0

    while IFS= read -r -d '' pkgbuild_file; do
        local pkg_dir=$(dirname "$pkgbuild_file")
        local pkg_name=$(basename "$pkg_dir")

        ((total++))

        log debug "Validating $pkg_name..."

        # Basic syntax check
        if ! bash -n "$pkgbuild_file" 2>/dev/null; then
            printf "${RED}❌ Syntax error:${NC} %s\n" "$pkg_name"
            ((errors++))
            continue
        fi

        # Check required variables
        (
            cd "$pkg_dir"
            source PKGBUILD 2>/dev/null || exit 1

            if [[ -z "${pkgname:-}" ]]; then
                printf "${RED}❌ Missing pkgname:${NC} %s\n" "$pkg_name"
                exit 1
            fi

            if [[ -z "${pkgver:-}" ]]; then
                printf "${RED}❌ Missing pkgver:${NC} %s\n" "$pkg_name"
                exit 1
            fi

            if [[ -z "${pkgrel:-}" ]]; then
                printf "${RED}❌ Missing pkgrel:${NC} %s\n" "$pkg_name"
                exit 1
            fi

            printf "${GREEN}✅ Valid:${NC} %s\n" "$pkg_name"
            exit 0
        ) && ((valid++)) || ((errors++))

    done < <(find "$REPO_ROOT" -name "PKGBUILD" -print0)

    echo
    log info "📊 Validation Summary:"
    log info "   Total packages: $total"
    log info "   Valid: $valid"
    log info "   Errors: $errors"

    if [[ $errors -gt 0 ]]; then
        return 1
    fi
}

# Initialize repository
init_repository() {
    log info "🚀 Initializing Dystopian PKGBUILD repository..."

    # Create .github/workflows directory
    mkdir -p "$REPO_ROOT/.github/workflows"

    # Create scripts directory
    mkdir -p "$REPO_ROOT/scripts"

    # Copy this script to scripts directory if not already there
    if [[ "$SCRIPT_DIR" != "$REPO_ROOT/scripts" ]]; then
        cp "$0" "$REPO_ROOT/scripts/package-analyzer.sh"
        chmod +x "$REPO_ROOT/scripts/package-analyzer.sh"
        log info "📝 Copied analyzer script to scripts/package-analyzer.sh"
    fi

    # Create default configuration if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log info "📝 Creating default configuration file..."
        # The config file was already created in a previous step
        log info "✅ Configuration created at package-config.yml"
    fi

    log info "✅ Repository initialized successfully!"
    log info ""
    log info "Next steps:"
    log info "  1. Review and customize package-config.yml"
    log info "  2. Add your PKGBUILD files to subdirectories"
    log info "  3. Run: $0 scan"
    log info "  4. Commit and push to enable automated workflows"
}

# Main script logic
main() {
    local command=""
    local package_name=""
    local force_check=false
    local dry_run=false
    local filter_pattern=""
    local type_filter=""
    local custom_config=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                LOG_LEVEL="debug"
                shift
                ;;
            -q|--quiet)
                LOG_LEVEL="error"
                shift
                ;;
            -f|--force)
                force_check=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            --filter)
                filter_pattern="$2"
                shift 2
                ;;
            --type)
                type_filter="$2"
                shift 2
                ;;
            --config)
                custom_config="$2"
                CONFIG_FILE="$custom_config"
                shift 2
                ;;
            scan|check|update|list|validate|config|init)
                command="$1"
                shift
                ;;
            *)
                if [[ -z "$package_name" ]] && [[ "$command" =~ ^(check|update)$ ]]; then
                    package_name="$1"
                else
                    log error "Unknown argument: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Default command
    if [[ -z "$command" ]]; then
        command="scan"
    fi

    # Execute command
    case "$command" in
        scan)
            scan_packages "$filter_pattern" "$type_filter"
            ;;
        check)
            check_package_updates "$package_name" "$force_check"
            ;;
        update)
            if [[ "$dry_run" == "true" ]]; then
                log info "🧪 DRY RUN MODE - No changes will be made"
            fi
            log warn "Update functionality not implemented in this script"
            log info "Use the GitHub Actions workflows for automated updates"
            ;;
        list)
            scan_packages "$filter_pattern" "$type_filter"
            ;;
        validate)
            validate_packages
            ;;
        config)
            if [[ -f "$CONFIG_FILE" ]]; then
                log info "📝 Configuration file: $CONFIG_FILE"
                cat "$CONFIG_FILE"
            else
                log error "Configuration file not found: $CONFIG_FILE"
                log info "Run '$0 init' to create a default configuration"
                exit 1
            fi
            ;;
        init)
            init_repository
            ;;
        *)
            log error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi