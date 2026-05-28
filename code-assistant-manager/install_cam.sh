#!/usr/bin/env bash
# Code Assistant Manager Installation Script (uv Edition)
# Production-ready installer using uv (Astral's ultra-fast Python package manager)
# Replaces pip + python -m build with uv tool + uv build for isolation, speed, and reliability
# Supports future PyPI release + Git source + local wheel builds
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}
print_error() {
    echo -e "${RED}✗${NC} $1"
}
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Install uv if not present (official one-liner, idempotent)
install_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        print_info "uv not found – installing latest version (Astral official installer)..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # Ensure it's in PATH for this session
        export PATH="$HOME/.cargo/bin:$PATH"
        if ! command -v uv >/dev/null 2>&1; then
            print_error "uv installation failed. Please install manually: https://docs.astral.sh/uv/getting-started/installation/"
            exit 1
        fi
        print_success "uv installed successfully"
    else
        print_success "uv already available ($(uv --version))"
    fi
}

# Check Python version (uv will handle the rest)
check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    print_info "System Python version: $PYTHON_VERSION"
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'; then
        print_success "Python 3.9+ compatible"
    else
        print_error "Python 3.9+ required"
        exit 1
    fi
}

# Install from PyPI (future-proof – currently falls back gracefully)
install_pypi() {
    print_header "Installing via uv tool (PyPI)"
    print_info "Attempting uv tool install from PyPI..."
    if uv tool install --reinstall code-assistant-manager; then
        print_success "Installed from PyPI (isolated tool environment)"
        return 0
    else
        print_warning "PyPI install not available yet (package not published) – falling back to local build"
        if build_and_install_local; then
            return 0
        else
            print_warning "Local build failed – will attempt source install"
            return 1
        fi
    fi
}

