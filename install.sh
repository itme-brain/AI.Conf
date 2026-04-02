#!/usr/bin/env bash
set -euo pipefail

# install.sh — symlinks agent-team into ~/.claude/
# Works on Windows (Git Bash/MSYS2), Linux, and macOS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
AGENTS_SRC="$SCRIPT_DIR/agents"
SKILLS_SRC="$SCRIPT_DIR/skills"
RULES_SRC="$SCRIPT_DIR/rules"
AGENTS_DST="$CLAUDE_DIR/agents"
SKILLS_DST="$CLAUDE_DIR/skills"
RULES_DST="$CLAUDE_DIR/rules"
CLAUDE_MD_SRC="$SCRIPT_DIR/CLAUDE.md"
CLAUDE_MD_DST="$CLAUDE_DIR/CLAUDE.md"
SETTINGS_SRC="$SCRIPT_DIR/settings.json"
SETTINGS_DST="$CLAUDE_DIR/settings.json"

# Detect OS
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Darwin*)               OS="macos"   ;;
    Linux*)                OS="linux"   ;;
    *)                     OS="unknown" ;;
esac

echo "Detected OS: $OS"
echo "Source:       $SCRIPT_DIR"
echo "Target:       $CLAUDE_DIR"
echo ""

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR"

# Symlink a directory
create_symlink() {
    local src="$1"
    local dst="$2"
    local name="$3"

    # Check if source exists
    if [ ! -d "$src" ]; then
        echo "ERROR: Source directory not found: $src"
        exit 1
    fi

    # Handle existing target
    if [ -L "$dst" ]; then
        echo "Removing existing symlink: $dst"
        rm "$dst"
    elif [ -d "$dst" ]; then
        local backup="${dst}.backup.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing $name to: $backup"
        mv "$dst" "$backup"
    fi

    # Create symlink
    if [ "$OS" = "windows" ]; then
        # Convert paths to Windows format for mklink
        local win_src
        local win_dst
        win_src="$(cygpath -w "$src")"
        win_dst="$(cygpath -w "$dst")"
        if ! cmd //c "mklink /D \"$win_dst\" \"$win_src\"" > /dev/null 2>&1; then
            echo "ERROR: mklink failed for $name."
            echo "On Windows, enable Developer Mode (Settings > Update & Security > For Developers)"
            echo "or run this script as Administrator."
            exit 1
        fi
    else
        ln -s "$src" "$dst"
    fi

    echo "Linked: $dst -> $src"
}

# Symlink a single file
create_file_symlink() {
    local src="$1"
    local dst="$2"
    local name="$3"

    # Check if source exists
    if [ ! -f "$src" ]; then
        echo "ERROR: Source file not found: $src"
        exit 1
    fi

    # Handle existing target
    if [ -L "$dst" ]; then
        echo "Removing existing symlink: $dst"
        rm "$dst"
    elif [ -f "$dst" ]; then
        local backup="${dst}.backup.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing $name to: $backup"
        mv "$dst" "$backup"
    fi

    # Create symlink
    if [ "$OS" = "windows" ]; then
        local win_src
        local win_dst
        win_src="$(cygpath -w "$src")"
        win_dst="$(cygpath -w "$dst")"
        if ! cmd //c "mklink \"$win_dst\" \"$win_src\"" > /dev/null 2>&1; then
            echo "ERROR: mklink failed for $name."
            echo "On Windows, enable Developer Mode (Settings > Update & Security > For Developers)"
            echo "or run this script as Administrator."
            exit 1
        fi
    else
        ln -s "$src" "$dst"
    fi

    echo "Linked: $dst -> $src"
}

create_symlink      "$AGENTS_SRC"    "$AGENTS_DST"    "agents"
create_symlink      "$SKILLS_SRC"    "$SKILLS_DST"    "skills"
create_symlink      "$RULES_SRC"     "$RULES_DST"     "rules"
create_file_symlink "$CLAUDE_MD_SRC" "$CLAUDE_MD_DST" "CLAUDE.md"
create_file_symlink "$SETTINGS_SRC"  "$SETTINGS_DST"  "settings.json"

echo ""
echo "Done. Open Claude Code and load the orchestrate skill to begin."
