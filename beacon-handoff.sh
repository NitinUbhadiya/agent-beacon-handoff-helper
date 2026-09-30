#!/usr/bin/env bash
# Beacon Handoff Helper
# Friendly setup + handoff helper for Agent Beacon.
# Designed for macOS and selected Linux distributions.
#
# This script does NOT replace Agent Beacon. It wraps common setup,
# diagnostics, and cross-agent memory prompts in a safer menu-driven flow.

set -u
set -o pipefail

SCRIPT_VERSION="0.3.1"
BEACON_SKILLS_REPO="asymptote-labs/agent-beacon"
CODEX_OTLP_ENDPOINT="http://127.0.0.1:4317"

# ---------- PATH bootstrap ----------
# GUI-launched shells and fresh Apple Silicon installs may not inherit the
# same PATH as the user's interactive shell. Add common user-local locations
# without removing or reordering the rest of PATH.
prepend_path_if_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  case ":${PATH:-}:" in
    *":$dir:"*) ;;
    *) PATH="$dir${PATH:+:$PATH}" ;;
  esac
}
prepend_path_if_dir "/opt/homebrew/bin"
prepend_path_if_dir "/usr/local/bin"
prepend_path_if_dir "$HOME/.local/bin"
export PATH

# ---------- Colors ----------
# NO_COLOR is honored whenever the variable exists, even when empty.
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
  RESET='\033[0m'
  BOLD='\033[1m'
  RED='\033[31m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  BLUE='\033[34m'
  CYAN='\033[36m'
  DIM='\033[2m'
else
  RESET=''
  BOLD=''
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  DIM=''
fi

say()     { printf "%b\n" "$*"; }
info()    { say "${CYAN}ℹ${RESET} $*"; }
success() { say "${GREEN}✓${RESET} $*"; }
warn()    { say "${YELLOW}!${RESET} $*"; }
error()   { say "${RED}✗${RESET} $*"; }

line() {
  say "${DIM}────────────────────────────────────────────────────────${RESET}"
}

pause() {
  printf "\n"
  if ! IFS= read -r -p "Press Enter to continue..." _unused; then
    printf "\n"
    return 1
  fi
  return 0
}

trim_outer_whitespace() {
  local value="$1"
  # Trim only leading/trailing whitespace; preserve internal spaces.
  value="${value#"${value%%[!$' \t\r\n']*}"}"
  value="${value%"${value##*[!$' \t\r\n']}"}"
  printf "%s" "$value"
}

expand_user_path() {
  local value="$1"
  case "$value" in
    "~") value="$HOME" ;;
    "~/"*) value="$HOME/${value:2}" ;;
  esac
  printf "%s" "$value"
}

menu_choice() {
  local value=""
  if ! value="$(prompt_value "Choose an option")"; then
    return 1
  fi
  trim_outer_whitespace "$value"
}

prompt_value() {
  # Usage: prompt_value "Prompt" "default"
  local label="$1"
  local default="${2:-}"
  local answer=""

  printf "\n" >&2

  if [ -n "$default" ]; then
    if ! IFS= read -r -p "$label [$default]: " answer; then
      printf "\n" >&2
      return 1
    fi
    if [ -z "$answer" ]; then
      answer="$default"
    fi
  else
    if ! IFS= read -r -p "$label: " answer; then
      printf "\n" >&2
      return 1
    fi
  fi

  printf "%s" "$answer"
}

