#!/usr/bin/env bash
set -euo pipefail

# generate-codex.sh — generates Codex CLI config from Claude source files.
# Claude source files are the source of truth; this script derives Codex equivalents.
# Idempotent: safe to run multiple times.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$SCRIPT_DIR/codex"
CODEX_AGENTS_DIR="$CODEX_DIR/agents"
AGENTS_SRC="$SCRIPT_DIR/agents"
RULES_DIR="$SCRIPT_DIR/rules"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
SETTINGS_JSON="$SCRIPT_DIR/settings.json"

# Create output directories
mkdir -p "$CODEX_DIR"
mkdir -p "$CODEX_AGENTS_DIR"

# Clean existing generated agent TOMLs
rm -f "$CODEX_AGENTS_DIR"/*.toml

# ---------------------------------------------------------------------------
# map_model — maps Claude model name to Codex model name
# ---------------------------------------------------------------------------
map_model() {
    local model="$1"
    case "$model" in
        opus)   echo "o3" ;;
        sonnet) echo "o4-mini" ;;
        haiku)  echo "o4-mini" ;;
        *)      echo "o4-mini" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_effort — maps Claude effort level to Codex model_reasoning_effort
# ---------------------------------------------------------------------------
map_effort() {
    local effort="$1"
    case "$effort" in
        low)    echo "low" ;;
        medium) echo "medium" ;;
        high)   echo "high" ;;
        max)    echo "xhigh" ;;
        *)      echo "medium" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_sandbox_mode — determines Codex sandbox_mode from agent frontmatter
#   $1 = permissionMode value (plan / acceptEdits / "")
#   $2 = tools list (comma-separated)
# ---------------------------------------------------------------------------
map_sandbox_mode() {
    local permission_mode="$1"
    local tools="$2"

    # plan mode is read-only
    if [ "$permission_mode" = "plan" ]; then
        echo "read-only"
        return
    fi

    # acceptEdits with Write or Edit tool → workspace-write
    if [ "$permission_mode" = "acceptEdits" ]; then
        if echo "$tools" | grep -qE '\b(Write|Edit)\b'; then
            echo "workspace-write"
            return
        fi
    fi

    # Default: read-only
    echo "read-only"
}

# ---------------------------------------------------------------------------
# generate_agent_toml — converts a single agent .md file to Codex .toml
# ---------------------------------------------------------------------------
generate_agent_toml() {
    local src_file="$1"
    local agent_basename
    agent_basename="$(basename "$src_file" .md)"
    local dst_file="$CODEX_AGENTS_DIR/${agent_basename}.toml"

    # Extract YAML frontmatter using yq
    local frontmatter
    frontmatter="$(yq --front-matter=extract '.' "$src_file")"

    # Extract individual fields from frontmatter
    local name description model effort permission_mode tools disallowed_tools
    name="$(echo "$frontmatter" | yq '.name // ""')"
    description="$(echo "$frontmatter" | yq '.description // ""')"
    model="$(echo "$frontmatter" | yq '.model // ""')"
    effort="$(echo "$frontmatter" | yq '.effort // ""')"
    permission_mode="$(echo "$frontmatter" | yq '.permissionMode // ""')"
    tools="$(echo "$frontmatter" | yq '.tools // ""')"
    disallowed_tools="$(echo "$frontmatter" | yq '.disallowedTools // ""')"

    # Map to Codex equivalents
    local codex_model codex_effort codex_sandbox
    codex_model="$(map_model "$model")"
    codex_effort="$(map_effort "${effort:-medium}")"
    codex_sandbox="$(map_sandbox_mode "$permission_mode" "$tools")"

    # Extract markdown body (everything after the closing frontmatter ---)
    # The frontmatter block starts at line 1 with --- and ends at the second ---
    local body
    body="$(awk 'BEGIN{fm=0} /^---$/{if(fm==0){fm=1;next} if(fm==1){fm=2;next}} fm==2{print}' "$src_file")"

    # Build developer_instructions: append disallowedTools note if present
    local developer_instructions
    developer_instructions="$body"
    if [ -n "$disallowed_tools" ] && [ "$disallowed_tools" != "null" ]; then
        developer_instructions="${developer_instructions}

You do NOT have access to these tools: ${disallowed_tools}"
    fi

    # Write TOML output
    cat > "$dst_file" <<TOML
name = "${name}"
description = "${description}"
model = "${codex_model}"
model_reasoning_effort = "${codex_effort}"
sandbox_mode = "${codex_sandbox}"
developer_instructions = """
${developer_instructions}
"""
TOML

    echo "Generated: $dst_file"
}

# ---------------------------------------------------------------------------
# Generate agents
# ---------------------------------------------------------------------------
echo "Generating Codex agent definitions..."
for agent_file in "$AGENTS_SRC"/*.md; do
    [ -f "$agent_file" ] || continue
    generate_agent_toml "$agent_file"
done

# ---------------------------------------------------------------------------
# Generate AGENTS.md — concatenate CLAUDE.md and rules/*.md (sorted)
# ---------------------------------------------------------------------------
echo ""
echo "Generating codex/AGENTS.md..."
{
    echo "# Agent Team Instructions"
    echo ""
    echo "Agent-team specific protocols live in skills (orchestrate, conventions, worker-protocol, qa-checklist, message-schema, project)."
    for rules_file in $(ls "$RULES_DIR"/*.md | sort); do
        echo ""
        cat "$rules_file"
    done
} > "$CODEX_DIR/AGENTS.md"
echo "Generated: $CODEX_DIR/AGENTS.md"

# ---------------------------------------------------------------------------
# Generate config.toml — derive sandbox_mode from settings.json defaultMode
# ---------------------------------------------------------------------------
echo ""
echo "Generating codex/config.toml..."

default_mode="$(yq -r '.permissions.defaultMode // "acceptEdits"' "$SETTINGS_JSON")"

# Map Claude defaultMode to Codex sandbox_mode
case "$default_mode" in
    plan)         config_sandbox="read-only" ;;
    acceptEdits)  config_sandbox="workspace-write" ;;
    *)            config_sandbox="workspace-write" ;;
esac

cat > "$CODEX_DIR/config.toml" <<TOML
model = "o4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "${config_sandbox}"
approval_policy = "on-request"
TOML
echo "Generated: $CODEX_DIR/config.toml"

echo ""
echo "Done. Run ./install.sh to link generated files into ~/.codex/"
