#!/usr/bin/env bash
# ==============================================================================
# PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.18.0
# Cross-Platform Launcher for Linux (including Steam Deck / SteamOS) & macOS
# Created by @KodeMannn with the help of Gemini
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SCRIPT="$SCRIPT_DIR/Scan-PZModPerformance.ps1"

# ANSI Colors
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# 1. Check if pwsh is already in PATH
if command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$@"
fi

# 2. Check for local user-space portable pwsh
USER_PWSH="$HOME/.local/share/powershell/pwsh"
LOCAL_PWSH="$SCRIPT_DIR/.pwsh/pwsh"

if [ -x "$USER_PWSH" ]; then
    exec "$USER_PWSH" -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$@"
fi

if [ -x "$LOCAL_PWSH" ]; then
    exec "$LOCAL_PWSH" -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$@"
fi

# 3. Interactive Zero-Root / Package Manager Helper
echo -e "${CYAN}=================================================================${NC}"
echo -e "${YELLOW}   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.18.0  ${NC}"
echo -e "${CYAN}         Cross-Platform Runner for Linux & macOS                 ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo ""
echo -e " ${YELLOW}[!] PowerShell Core (pwsh) was not detected on your system.${NC}"
echo -e "     The suite requires PowerShell Core 7+ to run on Linux and macOS."
echo ""
echo -e " Choose how you would like to proceed:"
echo -e "  ${GREEN}[1] 1-Click Portable Download (Zero-Root / Zero-Sudo, Steam Deck Ready)${NC}"
echo -e "  [2] Show Native Package Manager Install Commands for Your OS"
echo -e "  [0] Exit"
echo ""
read -p " Select an option (0-2): " choice

case "$choice" in
    1)
        echo ""
        echo -e "${YELLOW}[*] Detecting platform architecture...${NC}"
        OS="$(uname -s)"
        ARCH="$(uname -m)"
        
        PWSH_VERSION="7.4.5"
        TARBALL_NAME=""

        if [ "$OS" = "Linux" ]; then
            if [ "$ARCH" = "x86_64" ]; then
                TARBALL_NAME="powershell-${PWSH_VERSION}-linux-x64.tar.gz"
            elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                TARBALL_NAME="powershell-${PWSH_VERSION}-linux-arm64.tar.gz"
            fi
        elif [ "$OS" = "Darwin" ]; then
            if [ "$ARCH" = "arm64" ]; then
                TARBALL_NAME="powershell-${PWSH_VERSION}-osx-arm64.tar.gz"
            else
                TARBALL_NAME="powershell-${PWSH_VERSION}-osx-x64.tar.gz"
            fi
        fi

        if [ -z "$TARBALL_NAME" ]; then
            echo -e "${RED}[ERROR] Unsupported OS ($OS) or architecture ($ARCH) for automatic download.${NC}"
            exit 1
        fi

        TARGET_DIR="$HOME/.local/share/powershell"
        DOWNLOAD_URL="https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/${TARBALL_NAME}"

        echo -e "${CYAN}[*] Downloading PowerShell Core v${PWSH_VERSION} into $TARGET_DIR...${NC}"
        echo -e "${GRAY}    Source: $DOWNLOAD_URL${NC}"
        
        mkdir -p "$TARGET_DIR"
        TMP_TAR="/tmp/$TARBALL_NAME"
        
        if command -v curl >/dev/null 2>&1; then
            curl -L -o "$TMP_TAR" "$DOWNLOAD_URL"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "$TMP_TAR" "$DOWNLOAD_URL"
        else
            echo -e "${RED}[ERROR] Neither curl nor wget was found. Please install curl or wget.${NC}"
            exit 1
        fi

        echo -e "${CYAN}[*] Extracting portable runtime...${NC}"
        tar -xzf "$TMP_TAR" -C "$TARGET_DIR"
        chmod +x "$TARGET_DIR/pwsh"
        rm -f "$TMP_TAR"

        echo -e "${GREEN}[SUCCESS] Portable PowerShell Core installed to $TARGET_DIR/pwsh!${NC}"
        echo -e "${CYAN}[*] Launching Project Zomboid Mod Performance Suite...${NC}\n"
        exec "$TARGET_DIR/pwsh" -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$@"
        ;;
    2)
        echo ""
        echo -e "${CYAN}-----------------------------------------------------------------${NC}"
        echo -e "${YELLOW}   NATIVE PACKAGE MANAGER INSTALL COMMANDS                       ${NC}"
        echo -e "${CYAN}-----------------------------------------------------------------${NC}"
        echo -e " ${GREEN}Steam Deck (SteamOS) / Arch Linux:${NC}"
        echo -e "   yay -S powershell-bin"
        echo -e "   ${GRAY}(Or choose Option [1] for zero-root portable install!)${NC}\n"
        echo -e " ${GREEN}Ubuntu / Debian / Linux Mint / Pop!_OS:${NC}"
        echo -e "   sudo apt update && sudo apt install -y powershell\n"
        echo -e " ${GREEN}Fedora / RHEL / AlmaLinux:${NC}"
        echo -e "   sudo dnf install -y powershell\n"
        echo -e " ${GREEN}macOS (Homebrew):${NC}"
        echo -e "   brew install --cask powershell\n"
        echo -e "${CYAN}-----------------------------------------------------------------${NC}"
        read -p "Press [Enter] to exit..."
        exit 0
        ;;
    0)
        echo -e "\nExiting."
        exit 0
        ;;
    *)
        echo -e "\n${RED}[!] Invalid selection.${NC}"
        exit 1
        ;;
esac