confirm() {
  # Usage: confirm "Question" "y|n"
  # EOF / closed stdin is always cancellation, never approval.
  local question="$1"
  local default="${2:-n}"
  local reply=""

  printf "\n"

  if [ "$default" = "y" ]; then
    if ! IFS= read -r -p "$question [Y/n]: " reply; then
      printf "\n"
      warn "Input closed. Action canceled."
      return 1
    fi
    reply="${reply:-y}"
  else
    if ! IFS= read -r -p "$question [y/N]: " reply; then
      printf "\n"
      warn "Input closed. Action canceled."
      return 1
    fi
    reply="${reply:-n}"
  fi

  reply="$(trim_outer_whitespace "$reply")"
  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

beacon_version_text() {
  local version=""

  if ! command_exists beacon; then
    return 1
  fi

  # Current docs use `beacon version`; keep --version as a compatibility fallback.
  version="$(beacon version 2>/dev/null || true)"
  if [ -z "$version" ]; then
    version="$(beacon --version 2>/dev/null || true)"
  fi

  if [ -n "$version" ]; then
    printf "%s" "$version"
  else
    printf "%s" "installed (version command unavailable)"
  fi
}

require_beacon() {
  if ! command_exists beacon; then
    error "Beacon is not installed on this machine."
    info "Use main menu option 4 for the one-time Beacon installation."
    return 1
  fi
  return 0
}

endpoint_state() {
  # running: config exists and status succeeds
  # partial: config exists but status fails
  # missing: no endpoint config
  if [ ! -f "$HOME/.beacon/endpoint/config.json" ]; then
    printf "%s" "missing"
    return 0
  fi

  if beacon endpoint status >/dev/null 2>&1; then
    printf "%s" "running"
  else
    printf "%s" "partial"
  fi
}

run_command_report() {
  # Usage: run_command_report "Label" command arg...
  local label="$1"
  local rc=0
  shift

  "$@"
  rc=$?

  printf "\n"
  if [ "$rc" -eq 0 ]; then
    success "$label completed."
  elif [ "$rc" -eq 130 ]; then
    warn "$label canceled with Ctrl+C."
  else
    error "$label exited with status $rc."
  fi

  return "$rc"
}

show_beacon_destination_notice() {
  local status=""
  local managed_line=""

  if ! command_exists beacon; then
    return 0
  fi

  status="$(beacon endpoint status 2>/dev/null || true)"
  managed_line="$(printf "%s\n" "$status" | grep -E '^Beacon Managed:' | head -n 1 || true)"

  if [ -n "$managed_line" ]; then
    if printf "%s" "$managed_line" | grep -qi 'not connected'; then
      info "$managed_line"
    else
      warn "$managed_line"
      warn "Telemetry sent to the local Beacon collector may also be forwarded by the endpoint configuration."
    fi
  else
    info "Review 'beacon endpoint status' before enabling prompt capture if your company requires local-only telemetry."
  fi
}

show_header() {
  clear 2>/dev/null || true
  say "${BOLD}${BLUE}BEACON HANDOFF HELPER${RESET}  ${DIM}v${SCRIPT_VERSION}${RESET}"
  say "Cross-agent setup, local telemetry, project memory, and handoff prompts"
  line
}

show_beacon_version() {
  if command_exists beacon; then
    success "Beacon detected: $(beacon_version_text)"
  else
    warn "Beacon is not installed yet."
  fi
}

# ---------- Clipboard ----------
copy_to_clipboard() {
  local text="$1"

  if command_exists pbcopy; then
    if printf "%s" "$text" | pbcopy; then
      success "Copied to clipboard."
      return 0
    fi
  elif command_exists wl-copy && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if printf "%s" "$text" | wl-copy; then
      success "Copied to clipboard."
      return 0
    fi
  elif command_exists xclip && [ -n "${DISPLAY:-}" ]; then
    if printf "%s" "$text" | xclip -selection clipboard; then
      success "Copied to clipboard."
      return 0
    fi
  else
    warn "Clipboard utility not found. Copy the prompt manually."
    return 1
  fi

  error "Clipboard command failed. Copy the prompt manually."
  return 1
}

# ---------- Handoff prompts ----------
PROMPT_RECALL='Use the beacon-memory-recall skill to recall my recent work for this project.

Summarize:
- what I was trying to do
- what files/commands/tools were used
- what was already completed
- current problem/status
- what should be done next

Do not make changes yet.'

PROMPT_PROMOTE='Use beacon-memory-promote to save the important progress, decisions, current status, and next steps from this session so another agent can continue later.'

PROMPT_DISTILL='Use beacon-memory-distill to review the useful work from this project/session and prepare durable project knowledge. Do not promote low-value or temporary details.'

PROMPT_CONTINUE='Continue from the Beacon-recalled context.

Proceed with the next pending step, but inspect and explain before making any code changes.'

show_prompt() {
  local title="$1"
  local prompt="$2"

  printf "\n"
  say "${BOLD}${CYAN}${title}${RESET}"
  line
  printf "%s\n" "$prompt"
  line

  if confirm "Copy this prompt to clipboard?" "y"; then
    copy_to_clipboard "$prompt" || true
  fi
}

# ---------- Project skills ----------
project_has_beacon_skills() {
  local project="$1"

  [ -f "$project/.agents/skills/beacon-memory-recall/SKILL.md" ] && \
  [ -f "$project/.agents/skills/beacon-memory-distill/SKILL.md" ] && \
  [ -f "$project/.agents/skills/beacon-memory-promote/SKILL.md" ]
}

missing_beacon_skills() {
  local project="$1"
  local skill=""
  local missing=""

  for skill in beacon-memory-recall beacon-memory-distill beacon-memory-promote; do
    if [ ! -f "$project/.agents/skills/$skill/SKILL.md" ]; then
      if [ -n "$missing" ]; then
        missing="${missing}, "
      fi
      missing="${missing}${skill}"
    fi
  done

  printf "%s" "$missing"
}

setup_project_skills() {
  local default_project=""
  local project=""
  local missing=""
  local rc=0

  show_header
  say "${BOLD}1. Project Setup — Beacon Memory Skills${RESET}"
  say "Installs recall/distill/promote skills into a project so supported agents can share durable project knowledge."

  default_project="$(pwd)"
  if ! project="$(prompt_value "Project path" "$default_project")"; then
    info "Input closed. Returning to the main menu."
    return
  fi

  project="$(expand_user_path "$project")"

  if [ ! -d "$project" ]; then
    error "Directory does not exist: $project"
    pause || true
    return
  fi

  project="$(cd "$project" 2>/dev/null && pwd -P)" || {
    error "Could not access project directory."
    pause || true
    return
  }

  printf "\n"
  info "Project: $project"

  if project_has_beacon_skills "$project"; then
    success "All 3 Beacon memory skills are already installed in this project."
    info "Location: $project/.agents/skills/"
    pause || true
    return
  fi

  missing="$(missing_beacon_skills "$project")"
  warn "Missing or incomplete Beacon skills: $missing"

  if ! command_exists beacon; then
    warn "Beacon CLI is not installed yet."
    info "The skill files can still be installed now, but recall/telemetry workflows require Beacon to be installed and configured."
    info "Use main menu option 4 for the one-time Beacon installation."
  fi

  if ! command_exists npx; then
    error "npx is not available. Install Node.js/npm first, then run this option again."
    pause || true
    return
  fi

  say ""
  say "During the installer:"
  say "  1) Select ${BOLD}beacon-memory-distill${RESET}, ${BOLD}beacon-memory-promote${RESET}, and ${BOLD}beacon-memory-recall${RESET}."
  say "  2) Use ${BOLD}Project${RESET} scope for repository-specific memory."
  say "  3) Extra discovery skills are optional and are not required for Beacon handoff."
  say "  4) If asked to install find-skills, choose No for the minimal Beacon-only setup."

  if confirm "Start the official Beacon skills installer in this project?" "y"; then
    (
      cd "$project" || exit 1
      npx skills add "$BEACON_SKILLS_REPO"
    )
    rc=$?

    printf "\n"
    if [ "$rc" -eq 130 ]; then
      warn "Skills installer canceled with Ctrl+C."
    elif [ "$rc" -ne 0 ]; then
      error "Skills installer exited with status $rc."
    elif project_has_beacon_skills "$project"; then
      success "Beacon memory skills detected successfully."
    else
      missing="$(missing_beacon_skills "$project")"
      warn "Installer finished, but these skill files are still missing: $missing"
      info "Re-run this option and verify the Project-scope selections."
    fi
  else
    info "No project changes made."
  fi

  pause || true
}

# ---------- Codex OTel ----------
codex_otel_section_count() {
  local cfg="$1"
  local header_re="^[[:space:]]*[[][[:space:]]*(otel|\"otel\"|'otel')[[:space:]]*[]][[:space:]]*(#.*)?$"

  grep -Ec "$header_re" "$cfg" 2>/dev/null || true
}

codex_otel_section() {
  local cfg="$1"
  local header_re="^[[:space:]]*[[][[:space:]]*(otel|\"otel\"|'otel')[[:space:]]*[]][[:space:]]*(#.*)?$"

  awk -v header_re="$header_re" '
    BEGIN { in_otel=0 }
    /^[[:space:]]*#/ { if (in_otel) print; next }
    $0 ~ header_re {
      if (in_otel) exit
      in_otel=1
      print
      next
    }
    /^[[:space:]]*\[/ {
      if (in_otel) exit
    }
    {
      if (in_otel) print
    }
  ' "$cfg" 2>/dev/null
}

codex_otel_points_to_local_beacon() {
  local cfg="$1"
  local section=""

  section="$(codex_otel_section "$cfg")"

  printf "%s\n" "$section" | grep -Eq '^[[:space:]]*exporter[[:space:]]*=.*endpoint[[:space:]]*=[[:space:]]*"http://127\.0\.0\.1:4317"' && \
  printf "%s\n" "$section" | grep -Eq '^[[:space:]]*trace_exporter[[:space:]]*=.*endpoint[[:space:]]*=[[:space:]]*"http://127\.0\.0\.1:4317"'
}

codex_prompt_capture_state() {
  local cfg="$1"
  local section=""

  section="$(codex_otel_section "$cfg")"

  if printf "%s\n" "$section" | grep -Eq '^[[:space:]]*log_user_prompt[[:space:]]*=[[:space:]]*true([[:space:]]|#|$)'; then
    printf "%s" "enabled"
  elif printf "%s\n" "$section" | grep -Eq '^[[:space:]]*log_user_prompt[[:space:]]*=[[:space:]]*false([[:space:]]|#|$)'; then
    printf "%s" "disabled"
  else
    printf "%s" "unspecified"
  fi
}

next_backup_path() {
  local cfg="$1"
  local base="${cfg}.backup-$(date +%Y%m%d-%H%M%S)"
  local candidate="$base"
  local n=1

  while [ -e "$candidate" ]; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done

  printf "%s" "$candidate"
}

optional_toml_validate() {
  local cfg="$1"

  if ! command_exists python3; then
    return 0
  fi

  # Python < 3.11 may not include tomllib. In that case, keep the helper
  # dependency-free and rely on the section-level structural validation.
  if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
    return 0
  fi

  if python3 -c 'import sys, tomllib; f=open(sys.argv[1], "rb");
try: tomllib.load(f)
finally: f.close()' "$cfg" >/dev/null 2>&1; then
    return 0
  fi

  error "TOML validation failed using Python tomllib."
  return 1
}

write_new_codex_otel_section() {
  local cfg="$1"
  local prompt_value="$2"
  local cfg_dir=""
  local backup=""
  local tmp=""
  local count=""

  cfg_dir="$(dirname "$cfg")"

  if ! mkdir -p "$cfg_dir"; then
    error "Could not create Codex config directory: $cfg_dir"
    return 1
  fi

  if [ -f "$cfg" ]; then
    backup="$(next_backup_path "$cfg")"
    if ! cp -p "$cfg" "$backup"; then
      error "Could not create backup: $backup"
      return 1
    fi
  fi

  tmp="$(mktemp "${cfg}.tmp.XXXXXX" 2>/dev/null)" || {
    error "Could not create a temporary config file in $cfg_dir."
    return 1
  }

  if [ -f "$cfg" ]; then
    if ! cat "$cfg" > "$tmp"; then
      error "Could not copy the current Codex config into the temporary file."
      rm -f "$tmp"
      return 1
    fi
  fi

  if ! cat >> "$tmp" <<EOF_OTEL

[otel]
environment = "local"
log_user_prompt = $prompt_value
exporter = { otlp-grpc = { endpoint = "$CODEX_OTLP_ENDPOINT" } }
trace_exporter = { otlp-grpc = { endpoint = "$CODEX_OTLP_ENDPOINT" } }
EOF_OTEL
  then
    error "Could not write the Beacon OTel section to the temporary file."
    rm -f "$tmp"
    return 1
  fi

  count="$(codex_otel_section_count "$tmp")"
  if [ "$count" -ne 1 ] || ! codex_otel_points_to_local_beacon "$tmp"; then
    error "Temporary Codex config validation failed. The original config was not replaced."
    rm -f "$tmp"
    return 1
  fi

  if ! optional_toml_validate "$tmp"; then
    error "The original Codex config was not replaced."
    rm -f "$tmp"
    return 1
  fi

  if ! mv "$tmp" "$cfg"; then
    error "Could not replace $cfg with the validated temporary file."
    rm -f "$tmp"
    return 1
  fi

  chmod 600 "$cfg" 2>/dev/null || true

  success "Codex OTel configuration added safely."
  if [ -n "$backup" ]; then
    info "Backup: $backup"
  else
    info "A new config file was created: $cfg"
  fi
  return 0
}

update_codex_prompt_capture() {
  local cfg="$1"
  local desired="$2"
  local desired_label="disabled"
  local cfg_dir=""
  local backup=""
  local tmp=""
  local header_re="^[[:space:]]*[[][[:space:]]*(otel|\"otel\"|'otel')[[:space:]]*[]][[:space:]]*(#.*)?$"

  [ "$desired" = "true" ] && desired_label="enabled"

  if [ ! -f "$cfg" ] || [ "$(codex_otel_section_count "$cfg")" -ne 1 ]; then
    error "Expected exactly one existing [otel] section; no changes made."
    return 1
  fi

  if ! codex_otel_points_to_local_beacon "$cfg"; then
    error "The existing [otel] section does not clearly point to the local Beacon collector; no changes made."
    return 1
  fi

  cfg_dir="$(dirname "$cfg")"
  backup="$(next_backup_path "$cfg")"

  if ! cp -p "$cfg" "$backup"; then
    error "Could not create backup: $backup"
    return 1
  fi

  tmp="$(mktemp "${cfg}.tmp.XXXXXX" 2>/dev/null)" || {
    error "Could not create a temporary config file in $cfg_dir."
    return 1
  }

  if ! awk -v header_re="$header_re" -v desired="$desired" '
    BEGIN { in_otel=0; replaced=0 }
    $0 ~ header_re {
      if (in_otel && !replaced) print "log_user_prompt = " desired
      in_otel=1
      print
      next
    }
    /^[[:space:]]*\[/ {
      if (in_otel && !replaced) print "log_user_prompt = " desired
      in_otel=0
      print
      next
    }
    {
      if (in_otel && $0 ~ /^[[:space:]]*log_user_prompt[[:space:]]*=/) {
        if (!replaced) print "log_user_prompt = " desired
        replaced=1
        next
      }
      print
    }
    END {
      if (in_otel && !replaced) print "log_user_prompt = " desired
    }
  ' "$cfg" > "$tmp"; then
    error "Could not prepare the updated Codex config."
    rm -f "$tmp"
    return 1
  fi

  if [ "$(codex_otel_section_count "$tmp")" -ne 1 ] || ! codex_otel_points_to_local_beacon "$tmp"; then
    error "Updated Codex config failed structural validation. The original file was not replaced."
    rm -f "$tmp"
    return 1
  fi

  if [ "$(codex_prompt_capture_state "$tmp")" != "$desired_label" ]; then
    error "Updated raw-prompt setting could not be verified. The original file was not replaced."
    rm -f "$tmp"
    return 1
  fi

  if ! optional_toml_validate "$tmp"; then
    error "The original Codex config was not replaced."
    rm -f "$tmp"
    return 1
  fi

  if ! mv "$tmp" "$cfg"; then
    error "Could not replace $cfg with the validated temporary file."
    rm -f "$tmp"
    return 1
  fi

  chmod 600 "$cfg" 2>/dev/null || true
  success "Raw Codex prompt capture is now $desired_label."
  info "Backup: $backup"
  return 0
}

setup_codex_otel() {
  local cfg="$HOME/.codex/config.toml"
  local otel_count=0
  local prompt_state=""
  local prompt_capture="false"

  show_header
  say "${BOLD}Codex Desktop / Codex CLI — Local Beacon Telemetry${RESET}"

  if ! require_beacon; then
    pause || true
    return
  fi

  show_beacon_destination_notice
  say ""
  warn "The Codex OTLP endpoint is local ($CODEX_OTLP_ENDPOINT), but Beacon itself may forward collected telemetry if a hosted/SIEM destination is configured."
  info "Review main option 3 → Beacon endpoint status if your company requires local-only telemetry."

  if [ -f "$cfg" ]; then
    otel_count="$(codex_otel_section_count "$cfg")"
  fi

  if [ "$otel_count" -gt 1 ]; then
    error "Multiple [otel] sections were detected in $cfg."
    warn "No automatic changes will be made because duplicate TOML tables can make the configuration invalid."
    info "Review the file manually and keep only one [otel] section."
    pause || true
    return
  fi

  if [ "$otel_count" -eq 1 ]; then
    if codex_otel_points_to_local_beacon "$cfg"; then
      prompt_state="$(codex_prompt_capture_state "$cfg")"
      success "Codex OTel already points to Beacon at $CODEX_OTLP_ENDPOINT."
      info "Raw prompt capture: $prompt_state"
      if [ "$prompt_state" != "enabled" ]; then
        warn "Cross-agent recall may contain less context while raw prompt capture is disabled."
        if confirm "Enable raw Codex prompt capture? This may record sensitive prompt text" "n"; then
          update_codex_prompt_capture "$cfg" "true" || true
        fi
      else
        if confirm "Disable raw Codex prompt capture for greater privacy?" "n"; then
          update_codex_prompt_capture "$cfg" "false" || true
        fi
      fi
    else
      warn "An existing [otel] section was found in: $cfg"
      warn "It does not clearly point both exporters to the local Beacon collector."
      say ""
      say "This helper will NOT rewrite an existing telemetry section automatically."
      say "Review it manually. A local Beacon example is:"
      say ""
      say "  [otel]"
      say "  environment = \"local\""
      say "  log_user_prompt = false"
      say "  exporter = { otlp-grpc = { endpoint = \"$CODEX_OTLP_ENDPOINT\" } }"
      say "  trace_exporter = { otlp-grpc = { endpoint = \"$CODEX_OTLP_ENDPOINT\" } }"
      say ""
      warn "Set log_user_prompt = true only if you explicitly accept raw prompt capture."
    fi

    info "Fully quit and reopen Codex Desktop after any telemetry config change."
    pause || true
    return
  fi

  say ""
  say "No [otel] section was detected in the Codex config."
  warn "Raw prompts may contain source code, credentials, customer data, or other sensitive text."

  if ! confirm "Configure Codex to send telemetry to the local Beacon collector?" "n"; then
    info "No Codex config changes made."
    pause || true
    return
  fi

  if confirm "Also capture raw Codex user prompts for richer cross-agent handoff?" "n"; then
    prompt_capture="true"
    warn "Raw prompt capture ENABLED by explicit opt-in."
  else
    info "Raw prompt capture will remain disabled."
  fi

  if write_new_codex_otel_section "$cfg" "$prompt_capture"; then
    info "Config: $cfg"
    warn "Fully quit Codex Desktop (including background processes) and reopen it before testing."
    info "Then run: beacon traces"
  fi

  pause || true
}

# ---------- Agent setup ----------
setup_antigravity_cli() {
  show_header
  say "${BOLD}Antigravity CLI — Beacon Hooks${RESET}"

  if ! require_beacon; then
    pause || true
    return
  fi

  info "Beacon endpoint repair can reconcile service files, telemetry integrations, detected harness hooks, and configured forwarding destinations."
  warn "Review your organization's telemetry destination policy before running repair."

  if confirm "Run 'beacon endpoint repair' now?" "n"; then
    run_command_report "Beacon endpoint repair" beacon endpoint repair || true
  else
    info "No repair performed."
  fi

  say ""
  info "Review the result with: beacon endpoint status"
  pause || true
}

show_antigravity_ide_guidance() {
  show_header
  say "${BOLD}Antigravity IDE / Desktop — Project Memory Handoff${RESET}"
  warn "Beacon's documented local collection covers Antigravity CLI hooks; Antigravity IDE/Desktop telemetry may not be captured automatically."
  say ""
  say "For the IDE/Desktop flow used successfully in testing:"
  say "  • Install Beacon memory skills in the project (main option 1)."
  say "  • When entering Antigravity, use the recall prompt."
  say "  • Before leaving Antigravity, use the promote prompt."
  say "  • The promoted repository Agent Skill can then be loaded by Codex/other skill-capable agents."
  say ""
  say "Recall prompt:"
  say "${DIM}${PROMPT_RECALL}${RESET}"
  say ""
  say "Promote prompt:"
  say "${DIM}${PROMPT_PROMOTE}${RESET}"
  pause || true
}

setup_other_agents() {
  show_header
  say "${BOLD}Other Supported Agents — Repair / Detection${RESET}"

  if ! require_beacon; then
    pause || true
    return
  fi

  info "Beacon endpoint repair can reconcile service files, telemetry integrations, detected harness hooks, and configured forwarding destinations."
  warn "It is broader than agent detection alone."

  if confirm "Run 'beacon endpoint repair' now?" "n"; then
    run_command_report "Beacon endpoint repair" beacon endpoint repair || true
  else
    info "No repair performed."
  fi

  say ""
  info "Then review: beacon endpoint status"
  pause || true
}

agent_setup_menu() {
  local choice=""

  while true; do
    show_header
    say "${BOLD}2. AI App / Agent / CLI / Desktop Setup${RESET}"
    say ""
    say "  1) Codex Desktop / Codex CLI (OTLP → local Beacon)"
    say "  2) Antigravity CLI (hooks / repair)"
    say "  3) Antigravity IDE / Desktop (manual promote/recall flow)"
    say "  4) Other supported agents (repair / detection)"
    say "  5) Show Beacon endpoint status"
    say "  0) Back"

    if ! choice="$(menu_choice)"; then
      info "Input closed. Returning to the main menu."
      return
    fi

    case "$choice" in
      1) setup_codex_otel ;;
      2) setup_antigravity_cli ;;
      3) show_antigravity_ide_guidance ;;
      4) setup_other_agents ;;
      5)
        show_header
        if require_beacon; then
          beacon endpoint status || error "Could not read Beacon endpoint status."
        fi
        pause || true
        ;;
      0) return ;;
      *) warn "Invalid option."; pause || true ;;
    esac
  done
}

