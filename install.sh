#!/usr/bin/env sh
# reasonhub-skills installer
# Usage: curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh | sh
# Or:    ./install.sh [--pi] [--copilot] [--cursor] [--agents] [--dir <path>]

set -e

REPO="https://github.com/reason-healthcare/reasonhub-skills"
RAW="https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main"
SKILLS="reasonhub-snomed-semantic reasonhub-terminology-crossmap reasonhub-valueset-properties"

# ── helpers ────────────────────────────────────────────────────────────────────

info()    { printf '\033[34m  info\033[0m  %s\n' "$*"; }
success() { printf '\033[32m    ok\033[0m  %s\n' "$*"; }
warn()    { printf '\033[33m  warn\033[0m  %s\n' "$*"; }
error()   { printf '\033[31m error\033[0m  %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

copy_skills() {
  dest="$1"
  mkdir -p "$dest"
  for skill in $SKILLS; do
    if [ -d "$skill" ]; then
      # Running from inside the repo
      cp -r "$skill" "$dest/"
    else
      # Downloading from GitHub
      require curl
      mkdir -p "$dest/$skill"
      curl -fsSL "$RAW/$skill/SKILL.md" -o "$dest/$skill/SKILL.md"
    fi
    success "installed $skill → $dest/$skill"
  done
}

generate_cursor_rules() {
  dest="${1:-.cursor/rules}"
  mkdir -p "$dest"
  for skill in $SKILLS; do
    src=""
    if [ -f "$skill/SKILL.md" ]; then
      src="$skill/SKILL.md"
    else
      require curl
      tmp=$(mktemp)
      curl -fsSL "$RAW/$skill/SKILL.md" -o "$tmp"
      src="$tmp"
    fi
    # Extract description from frontmatter for Cursor's description field
    desc=$(sed -n '/^description:/,/^[a-z]/{ /^description:/!{ /^[a-z]/!p } }' "$src" \
           | sed 's/^  //' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    out="$dest/$skill.mdc"
    printf -- '---\ndescription: %s\n---\n\n' "$desc" > "$out"
    # Append body (skip frontmatter block)
    awk '/^---/{n++; if(n==2){found=1; next}} found{print}' "$src" >> "$out"
    success "generated $out"
    [ -n "${tmp:-}" ] && rm -f "$tmp"
  done
}

# ── argument parsing ────────────────────────────────────────────────────────────

mode=""
custom_dir=""

for arg in "$@"; do
  case "$arg" in
    --pi)      mode="pi" ;;
    --copilot) mode="copilot" ;;
    --cursor)  mode="cursor" ;;
    --agents)  mode="agents" ;;
    --dir)     shift; custom_dir="$1" ;;
    --help|-h)
      cat <<EOF
reasonhub-skills installer

Usage: install.sh [option]

Options:
  --pi        Install to .agents/skills/ (pi project-level discovery)
  --copilot   Install to .github/skills/ (GitHub Copilot discovery)
  --cursor    Generate .cursor/rules/*.mdc (Cursor discovery)
  --agents    Install to ~/.agents/skills/ (pi global discovery)
  --dir PATH  Install to a custom directory
  (no option)  Interactive prompt
EOF
      exit 0
      ;;
  esac
done

# ── interactive mode if no flag given ──────────────────────────────────────────

if [ -z "$mode" ] && [ -z "$custom_dir" ]; then
  printf '\nreasonhub-skills — where would you like to install?\n\n'
  printf '  1) .agents/skills/     (pi — project level)\n'
  printf '  2) ~/.agents/skills/   (pi — global)\n'
  printf '  3) .github/skills/     (GitHub Copilot)\n'
  printf '  4) .cursor/rules/      (Cursor)\n'
  printf '  5) Custom path\n\n'
  printf 'Choice [1]: '
  read -r choice
  choice="${choice:-1}"
  case "$choice" in
    1) mode="pi" ;;
    2) mode="agents" ;;
    3) mode="copilot" ;;
    4) mode="cursor" ;;
    5)
      printf 'Path: '
      read -r custom_dir
      ;;
    *) error "Invalid choice" ;;
  esac
fi

# ── install ─────────────────────────────────────────────────────────────────────

case "$mode" in
  pi)
    copy_skills ".agents/skills"
    info "Skills will be auto-discovered by pi in .agents/skills/"
    ;;
  agents)
    copy_skills "$HOME/.agents/skills"
    info "Skills will be available globally to pi in ~/.agents/skills/"
    ;;
  copilot)
    copy_skills ".github/skills"
    info "Skills will be discovered by GitHub Copilot in .github/skills/"
    ;;
  cursor)
    generate_cursor_rules ".cursor/rules"
    info "Add .cursor/rules/ to your Cursor settings to enable rule discovery"
    ;;
  "")
    if [ -n "$custom_dir" ]; then
      copy_skills "$custom_dir"
    else
      error "No install target specified. Run with --help for usage."
    fi
    ;;
esac

printf '\n'
success "reasonhub-skills installed"
printf '\n  Requires a running ReasonHub MCP server.\n'
printf '  See %s for setup.\n\n' "$REPO"
