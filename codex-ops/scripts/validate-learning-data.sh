#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$ROOT"

ruby <<'RUBY'
require "json"
require "yaml"

errors = []

jsonl_requirements = {
  "codex-ops/evals/preference-dataset.jsonl" => %w[id domain task_type locale user_prompt must_do must_not_do candidate_a candidate_b preference rubric_scores],
  "codex-ops/evals/agent-learning-dataset.jsonl" => %w[id domain task_type locale trigger must_do must_not_do evidence success_criteria rubric]
}

jsonl_requirements.each do |path, keys|
  unless File.file?(path)
    errors << "#{path}: missing"
    next
  end

  File.foreach(path).with_index(1) do |line, lineno|
    next if line.strip.empty?
    begin
      obj = JSON.parse(line)
    rescue JSON::ParserError => e
      errors << "#{path}:#{lineno}: invalid JSON: #{e.message}"
      next
    end

    missing = keys.reject { |key| obj.key?(key) }
    errors << "#{path}:#{lineno}: missing keys #{missing.join(',')}" unless missing.empty?
  end
end

yaml_requirements = {
  "codex-ops/evals/eval-cases.yaml" => %w[version cases],
  "codex-ops/evals/antipattern-cases.yaml" => %w[version cases],
  "codex-ops/assets/asset-catalog.yaml" => %w[version assets],
  "codex-ops/packages/local-codex-ops/manifest.yaml" => %w[name version capabilities dependencies preflight postflight]
}

yaml_requirements.each do |path, keys|
  unless File.file?(path)
    errors << "#{path}: missing"
    next
  end

  begin
    obj = YAML.load_file(path)
  rescue Psych::SyntaxError => e
    errors << "#{path}: invalid YAML: #{e.message}"
    next
  end

  missing = keys.reject { |key| obj.is_a?(Hash) && obj.key?(key) }
  errors << "#{path}: missing keys #{missing.join(',')}" unless missing.empty?
end

antipattern_path = "codex-ops/evals/antipattern-cases.yaml"
if File.file?(antipattern_path)
  data = YAML.load_file(antipattern_path)
  Array(data["cases"]).each_with_index do |item, idx|
    required = %w[id domain severity trigger_signals antipattern preferred_behavior forbidden_behavior evidence_required]
    missing = required.reject { |key| item.is_a?(Hash) && item.key?(key) }
    errors << "#{antipattern_path}:case #{idx + 1}: missing keys #{missing.join(',')}" unless missing.empty?
  end
end

if errors.empty?
  puts "learning-data: OK"
else
  warn errors.join("\n")
  exit 1
end
RUBY