# ---------- Handoff / diagnostics ----------
run_dashboard() {
  if ! require_beacon; then
    return 1
  fi

  say ""
  info "Starting local dashboard. Press Ctrl+C to return to this helper."
  run_command_report "Local dashboard" beacon endpoint dashboard
}

run_traces() {
  if ! require_beacon; then
    return 1
  fi

  say ""
  info "Opening local traces. Use q to quit the trace browser."
  run_command_report "Trace browser" beacon traces
}

handoff_menu() {
  local choice=""

  while true; do
    show_header
    say "${BOLD}3. Handoff Prompts & Diagnostics${RESET}"
    say ""
    say "  1) Recall previous agent work prompt"
    say "  2) Promote current session prompt"
    say "  3) Distill project/session memory prompt"
    say "  4) Continue from recalled context prompt"
    say "  5) Beacon endpoint status"
    say "  6) Open terminal traces"
    say "  7) Start local dashboard"
    say "  8) Repair Beacon endpoint / detected integrations"
    say "  0) Back"

    if ! choice="$(menu_choice)"; then
      info "Input closed. Returning to the main menu."
      return
    fi

    case "$choice" in
      1) show_header; show_prompt "RECALL — New Agent Reads Previous Work" "$PROMPT_RECALL"; pause || true ;;
      2) show_header; show_prompt "PROMOTE — Save Current Work for Next Agent" "$PROMPT_PROMOTE"; pause || true ;;
      3) show_header; show_prompt "DISTILL — Prepare Durable Project Knowledge" "$PROMPT_DISTILL"; pause || true ;;
      4) show_header; show_prompt "CONTINUE — Continue After Recall" "$PROMPT_CONTINUE"; pause || true ;;
      5)
        show_header
        if require_beacon; then
          beacon endpoint status || error "Could not read Beacon endpoint status."
        fi
        pause || true
        ;;
      6) show_header; run_traces || true; pause || true ;;
      7) show_header; run_dashboard || true; pause || true ;;
      8)
        show_header
        if require_beacon; then
          info "Repair can reconcile Beacon service files, telemetry configuration, detected harness hooks, and configured forwarding destinations."
          if confirm "Run 'beacon endpoint repair' now?" "n"; then
            run_command_report "Beacon endpoint repair" beacon endpoint repair || true
          else
            info "No repair performed."
          fi
        fi
        pause || true
        ;;
      0) return ;;
      *) warn "Invalid option."; pause || true ;;
    esac
  done
}