# Build wheel locally with uv (much faster than python -m build) and install
build_and_install_local() {
    print_header "Building & installing local wheel with uv"
    print_info "Ensuring uv build tools are ready..."
    uv build --wheel
    if ls dist/*.whl >/dev/null 2>&1; then
        WHEEL=$(ls dist/*.whl | head -n1)
        print_info "Built wheel: $WHEEL"
        if uv tool install --reinstall "$WHEEL"; then
            print_success "Installed from local wheel (uv tool)"
            return 0
        else
            print_warning "Wheel installation failed"
            return 1
        fi
    else
        print_warning "Build completed but no wheel found in dist/"
        return 1
    fi
}

# Install from Git source (cleanest production method – uv handles everything)
install_source() {
    print_header "Installing from Git source (uv tool)"
    print_info "Installing latest from https://github.com/Chat2AnyLLM/code-assistant-manager.git"
    if uv tool install --reinstall git+https://github.com/Chat2AnyLLM/code-assistant-manager.git; then
        print_success "Installed from Git source (isolated tool environment)"
        return 0
    else
        print_error "Git source install failed"
        exit 1
    fi
}

# Setup configuration (works with uv tool isolated venv)
setup_config() {
    print_header "Setting up configuration"
    mkdir -p ~/.config/code-assistant-manager

    # Detect uv tool Python environment (most reliable method)
    if command -v cam >/dev/null 2>&1; then
        CAM_BIN=$(command -v cam)
        VENV_BIN_DIR=$(dirname "$CAM_BIN")
        if [ -x "$VENV_BIN_DIR/python" ]; then
            PYTHON_CMD="$VENV_BIN_DIR/python"
            print_info "Using uv tool Python: $PYTHON_CMD"
        else
            PYTHON_CMD=python3
        fi
    else
        PYTHON_CMD=python3
    fi

    # Copy bundled configs from installed package
    pkg_dir=$($PYTHON_CMD -c "
import code_assistant_manager
import os
print(os.path.dirname(code_assistant_manager.__file__))
" 2>/dev/null || echo "")

    if [ -n "$pkg_dir" ]; then
        for file in config.yaml providers.json skill_repos.json; do
            if [ -f "$pkg_dir/$file" ] && [ ! -f "~/.config/code-assistant-manager/$file" ]; then
                cp "$pkg_dir/$file" "~/.config/code-assistant-manager/$file"
                print_success "Created $file"
            elif [ -f "$pkg_dir/$file" ]; then
                print_info "$file already exists, skipping"
            fi
        done
    else
        print_warning "Could not locate installed package for config files"
    fi

    # .env template
    if [ ! -f ~/.env ]; then
        touch ~/.env
        chmod 600 ~/.env
        cat > ~/.env << 'EOL'
# Add your API keys here (loaded automatically by CAM)
ANTHROPIC_API_KEY=sk-ant-...
GITHUB_TOKEN=ghp_...
GEMINI_API_KEY=...
# Add more providers as needed
EOL
        print_success "Created secure ~/.env (chmod 600)"
        print_info "Edit ~/.env with your API keys"
    fi
}

# Verify installation
verify_install() {
    print_header "Verifying installation"
    for cmd in cam code-assistant-manager; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_success "$cmd command found in PATH"
            VERSION=$("$cmd" --version 2>/dev/null || echo "unknown")
            print_info "Version: $VERSION"
        else
            print_warning "$cmd not found in PATH"
        fi
    done
    print_info "uv tool environment is isolated and upgradable with: uv tool upgrade code-assistant-manager"
}

# Uninstall
uninstall_package() {
    print_header "Uninstalling via uv tool"
    if uv tool uninstall code-assistant-manager 2>/dev/null || uv tool uninstall cam 2>/dev/null; then
        print_success "Uninstalled code-assistant-manager (uv tool)"
    else
        print_warning "No uv tool installation found"
    fi
}

# Purge user configuration
purge_config() {
    print_header "Purging user configuration"
    if [ -d "$HOME/.config/code-assistant-manager" ]; then
        rm -rf "$HOME/.config/code-assistant-manager"
        print_success "Removed ~/.config/code-assistant-manager"
    else
        print_warning "No user config directory found"
    fi
    if [ -f "$HOME/.env" ]; then
        rm -f "$HOME/.env"
        print_success "Removed ~/.env"
    else
        print_warning "No ~/.env file found"
    fi
}

# Show usage
show_usage() {
    cat << EOF
Code Assistant Manager Installer (uv Edition)
Usage: $0 [METHOD]
Methods:
    pypi     Install from PyPI (default, falls back gracefully)
    source   Install latest from Git (recommended for now)
    uninstall  Uninstall via uv tool
    uninstall-purge  Uninstall + remove all user config
    verify   Only verify current installation
Examples:
    $0                  # PyPI (future) or local build
    $0 source           # Git source (cleanest today)
    $0 verify
EOF
}

# Main logic
main() {
    print_header "Code Assistant Manager Installer (uv Edition)"
    install_uv
    check_python

    METHOD=${1:-pypi}
    case $METHOD in
        pypi)
            install_pypi
            setup_config
            verify_install
            ;;
        source)
            install_source
            setup_config
            verify_install
            ;;
        verify)
            verify_install
            ;;
        uninstall)
            uninstall_package
            ;;
        uninstall-purge)
            uninstall_package
            purge_config
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown method: $METHOD"
            show_usage
            exit 1
            ;;
    esac

    if [ "$METHOD" != "verify" ]; then
        print_success "Installation completed successfully! 🎉"
        echo ""
        print_info "Next steps:"
        echo "1. Edit ~/.env with your API keys"
        echo "2. Run 'cam doctor' to verify setup"
        echo "3. Launch interactive TUI: 'cam launch'"
        echo "4. Upgrade anytime: 'uv tool upgrade code-assistant-manager'"
        echo ""
        print_info "Documentation & commands:"
        echo "   cam --help"
        echo "   https://github.com/Chat2AnyLLM/code-assistant-manager"
    fi
}

main "$@"
