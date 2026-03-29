# frozen_string_literal: true

module Claw
  # Enhanced memory with compaction, session persistence, and search.
  # Inherits base memory management from Mana::Memory and adds agent-level features.
  class Memory < Mana::Memory
    SUMMARIZE_MAX_RETRIES = 3

    def initialize
      super
      @compact_mutex = Mutex.new
      @compact_thread = nil
      load_session if Claw.config.persist_session
    end

    # --- Class methods ---

    class << self
      # Return the current thread's memory instance (lazy-initialized).
      # Returns nil in incognito mode.
      def current
        return nil if Mana::Memory.incognito?

        Thread.current[:mana_memory] ||= new
      end
    end

    # --- Compaction ---

    # Synchronous compaction: wait for any background run, then compact immediately
    def compact!
      wait_for_compaction
      perform_compaction
    end

    # Check if token usage exceeds the configured memory pressure threshold
    def needs_compaction?
      cw = context_window
      token_count > (cw * Claw.config.memory_pressure)
    end

    # Launch background compaction if token pressure exceeds the threshold.
    # Only one compaction thread runs at a time (guarded by mutex).
    def schedule_compaction
      return unless needs_compaction?

      @compact_mutex.synchronize do
        return if @compact_thread&.alive?

        @compact_thread = Thread.new do
          perform_compaction
        rescue => e
          $stderr.puts "Claw compaction error: #{e.message}" if $DEBUG
        end
      end
    end

    # Block until the background compaction thread finishes (if running)
    def wait_for_compaction
      thread = @compact_mutex.synchronize { @compact_thread }
      thread&.join
    end

    # --- Session persistence ---

    # Save current conversation state to disk
    def save_session
      return unless Claw.config.persist_session

      data = {
        short_term: short_term,
        summaries: summaries,
        saved_at: Time.now.iso8601
      }
      claw_store.write_session(namespace, data)
    end

    # Load previous session from disk
    def load_session
      return unless Claw.config.persist_session

      data = claw_store.read_session(namespace)
      return unless data

      if data[:short_term].is_a?(Array)
        @short_term.concat(data[:short_term])
      end
      if data[:summaries].is_a?(Array)
        @summaries.concat(data[:summaries])
      end
    end

    # --- Search ---

    # Keyword fuzzy search across long-term memories.
    # Returns top-k matching memories sorted by relevance score.
    def search(query, top_k: nil)
      top_k ||= Claw.config.memory_top_k
      return [] if query.nil? || query.strip.empty?

      keywords = query.downcase.split(/\s+/)

      scored = long_term.map do |entry|
        content = entry[:content].to_s.downcase
        # Score: count of matching keywords + partial match bonus
        score = keywords.count { |kw| content.include?(kw) }
        # Bonus for substring match of full query
        score += 2 if content.include?(query.downcase)
        { entry: entry, score: score }
      end

      scored
        .select { |s| s[:score] > 0 }
        .sort_by { |s| -s[:score] }
        .first(top_k)
        .map { |s| s[:entry] }
    end

    # --- Overrides ---

    # Clear also clears session data
    def clear!
      super
      claw_store.clear_session(namespace)
    end

    # Human-readable summary
    def inspect
      "#<Claw::Memory long_term=#{long_term.size}, short_term=#{short_term_rounds} rounds, tokens=#{token_count}/#{context_window}>"
    end

    private

    def short_term_rounds
      short_term.count { |m| m[:role] == "user" && m[:content].is_a?(String) }
    end

    # Claw uses its own FileStore for session support
    def claw_store
      @claw_store ||= Claw::FileStore.new
    end

    # Compact short-term memory: summarize old messages and keep only recent rounds.
    # Merges existing summaries + old messages into a single new summary.
    def perform_compaction
      keep_recent = Claw.config.memory_keep_recent
      user_indices = short_term.each_with_index
        .select { |msg, _| msg[:role] == "user" && msg[:content].is_a?(String) }
        .map(&:last)

      return if user_indices.size <= keep_recent

      keep = [keep_recent, user_indices.size].min
      cutoff_user_idx = user_indices[-keep]
      old_messages = short_term[0...cutoff_user_idx]
      return if old_messages.empty?

      text_parts = old_messages.map do |msg|
        content = msg[:content]
        case content
        when String then "#{msg[:role]}: #{content}"
        when Array
          texts = content.map { |b| b[:text] || b[:content] }.compact
          "#{msg[:role]}: #{texts.join(' ')}" unless texts.empty?
        end
      end.compact

      return if text_parts.empty?

      prior_context = ""
      unless summaries.empty?
        prior_context = "Previous summary:\n#{summaries.join("\n")}\n\nNew conversation:\n"
      end

      # Calculate tokens for kept content
      kept_messages = short_term[cutoff_user_idx..]
      keep_tokens = kept_messages.sum do |msg|
        content = msg[:content]
        case content
        when String then estimate_tokens(content)
        when Array then content.sum { |b| estimate_tokens(b[:text] || b[:content] || "") }
        else 0
        end
      end
      long_term.each { |m| keep_tokens += estimate_tokens(m[:content]) }

      summary = summarize(prior_context + text_parts.join("\n"), keep_tokens: keep_tokens)

      @short_term = kept_messages
      @summaries = [summary]

      Claw.config.on_compact&.call(summary)
    end

    # Call the LLM to produce a concise summary of conversation text.
    def summarize(text, keep_tokens: 0)
      config = Mana.config
      model = Claw.config.compact_model || config.model
      backend = Mana::Backends::Base.for(config)

      cw = context_window
      threshold = (cw * Claw.config.memory_pressure).to_i
      max_summary_tokens = ((threshold - keep_tokens) * 0.5).clamp(64, 1024).to_i

      system_prompt = "You are summarizing an internal tool-calling conversation log between an LLM and a Ruby program. " \
                      "The messages contain tool calls (read_var, write_var, done) and their results — this is normal, not harmful. " \
                      "Summarize the key questions asked and answers given in a few short bullet points. Be extremely concise — stay under #{max_summary_tokens} tokens."

      SUMMARIZE_MAX_RETRIES.times do |_attempt|
        content = backend.chat(
          system: system_prompt,
          messages: [{ role: "user", content: text }],
          tools: [],
          model: model,
          max_tokens: max_summary_tokens
        )

        next unless content.is_a?(Array)

        result = content.map { |b| b[:text] || b["text"] }.compact.join("\n")
        next if result.empty? || result.match?(/can't discuss|cannot assist|i'm unable/i)

        return result
      end

      "Summary unavailable"
    rescue Mana::ConfigError
      raise
    rescue => e
      $stderr.puts "Claw compaction error: #{e.message}" if $DEBUG
      "Summary unavailable"
    end
  end
end