# ---------- Beacon installation ----------
install_beacon_macos() {
  if ! command_exists brew; then
    error "Homebrew is not installed."
    info "Install Homebrew from its official site, then run this option again."
    return 1
  fi

  info "Installing Beacon using the official Asymptote Labs Homebrew tap."

  if ! brew trust asymptote-labs/tap; then
    warn "'brew trust' was unavailable or failed; continuing to tap/install."
  fi

  brew tap asymptote-labs/tap || return 1
  brew install beacon || return 1
}

install_beacon_linux() {
  local linux_id=""
  local linux_like=""
  local arch=""
  local rc=0

  info "Automatic Linux installation in this helper is limited to Debian/Ubuntu and Fedora/RHEL/Rocky/Alma package families."

  if ! command_exists curl; then
    error "curl is required for the official Linux installer."
    return 1
  fi

  if [ ! -r /etc/os-release ]; then
    error "Could not identify this Linux distribution."
    info "Automatic Linux install is limited to Beacon's documented package families."
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  linux_id="${ID:-unknown}"
  linux_like="${ID_LIKE:-}"

  case " $linux_id $linux_like " in
    *" ubuntu "*|*" debian "*|*" fedora "*|*" rhel "*|*" rocky "*|*" almalinux "*)
      ;;
    *)
      error "Automatic Beacon install is not enabled for this distribution: ${PRETTY_NAME:-$linux_id}"
      info "This helper currently follows Beacon's documented Debian/Ubuntu and Fedora/RHEL/Rocky/Alma package flows."
      return 1
      ;;
  esac

  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    x86_64|aarch64|arm64) ;;
    *)
      error "Unsupported/untested Linux architecture for this helper: $arch"
      return 1
      ;;
  esac

  warn "The official Linux flow downloads an installer script from GitHub releases."
  info "This helper downloads it to a temporary file first, then executes it with Bash so installer/sudo prompts keep normal terminal input."
  info "Beacon documents that the installer downloads the matching .deb/.rpm and verifies it against release checksums."

  if confirm "Download and run the official Beacon Linux installer from GitHub releases?" "n"; then
    local tmp_installer=""
    tmp_installer="$(mktemp "${TMPDIR:-/tmp}/beacon-install.XXXXXX")" || {
      error "Could not create a temporary installer file."
      return 1
    }
    if ! curl -fsSL https://github.com/asymptote-labs/agent-beacon/releases/latest/download/install.sh -o "$tmp_installer"; then
      error "Could not download the Beacon installer."
      rm -f "$tmp_installer"
      return 1
    fi
    chmod 700 "$tmp_installer" 2>/dev/null || true
    info "Installer downloaded to a temporary file. Running it now..."
    bash "$tmp_installer"
    rc=$?
    rm -f "$tmp_installer"
    if [ "$rc" -eq 0 ]; then
      success "Beacon Linux installer completed."
      return 0
    fi
    error "Beacon Linux installer failed (exit $rc)."
    return "$rc"
  fi

  say ""
  info "No installation performed."
  return 1
}

