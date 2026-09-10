#!/usr/bin/env bash

set -euo pipefail

if ! command -v skills >/dev/null 2>&1; then
  echo "The 'skills' CLI is not available on PATH." >&2
  exit 1
fi

install_skill_group() {
  local source_url="$1"
  shift
  local skill_args=()
  local skill_name
  for skill_name in "$@"; do
    skill_args+=(--skill "$skill_name")
  done

  echo "Installing $# skills from $source_url."
  skills add "$source_url" -g -a universal "${skill_args[@]}" -y
}

# Add selected names to a group, or add another source with install_skill_group.
pstack_skills=(
  'Poteto Mode'
  'how'
  'why'
  'teach'
  'bro'
  'architect'
  'arena'
  'swarm'
  'interrogate'
  'blast-radius'
  'figure-it-out'
  'show-me-your-work'
  'no-comments'
  'tdd'
  'technical-writing'
  'unslop'
  'principle-laziness-protocol'
  'principle-foundational-thinking'
  'principle-redesign-from-first-principles'
  'principle-subtract-before-you-add'
  'principle-minimize-reader-load'
  'principle-outcome-oriented-execution'
  'principle-experience-first'
  'principle-exhaust-the-design-space'
  'principle-build-the-lever'
  'principle-model-the-domain'
  'principle-boundary-discipline'
  'principle-type-system-discipline'
  'principle-make-operations-idempotent'
  'principle-migrate-callers-then-delete-legacy-apis'
  'principle-separate-before-serializing-shared-state'
  'principle-prove-it-works'
  'principle-fix-root-causes'
  'principle-sequence-verifiable-units'
  'principle-guard-the-context-window'
  'principle-never-block-on-the-human'
  'principle-encode-lessons-in-structure'
)

install_skill_group 'https://github.com/cursor/plugins/tree/main/pstack' "${pstack_skills[@]}"
install_skill_group 'railwayapp/railway-skills' 'use-railway'

echo "All configured global skills installed."
