# frozen_string_literal: true

module Claw
  # Standalone long-term memory with compaction, session persistence, and search.
  # No longer inherits from Mana::Memory — reads/writes Mana::Context for conversation state.
  class Memory
    SUMMARIZE_MAX_RETRIES = 3

    attr_reader :long_term

    def initialize
      @long_term = []
      @next_id = 1
      @compact_mutex = Mutex.new
      @compact_thread = nil
      load_long_term
      load_session if Claw.config.persist_session
    end

    # --- Class methods ---

    class << self
      # Check if the current thread is in claw incognito mode
      def incognito?
        Thread.current[:claw_incognito] == true
      end

      # Run a block with claw memory disabled. Long-term memory won't be
      # loaded or saved, and the remember tool will be inactive.
      def incognito(&block)
        prev_incognito = Thread.current[:claw_incognito]
        prev_memory = Thread.current[:claw_memory]
        Thread.current[:claw_incognito] = true
        Thread.current[:claw_memory] = nil
        block.call
      ensure
        Thread.current[:claw_incognito] = prev_incognito
        Thread.current[:claw_memory] = prev_memory
      end

      # Return the current thread's Claw memory instance (lazy-initialized).
      # Uses a separate thread-local from Mana::Context.
      # Returns nil in incognito mode.
      def current
        return nil if incognito?

        Thread.current[:claw_memory] ||= new
      end
    end

    # --- Token estimation ---

    # Rough token estimate: ~4 characters per token
    def estimate_tokens(text)
      return 0 unless text.is_a?(String)

      (text.length / 4.0).ceil
    end

    # Estimate total token count across long-term memories + context messages/summaries
    def token_count
      count = 0
      @long_term.each { |m| count += estimate_tokens(m[:content]) }
      context = Mana::Context.current
      if context
        context.messages.each do |msg|
          content = msg[:content]
          case content
          when String then count += estimate_tokens(content)
          when Array
            content.each { |block| count += estimate_tokens(block[:text] || block[:content] || "") }
          end
        end
        context.summaries.each { |s| count += estimate_tokens(s) }
      end
      count
    end

    # --- Long-term memory management ---

    # Store a fact in long-term memory. Deduplicates by content.
    # Persists to disk immediately after adding.
    def remember(content)
      existing = @long_term.find { |e| e[:content] == content }
      return existing if existing

      entry = { id: @next_id, content: content, created_at: Time.now.iso8601 }
      @next_id += 1
      @long_term << entry
      store.write(namespace, @long_term)
      claw_store.append_log(title: "Remembered", detail: "- #{content}")
      entry
    end

    # Remove a specific long-term memory by ID and persist the change
    def forget(id:)
      @long_term.reject! { |m| m[:id] == id }
      store.write(namespace, @long_term)
    end

    # Clear persistent memories from both in-memory array and disk
    def clear_long_term!
      @long_term.clear
      store.clear(namespace)
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

      context = Mana::Context.current
      data = {
        short_term: context&.messages || [],
        summaries: context&.summaries || [],
        saved_at: Time.now.iso8601
      }
      claw_store.write_session(namespace, data)
    end

    # Load previous session from disk
    def load_session
      return unless Claw.config.persist_session

      data = claw_store.read_session(namespace)
      return unless data

      context = Mana::Context.current
      if data[:short_term].is_a?(Array) && context
        context.messages.concat(data[:short_term])
      end
      if data[:summaries].is_a?(Array) && context
        context.summaries.concat(data[:summaries])
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
        score = keywords.count { |kw| content.include?(kw) }
        score += 2 if content.include?(query.downcase)
        { entry: entry, score: score }
      end

      scored
        .select { |s| s[:score] > 0 }
        .sort_by { |s| -s[:score] }
        .first(top_k)
        .map { |s| s[:entry] }
    end

    # --- Clearing ---

    # Clear all memory (long-term + context + session)
    def clear!
      @long_term.clear
      store.clear(namespace)
      claw_store.clear_session(namespace)
      Mana::Context.current&.clear!
    end

    # --- Display ---

    def inspect
      "#<Claw::Memory long_term=#{long_term.size}, short_term=#{short_term_rounds} rounds, tokens=#{token_count}/#{context_window}>"
    end

    private

    def short_term_rounds
      context = Mana::Context.current
      return 0 unless context
      context.messages.count { |m| m[:role] == "user" && m[:content].is_a?(String) }
    end

    def context_window
      Mana.config.context_window
    end

    # Claw uses its own FileStore for session/log support
    def claw_store
      @claw_store ||= Claw::FileStore.new
    end

    # Resolve memory store: user config > default file-based store
    def store
      Mana.config.memory_store || default_store
    end

    # Lazy-initialized default FileStore singleton
    def default_store
      @default_store ||= Mana::FileStore.new
    end

    def namespace
      ns = Mana.config.namespace
      return ns if ns && !ns.to_s.empty?

      dir = `git rev-parse --show-toplevel 2>/dev/null`.strip
      return File.basename(dir) unless dir.empty?

      d = Dir.pwd
      loop do
        return File.basename(d) if File.exist?(File.join(d, "Gemfile"))
        parent = File.dirname(d)
        break if parent == d
        d = parent
      end

      File.basename(Dir.pwd)
    end

    # Load long-term memories from the persistent store on initialization.
    def load_long_term
      return if self.class.incognito?

      @long_term = store.read(namespace)
      @next_id = (@long_term.map { |m| m[:id] }.max || 0) + 1
    end

    # Compact short-term memory: summarize old messages and keep only recent rounds.
    def perform_compaction
      context = Mana::Context.current
      return unless context

      keep_recent = Claw.config.memory_keep_recent
      messages = context.messages
      user_indices = messages.each_with_index
        .select { |msg, _| msg[:role] == "user" && msg[:content].is_a?(String) }
        .map(&:last)

      return if user_indices.size <= keep_recent

      keep = [keep_recent, user_indices.size].min
      cutoff_user_idx = user_indices[-keep]
      old_messages = messages[0...cutoff_user_idx]
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
      unless context.summaries.empty?
        prior_context = "Previous summary:\n#{context.summaries.join("\n")}\n\nNew conversation:\n"
      end

      # Calculate tokens for kept content
      kept_messages = messages[cutoff_user_idx..]
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

      context.messages.replace(kept_messages)
      context.summaries.replace([summary])

      Claw.config.on_compact&.call(summary)
      claw_store.append_log(title: "Memory compacted", detail: "- Summaries updated")
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
