# frozen_string_literal: true

module Claw
  module Resources
    # Reversible resource wrapping Claw::Memory's long_term array.
    # On rollback, restores the in-memory array and syncs to MEMORY.md.
    class MemoryResource
      include Claw::Resource

      def initialize(memory)
        @memory = memory
      end

      # Deep-copy the long_term array.
      def snapshot!
        MarshalMd.load(MarshalMd.dump(@memory.long_term))
      end

      # Restore long_term array and sync to disk.
      def rollback!(token)
        restored = MarshalMd.load(MarshalMd.dump(token))
        @memory.long_term.replace(restored)
        # Sync to MEMORY.md so file matches in-memory state
        store = @memory.send(:store)
        ns = @memory.send(:namespace)
        store.write(ns, @memory.long_term)
      end

      # Human-readable diff between two snapshots.
      def diff(token_a, token_b)
        ids_a = token_a.map { |m| m[:id] }.to_set
        ids_b = token_b.map { |m| m[:id] }.to_set

        added = token_b.select { |m| !ids_a.include?(m[:id]) }
        removed = token_a.select { |m| !ids_b.include?(m[:id]) }

        lines = []
        added.each { |m| lines << "+ [#{m[:id]}] #{m[:content]}" }
        removed.each { |m| lines << "- [#{m[:id]}] #{m[:content]}" }
        lines.empty? ? "(no changes)" : lines.join("\n")
      end

      # Render current memory state as Markdown.
      def to_md
        count = @memory.long_term.size
        if count == 0
          "(empty)"
        else
          lines = ["#{count} memories:"]
          @memory.long_term.each do |m|
            lines << "- [#{m[:id]}] #{m[:content]}"
          end
          lines.join("\n")
        end
      end
    end
  end
end
