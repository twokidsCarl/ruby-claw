# frozen_string_literal: true

module Claw
  module Resources
    # Reversible resource wrapping Mana::Context (messages + summaries).
    # Snapshots are deep copies of the messages and summaries arrays.
    class ContextResource
      include Claw::Resource

      def initialize(context)
        @context = context
      end

      # Deep-copy messages and summaries arrays.
      def snapshot!
        {
          messages: deep_copy(@context.messages),
          summaries: deep_copy(@context.summaries)
        }
      end

      # Replace messages and summaries with the snapshot's copies.
      def rollback!(token)
        @context.messages.replace(deep_copy(token[:messages]))
        @context.summaries.replace(deep_copy(token[:summaries]))
      end

      # Human-readable diff between two snapshots.
      def diff(token_a, token_b)
        msgs_a = token_a[:messages].size
        msgs_b = token_b[:messages].size
        sums_a = token_a[:summaries].size
        sums_b = token_b[:summaries].size

        lines = []
        lines << "messages: #{msgs_a} → #{msgs_b}" if msgs_a != msgs_b

        # Show added messages
        if msgs_b > msgs_a
          token_b[:messages][msgs_a..].each do |msg|
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]
            preview = content.is_a?(String) ? content[0, 80] : "(#{content.size} blocks)"
            lines << "  + [#{role}] #{preview}"
          end
        end

        lines << "summaries: #{sums_a} → #{sums_b}" if sums_a != sums_b
        lines.empty? ? "(no changes)" : lines.join("\n")
      end

      # Render current context state as Markdown.
      def to_md
        msgs = @context.messages.size
        sums = @context.summaries.size
        "#{msgs} messages, #{sums} summaries"
      end

      private

      def deep_copy(obj)
        MarshalMd.load(MarshalMd.dump(obj))
      end
    end
  end
end
