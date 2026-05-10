#!/bin/bash

TOOLCHAIN_DIR="/opt"
GITHUB_REPO="haarer/toolchain68k"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}INFO:${NC} $1"; }
success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
error() { echo -e "${RED}ERROR:${NC} $1"; }

http_get() {
    if command -v curl >/dev/null 2>&1; then
        curl -s "$1" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O - "$1" 2>/dev/null
    else
        echo "[]"
    fi
}

http_download() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url"
    else
        error "Neither curl nor wget found"
        return 1
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This operation requires root privileges"
        exit 1
    fi
}

detect_platform() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        echo "linux"
    fi
}

json_get() {
    local file="$1"
    local key="$2"
    grep "\"$key\":" "$file" 2>/dev/null | sed 's/.*"'$key'": *"\([^"]*\)".*/\1/'
}

extract_target_from_name() {
    local name="$1"
    if [[ "$name" =~ ^toolchain-([a-z0-9-]+)- ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

get_installed_toolchains() {
    for dir in "$TOOLCHAIN_DIR"/toolchain-*; do
        [ -e "$dir" ] || continue
        [ -L "$dir" ] && continue
        [ ! -d "$dir" ] && continue

        if [ ! -f "$dir/package.json" ]; then
            continue
        fi

        local name=$(json_get "$dir/package.json" "name")
        local version=$(json_get "$dir/package.json" "version")
        local target=$(extract_target_from_name "$name")

        if [ -n "$target" ] && [ -n "$version" ]; then
            echo "$target:$version:$dir:$name"
        fi
    done
}

list_installed() {
    info "Installed toolchains in $TOOLCHAIN_DIR:"
    echo "===================================================================================="
    printf "%-20s | %-15s | %s\n" "TARGET" "VERSION" "DIRECTORY"
    echo "------------------------------------------------------------------------------------"

    local count=0
    while IFS=: read -r target version dir name; do
        [ -z "$target" ] && continue
        printf "%-20s | %-15s | %s\n" "$target" "$version" "$name"
        ((count++))
    done < <(get_installed_toolchains)

    echo "===================================================================================="
    if [ $count -eq 0 ]; then
        warn "No toolchains installed"
    fi
}

fetch_releases() {
    http_get "https://api.github.com/repos/$GITHUB_REPO/releases" || echo "[]"
}

parse_download_urls() {
    local json="$1"
    echo "$json" | tr ',' '\n' | grep 'browser_download_url' | \
        sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/'
}

match_asset_for_platform() {
    local fname="$1"
    local platform="$2"

    if [[ "$fname" =~ toolchain-([a-z0-9-]+)-([a-zA-Z0-9_-]+)-gcc-([0-9.]+).tar.gz$ ]]; then
        local tc_target="${BASH_REMATCH[1]}"
        local tc_platform="${BASH_REMATCH[2]}"
        local tc_version="${BASH_REMATCH[3]}"

        local match=0
        if [ "$platform" = "linux" ]; then
            if [[ "$tc_platform" = "linux" ]] || [[ "$tc_platform" = "Debian" ]]; then
                match=1
            fi
        elif [ "$platform" = "alpine" ]; then
            if [ "$tc_platform" = "alpine" ]; then
                match=1
            fi
        fi

        if [ $match -eq 1 ]; then
            echo "$tc_target:$tc_version:$fname"
            return 0
        fi
    fi
    return 1
}

list_available() {
    info "Available toolchains from github.com/$GITHUB_REPO/releases:"
    echo "Fetching releases..."

    local releases=$(fetch_releases)
    local platform=$(detect_platform)

    echo "===================================================================================="
    echo "Platform: $platform"
    echo "===================================================================================="
    printf "%-20s | %-15s | %s\n" "TARGET" "VERSION" "STATUS"
    echo "------------------------------------------------------------------------------------"

    local installed=$(get_installed_toolchains)
    local found=0
    local seen=""

    for url in $(parse_download_urls "$releases"); do
        local fname=$(basename "$url")
        [ "$fname" = "manifest.json" ] && continue

        local match_result=$(match_asset_for_platform "$fname" "$platform")
        [ -z "$match_result" ] && continue

        local target=$(echo "$match_result" | cut -d: -f1)
        local version=$(echo "$match_result" | cut -d: -f2)

        echo "$seen" | grep -q "|$target|" && continue
        seen="${seen}|$target|"

        local status="${YELLOW}available${NC}"
        if echo "$installed" | grep -q "^$target:"; then
            local installed_ver=$(echo "$installed" | grep "^$target:" | cut -d: -f2)
            if [ "$installed_ver" = "$version" ]; then
                status="${GREEN}installed${NC}"
            else
                status="${YELLOW}upgradable ($installed_ver -> $version)${NC}"
            fi
        fi

        printf "%-20s | %-15s | %b\n" "$target" "$version" "$status"
        found=1
    done

    if [ $found -eq 0 ]; then
        warn "No toolchains found. Check network connection."
    fi

    echo "===================================================================================="
}

get_download_info_for_target() {
    local json="$1"
    local target="$2"
    local platform=$(detect_platform)

    for url in $(parse_download_urls "$json"); do
        local fname=$(basename "$url")
        [ "$fname" = "manifest.json" ] && continue

        local match_result=$(match_asset_for_platform "$fname" "$platform")
        [ -z "$match_result" ] && continue

        local t=$(echo "$match_result" | cut -d: -f1)
        local v=$(echo "$match_result" | cut -d: -f2)

        if [ "$t" = "$target" ]; then
            echo "$v:$fname:$url"
            return 0
        fi
    done
    return 1
}

download_and_install() {
    local target="$1"
    local releases=$(fetch_releases)

    local result=$(get_download_info_for_target "$releases" "$target")
    if [ -z "$result" ]; then
        error "Toolchain '$target' not found for your platform"
        info "Available targets: m68k-elf, arm-none-eabi, avr"
        return 1
    fi

    local version=$(echo "$result" | cut -d: -f1)
    local fname=$(echo "$result" | cut -d: -f2)
    local dl_url=$(echo "$result" | cut -d: -f3-)

    check_root

    local tmpdir=$(mktemp -d)
    info "Downloading $fname..."
    info "From: $dl_url"

    if ! http_download "$dl_url" "$tmpdir/$fname"; then
        error "Download failed"
        rm -rf "$tmpdir"
        return 1
    fi

    info "Extracting..."

    if ! tar -xzf "$tmpdir/$fname" -C "$tmpdir"; then
        error "Extraction failed"
        rm -rf "$tmpdir"
        return 1
    fi

    local content_dir=""
    local pkg_name=""
    local pkg_version=""

    if [ -f "$tmpdir/package.json" ]; then
        content_dir="$tmpdir"
        pkg_name=$(json_get "$content_dir/package.json" "name")
        pkg_version=$(json_get "$content_dir/package.json" "version")
    fi

    if [ -z "$pkg_name" ]; then
        for d in "$tmpdir"/*/; do
            [ -d "$d" ] || continue
            if [ -f "$d/package.json" ]; then
                content_dir="$d"
                pkg_name=$(json_get "$content_dir/package.json" "name")
                pkg_version=$(json_get "$content_dir/package.json" "version")
                break
            fi
        done
    fi

    if [ -z "$pkg_name" ]; then
        error "Could not read 'name' from extracted package.json"
        rm -rf "$tmpdir"
        return 1
    fi

    local install_dir="$TOOLCHAIN_DIR/$pkg_name"

    info "Directory name from package.json: $pkg_name"

    if [ -d "$install_dir" ]; then
        local old_version=""
        if [ -f "$install_dir/package.json" ]; then
            old_version=$(json_get "$install_dir/package.json" "version")
        fi
        if [ -n "$old_version" ]; then
            warn "Existing installation found: $pkg_name (version $old_version)"
        else
            warn "Existing installation found: $pkg_name"
        fi
        read -p "Replace with version $version? [y/N]: " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && { rm -rf "$tmpdir"; return 0; }
        rm -rf "$install_dir"
    fi

    mkdir -p "$TOOLCHAIN_DIR"

    if [ "$content_dir" = "$tmpdir" ]; then
        mkdir -p "$install_dir"
        for item in "$tmpdir"/*; do
            [ "$item" = "$tmpdir/$fname" ] && continue
            mv "$item" "$install_dir/"
        done
    else
        mv "$content_dir" "$install_dir"
    fi

    rm -rf "$tmpdir"

    success "Installed $pkg_name"
    info "  Version:  $pkg_version"
    info "  Location: $install_dir"
    echo
    info "To use: export PATH=\$PATH:$install_dir/bin"
}

remove_toolchain() {
    local target="$1"
    local found=0
    local version=""
    local dir=""
    local name=""

    while IFS=: read -r t v d n; do
        if [ "$t" = "$target" ]; then
            found=1
            version="$v"
            dir="$d"
            name="$n"
        fi
    done < <(get_installed_toolchains)

    if [ $found -eq 0 ]; then
        error "Toolchain '$target' is not installed"
        info "Use 'tcman list' to see installed toolchains"
        return 1
    fi

    info "Found: $name (version $version)"
    info "   at: $dir"

    read -p "Remove this toolchain? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return 0

    check_root

    rm -rf "$dir"
    success "Removed $name"
}

show_menu() {
    echo
    echo "=================================="
    echo "    TCMAN - Toolchain Manager"
    echo "=================================="
    echo
    echo "  1) List installed toolchains"
    echo "  2) List available toolchains"
    echo "  3) Install toolchain"
    echo "  4) Remove toolchain"
    echo "  q) Quit"
    echo
    echo "Platform: $(detect_platform)"
    echo
    read -p "Choose [1-4,q]: " choice

    case "$choice" in
        1) list_installed ;;
        2) list_available ;;
        3)
            echo
            echo "Targets: m68k-elf, arm-none-eabi, avr"
            read -p "Target to install: " target
            [ -n "$target" ] && download_and_install "$target"
            ;;
        4)
            echo
            list_installed
            echo
            read -p "Target to remove: " target
            [ -n "$target" ] && remove_toolchain "$target"
            ;;
        q|Q) exit 0 ;;
        *) error "Invalid option" ;;
    esac
}

main() {
    if [ $# -gt 0 ]; then
        case "$1" in
            list|ls) list_installed ;;
            available|avail) list_available ;;
            install)
                [ -z "$2" ] && { error "Usage: tcman install <target>"; exit 1; }
                download_and_install "$2"
                ;;
            remove|uninstall)
                [ -z "$2" ] && { error "Usage: tcman remove <target>"; exit 1; }
                remove_toolchain "$2"
                ;;
            help|--help|-h)
                echo "Usage: tcman [command]"
                echo
                echo "Commands:"
                echo "  list, ls        List installed toolchains"
                echo "  available       List available from GitHub"
                echo "  install <tgt>   Install (m68k-elf, arm-none-eabi, avr)"
                echo "  remove <tgt>    Remove installed toolchain"
                echo "  help            Show this help"
                echo
                echo "Run without args for interactive menu"
                ;;
            *) error "Unknown command: $1"; exit 1 ;;
        esac
        exit 0
    fi

    while true; do
        show_menu
        echo
        read -p "Press Enter to continue..." -r
    done
}

main "$@"
