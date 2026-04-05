# frozen_string_literal: true

require "open3"
require "json"

module Claw
  # Self-evolution loop: reads execution traces, uses LLM to diagnose
  # improvements, forks runtime to apply changes, scores via test suite,
  # and keeps or discards the change atomically.
  #
  # Depends on:
  #   - v3 Runtime (fork/rollback)
  #   - v5.1 Traces (.ruby-claw/traces/)
  #   - v5.2 claw init (.ruby-claw/gems/ editable source)
  class Evolution
    class RejectError < StandardError; end

    DIAGNOSIS_SYSTEM = "You are a code improvement agent. Analyze execution traces and propose precise code changes. Respond only with valid JSON."

    DIAGNOSIS_PROMPT = <<~PROMPT
      Review these execution traces from a Ruby agent framework and propose ONE specific code change that would improve:
      - Response quality (better tool use, fewer iterations)
      - Performance (fewer tokens, lower latency)
      - Robustness (better error handling, edge cases)

      Respond with a JSON object:
      {
        "summary": "Brief description of the change",
        "gem": "ruby-claw or ruby-mana",
        "file": "relative/path/to/file.rb",
        "old_code": "exact existing code to replace (copy-paste from source)",
        "new_code": "replacement code",
        "rationale": "why this improves the agent"
      }

      If no meaningful improvements can be made, respond with:
      {"summary": "no changes needed"}

      IMPORTANT: old_code must be an exact substring of the file. Be precise.
    PROMPT

    attr_reader :results

    # @param runtime [Claw::Runtime] the reversible runtime
    # @param claw_dir [String] path to .ruby-claw/
    # @param config [Mana::Config] LLM configuration
    def initialize(runtime:, claw_dir:, config: Mana.config)
      @runtime = runtime
      @claw_dir = claw_dir
      @gems_dir = File.join(claw_dir, "gems")
      @config = config
      @results = []
    end

    # Run one evolution cycle: diagnose → propose → test → keep/discard.
    # Returns a result hash with :status, :proposal, :reason.
    def evolve
      traces = load_recent_traces
      if traces.empty?
        return log_result(status: :skip, reason: "no traces found")
      end

      unless Dir.exist?(@gems_dir)
        return log_result(status: :skip, reason: "no gems/ directory — run `claw init` first")
      end

      proposal = diagnose(traces)
      if proposal[:file].nil?
        return log_result(status: :skip, reason: proposal[:summary])
      end

      try_proposal(proposal)
    end

    # Load recent trace files as strings.
    def load_recent_traces(limit: 5)
      dir = File.join(@claw_dir, "traces")
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.md"))
        .sort_by { |f| File.mtime(f) }
        .last(limit)
        .map { |f| File.read(f) }
    end

    # Send traces to LLM for diagnosis. Returns a proposal hash.
    def diagnose(traces)
      prompt = DIAGNOSIS_PROMPT + "\n\n## Recent Traces\n\n" + traces.join("\n\n---\n\n")

      backend = Mana::Backends::Base.for(@config)
      response = backend.chat(
        system: DIAGNOSIS_SYSTEM,
        messages: [{ role: "user", content: prompt }],
        tools: [],
        model: @config.model
      )

      text = extract_text(response[:content])
      parse_proposal(text)
    rescue => e
      { summary: "diagnosis failed: #{e.message}" }
    end

    # Attempt to apply a proposal inside a runtime fork.
    def try_proposal(proposal)
      gem_name = proposal[:gem] || "ruby-claw"
      file_path = File.join(@gems_dir, gem_name, proposal[:file])

      unless File.exist?(file_path)
        return log_result(status: :reject, proposal: proposal[:summary],
                          reason: "file not found: #{proposal[:file]}")
      end

      content = File.read(file_path)
      unless content.include?(proposal[:old_code])
        return log_result(status: :reject, proposal: proposal[:summary],
                          reason: "old_code not found in #{proposal[:file]}")
      end

      success, result = @runtime.fork(label: "evolve: #{proposal[:summary]}") do
        # Apply the change
        modified = content.sub(proposal[:old_code], proposal[:new_code])
        File.write(file_path, modified)

        # Score: run tests
        score = run_tests(gem_name)
        unless score[:passed]
          raise RejectError, "tests failed:\n#{score[:output].to_s[0, 500]}"
        end

        score
      end

      if success
        # Write evolution log
        write_evolution_log(proposal, :accept, result)
        log_result(status: :accept, proposal: proposal[:summary],
                   rationale: proposal[:rationale])
      else
        write_evolution_log(proposal, :reject, result)
        log_result(status: :reject, proposal: proposal[:summary],
                   reason: result.is_a?(Exception) ? result.message : result.to_s)
      end
    end

    private

    def extract_text(content)
      return content.to_s unless content.is_a?(Array)
      content.filter_map { |b| b[:text] || b["text"] }.join
    end

    def parse_proposal(text)
      json_match = text.match(/\{[\s\S]*\}/)
      return { summary: "no JSON in response" } unless json_match

      parsed = JSON.parse(json_match[0], symbolize_names: true)
      parsed
    rescue JSON::ParserError
      { summary: "failed to parse proposal JSON" }
    end

    def run_tests(gem_name)
      gem_dir = File.join(@gems_dir, gem_name)
      return { passed: true, output: "no gem directory" } unless Dir.exist?(gem_dir)

      # Check if rspec is available
      gemfile = File.join(gem_dir, "Gemfile")
      unless File.exist?(gemfile)
        return { passed: true, output: "no Gemfile — skipping tests" }
      end

      out, status = Open3.capture2e(
        "bundle", "exec", "rspec", "--format", "progress",
        chdir: gem_dir
      )
      { passed: status.success?, output: out }
    rescue Errno::ENOENT
      # bundle/rspec not found
      { passed: true, output: "rspec not available — skipping" }
    end

    def write_evolution_log(proposal, status, result)
      log_dir = File.join(@claw_dir, "evolution")
      FileUtils.mkdir_p(log_dir)

      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      path = File.join(log_dir, "#{timestamp}_#{status}.md")

      lines = []
      lines << "# Evolution: #{proposal[:summary]}"
      lines << ""
      lines << "- Status: #{status}"
      lines << "- Gem: #{proposal[:gem]}"
      lines << "- File: #{proposal[:file]}"
      lines << "- Rationale: #{proposal[:rationale]}"
      lines << "- Timestamp: #{Time.now.iso8601}"
      lines << ""
      lines << "## Old Code"
      lines << "```ruby"
      lines << proposal[:old_code].to_s
      lines << "```"
      lines << ""
      lines << "## New Code"
      lines << "```ruby"
      lines << proposal[:new_code].to_s
      lines << "```"

      if result.is_a?(Hash) && result[:output]
        lines << ""
        lines << "## Test Output"
        lines << "```"
        lines << result[:output].to_s[0, 2000]
        lines << "```"
      end

      File.write(path, lines.join("\n"))
    rescue => e
      # Don't crash on log failure
    end

    def log_result(result)
      @results << result
      result
    end
  end
end
