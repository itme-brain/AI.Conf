#!/usr/bin/env bash
set -euo pipefail

# install.sh — symlinks agent-team into ~/.claude/ and ~/.codex/ (if present)
# Works on Windows (Git Bash/MSYS2), Linux, and macOS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
AGENTS_SRC="$SCRIPT_DIR/claude/agents"
SKILLS_SRC="$SCRIPT_DIR/skills"
RULES_SRC="$SCRIPT_DIR/rules"
TEAM_YAML="$SCRIPT_DIR/TEAM.yaml"
AGENTS_DST="$CLAUDE_DIR/agents"
SKILLS_DST="$CLAUDE_DIR/skills"
RULES_DST="$CLAUDE_DIR/rules"
CLAUDE_MD_SRC="$SCRIPT_DIR/claude/CLAUDE.md"
CLAUDE_MD_DST="$CLAUDE_DIR/CLAUDE.md"
SETTINGS_SRC="$SCRIPT_DIR/claude/settings.json"
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

# Pre-flight: require generated claude/ output before proceeding
if [ ! -d "$SCRIPT_DIR/claude" ]; then
    echo "Error: claude/ not found. Run ./generate.sh first."
    exit 1
fi

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

# Return one skill id per line for a target platform from TEAM.yaml.
# Falls back to empty output when TEAM.yaml is unavailable.
list_team_skills_for_target() {
    local target="$1"

    if [ ! -f "$TEAM_YAML" ]; then
        return 0
    fi

    # Validate TEAM parseability before resolving inventory.
    yq -e '.version == 1 and has("skills") and (.skills | has("order")) and (.skills | has("items"))' "$TEAM_YAML" > /dev/null

    local skill_id applies
    while IFS= read -r skill_id; do
        [ -n "$skill_id" ] || continue
        applies="$(yq -r ".skills.items.\"$skill_id\".applies_to[]? // \"\"" "$TEAM_YAML")"
        if printf '%s\n' "$applies" | grep -Fxq "$target"; then
            printf '%s\n' "$skill_id"
        fi
    done < <(yq -r '.skills.order[]' "$TEAM_YAML")
}

# Resolve a TEAM skill id to its source directory using instruction_file.
resolve_skill_dir_from_team() {
    local skill_id="$1"

    if [ ! -f "$TEAM_YAML" ]; then
        return 1
    fi

    local instruction_file skill_dir
    instruction_file="$(
        yq -r ".skills.items.\"$skill_id\".instruction_file // \"\"" "$TEAM_YAML"
    )"
    [ -n "$instruction_file" ] || return 1

    skill_dir="$(dirname "$SCRIPT_DIR/$instruction_file")"
    [ -d "$skill_dir" ] || return 1

    printf '%s\n' "$skill_dir"
}

create_symlink      "$AGENTS_SRC"    "$AGENTS_DST"    "agents"
create_symlink      "$SKILLS_SRC"    "$SKILLS_DST"    "skills"
create_symlink      "$RULES_SRC"     "$RULES_DST"     "rules"
create_file_symlink "$CLAUDE_MD_SRC" "$CLAUDE_MD_DST" "CLAUDE.md"
create_file_symlink "$SETTINGS_SRC"  "$SETTINGS_DST"  "settings.json"

# Codex CLI integration (optional — only if codex/ output exists)
CODEX_DIR="$HOME/.codex"

if [ -d "$SCRIPT_DIR/codex" ]; then
    echo ""
    echo "Codex output found — installing to $CODEX_DIR"
    mkdir -p "$CODEX_DIR"

    # Skills: symlink each skill directory into ~/.codex/skills/
    # (Can't replace the whole directory — .system/ must remain intact)
    mkdir -p "$CODEX_DIR/skills"
    if [ -f "$TEAM_YAML" ]; then
        team_codex_skills_tmp="$(mktemp)"
        if ! list_team_skills_for_target "codex" > "$team_codex_skills_tmp" 2>/dev/null; then
            echo "Warning: TEAM.yaml exists but could not be parsed; falling back to directory-based Codex skill install."
            for skill_dir in "$SKILLS_SRC"/*/; do
                skill_name="$(basename "$skill_dir")"
                create_symlink "$skill_dir" "$CODEX_DIR/skills/$skill_name" "codex skill: $skill_name"
            done
            rm -f "$team_codex_skills_tmp"
        else
            # TEAM is authoritative when present, including the explicit zero-skills case.
            while IFS= read -r skill_id; do
                [ -n "$skill_id" ] || continue
                skill_dir="$(resolve_skill_dir_from_team "$skill_id" || true)"
                if [ -z "$skill_dir" ]; then
                    echo "Warning: TEAM.yaml skill '$skill_id' has no valid instruction_file directory; skipping."
                    continue
                fi
                create_symlink "$skill_dir" "$CODEX_DIR/skills/$skill_id" "codex skill: $skill_id"
            done < "$team_codex_skills_tmp"
            rm -f "$team_codex_skills_tmp"
        fi
    else
        # Legacy fallback only when TEAM.yaml is absent.
        for skill_dir in "$SKILLS_SRC"/*/; do
            skill_name="$(basename "$skill_dir")"
            create_symlink "$skill_dir" "$CODEX_DIR/skills/$skill_name" "codex skill: $skill_name"
        done
    fi

    # Generated agents
    if [ -d "$SCRIPT_DIR/codex/agents" ]; then
        create_symlink "$SCRIPT_DIR/codex/agents" "$CODEX_DIR/agents" "codex agents"
    else
        echo "Run ./generate.sh first to generate Codex agent definitions"
    fi

    # Generated AGENTS.md (symlink to project root for Codex discovery)
    if [ -f "$SCRIPT_DIR/codex/AGENTS.md" ]; then
        create_file_symlink "$SCRIPT_DIR/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" "codex AGENTS.md"
    fi

    # Generated config.toml
    if [ -f "$SCRIPT_DIR/codex/config.toml" ]; then
        create_file_symlink "$SCRIPT_DIR/codex/config.toml" "$CODEX_DIR/config.toml" "codex config.toml"
    fi
fi
