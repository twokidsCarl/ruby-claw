# frozen_string_literal: true

module Claw
  # Extended knowledge base — adds claw-specific topics, falls back to Mana::Knowledge.
  module Knowledge
    class << self
      # Query a topic: try claw-specific sections first, then delegate to Mana::Knowledge.
      def query(topic)
        topic_key = topic.to_s.strip.downcase

        # Try claw-specific sections (bidirectional substring match)
        match = claw_sections.find { |k, _| topic_key.include?(k) || k.include?(topic_key) }
        return "[source: claw]\n#{match.last}" if match

        # Fall back to mana's knowledge base
        Mana::Knowledge.query(topic)
      end

      private

      def claw_sections
        {
          "claw"          => overview,
          "agent"         => overview,
          "compaction"    => compaction,
          "session"       => session,
          "serializer"    => serializer,
          "persistence"   => session
        }
      end

      def overview
        <<~TEXT
          ruby-claw v#{Claw::VERSION} is an Agent framework built on ruby-mana.
          It adds interactive chat, persistent memory with compaction, session persistence,
          knowledge base, and runtime state serialization.

          Key components:
          - Claw::Chat — interactive REPL with streaming markdown output
          - Claw::Memory — enhanced memory with compaction, search, and session persistence
          - Claw::Serializer — save/restore runtime state across process restarts
          - Claw::Knowledge — extended knowledge base with claw-specific topics
        TEXT
      end

      def compaction
        <<~TEXT
          Memory compaction in Claw:
          When short-term memory exceeds the token pressure threshold
          (#{Claw.config.memory_pressure}), old messages are summarized by the LLM.
          - schedule_compaction: launches background compaction thread
          - compact!: synchronous compaction
          - needs_compaction?: checks token pressure
          - Keeps the #{Claw.config.memory_keep_recent} most recent conversation rounds
          - Summaries are rolling — merged on each compaction, never accumulate
          Configure via: Claw.configure { |c| c.memory_pressure = 0.7 }
        TEXT
      end

      def session
        <<~TEXT
          Session persistence in Claw:
          Conversation state (short-term memory + summaries) can be saved to disk
          and restored on next startup, enabling multi-session agents.
          - save_session: writes current state to disk
          - load_session: restores from disk (called automatically on init)
          - Stored as JSON in the sessions/ subdirectory of the memory store
          Configure via: Claw.configure { |c| c.persist_session = true }
        TEXT
      end

      def serializer
        <<~TEXT
          Runtime state serialization in Claw:
          Claw::Serializer can save and restore local variables and method definitions.
          - Claw::Serializer.save(binding, dir) — saves values.json + definitions.rb
          - Claw::Serializer.restore(binding, dir) — restores from saved files
          - Values: MarshalMd.dump (human-readable Markdown) with JSON fallback
          - Definitions: tracked via @__claw_definitions__ on the receiver
        TEXT
      end
    end
  end
end