install_beacon() {
  local os=""
  local state=""

  show_header
  say "${BOLD}4. One-Time Beacon Installation / Endpoint Initialization${RESET}"
  say "This option belongs last because installation is normally needed only once per machine."
  say ""

  if command_exists beacon; then
    success "Beacon is already installed: $(beacon_version_text)"
  else
    os="$(uname -s 2>/dev/null || echo unknown)"
    case "$os" in
      Darwin)
        install_beacon_macos || { pause || true; return; }
        ;;
      Linux)
        install_beacon_linux || { pause || true; return; }
        ;;
      *)
        error "Automatic install is currently supported by this helper only on macOS and selected Linux distributions."
        info "Use Agent Beacon's official installation docs for this OS."
        pause || true
        return
        ;;
    esac
  fi

  if ! command_exists beacon; then
    error "Beacon command is still unavailable after installation."
    pause || true
    return
  fi

  say ""
  warn "Beacon endpoint setup is interactive and may open a browser for sign-in."
  warn "IMPORTANT: Beacon's interactive installer currently PRESELECTS Beacon Managed/Cloud."
  warn "Choosing the preselected Managed option enables hosted forwarding after confirmation."
  success "Choose ${BOLD}Local only${RESET} if telemetry must remain on this machine."
  warn "Do not continue with a hosted/managed destination unless your company/privacy policy explicitly allows it."

  state="$(endpoint_state)"

  case "$state" in
    running)
      say ""
      success "Beacon endpoint already appears configured and running."
      info "Re-running endpoint install is normally unnecessary and may ask for destination/sign-in choices again."

      if confirm "Re-run 'beacon endpoint install' anyway?" "n"; then
        warn "The installer will again preselect Beacon Managed/Cloud. Select Local only if you do not want hosted forwarding."
        if confirm "I understand the destination choice and want to open the installer" "n"; then
          run_command_report "Beacon endpoint setup" beacon endpoint install || true
          say ""
          beacon endpoint status || error "Could not read Beacon endpoint status."
        else
          info "Endpoint setup canceled."
        fi
      fi
      ;;

    partial)
      say ""
      warn "Beacon endpoint config exists, but 'beacon endpoint status' is not healthy."
      info "This may be a partial/stopped setup. Reinstalling immediately could hide the real issue."
      info "Beacon repair can also reconcile service files, telemetry configuration, harness integrations, and configured forwarding destinations."

      if confirm "Run 'beacon endpoint repair' first?" "n"; then
        run_command_report "Beacon endpoint repair" beacon endpoint repair || true
        say ""
        beacon endpoint status || warn "Endpoint status is still unavailable after repair."
      else
        info "No repair performed."
      fi
      ;;

    missing)
      say ""
      info "Beacon endpoint is not configured yet."
      warn "Before opening the installer, decide whether this machine is allowed to forward agent telemetry off-device."

      if confirm "Open the interactive Beacon endpoint installer?" "n"; then
        warn "When asked where telemetry should go, Beacon Managed/Cloud is preselected."
        success "Select Local only to keep telemetry on this machine."

        if confirm "I understand the destination choice and want to continue" "n"; then
          run_command_report "Beacon endpoint setup" beacon endpoint install || true
          say ""
          beacon endpoint status || error "Could not read Beacon endpoint status."
        else
          info "Endpoint setup canceled."
        fi
      else
        info "Endpoint setup not started."
      fi
      ;;
  esac

  say ""
  info "After setup, use main option 1 for each project and option 2 for agent-specific setup."
  pause || true
}

# ---------- Main ----------
main_menu() {
  local choice=""

  while true; do
    show_header
    show_beacon_version
    say ""
    say "${BOLD}Main Menu${RESET}"
    say ""
    say "  1) Project setup — install Beacon memory skills"
    say "  2) AI app / agent / CLI / Desktop setup"
    say "  3) Handoff prompts & diagnostics"
    say "  4) One-time Beacon installation / endpoint setup"
    say "  0) Exit"

    if ! choice="$(menu_choice)"; then
      say ""
      info "Input closed. Exiting safely."
      exit 0
    fi

    case "$choice" in
      1) setup_project_skills ;;
      2) agent_setup_menu ;;
      3) handoff_menu ;;
      4) install_beacon ;;
      0)
        say ""
        success "Done."
        exit 0
        ;;
      *) warn "Invalid option."; pause || true ;;
    esac
  done
}

main_menu
