# frozen_string_literal: true

module Claw
  module Resources
    # Reversible resource wrapping a Ruby Binding.
    #
    # Tracks all local variables by default. Uses binding diff to detect changes
    # after each eval. Non-serializable variables are automatically excluded
    # with a warning.
    #
    # Serialization: MarshalMd.dump for human-readable Markdown snapshots.
    class BindingResource
      include Claw::Resource

      attr_reader :tracked, :excluded

      # @param binding [Binding] the binding to track
      # @param on_exclude [Proc, nil] called with (name, error) when a variable is excluded
      def initialize(binding, on_exclude: nil)
        @binding = binding
        @tracked = {}    # name => last known Marshal blob
        @excluded = {}   # name => reason string
        @on_exclude = on_exclude
        scan_binding
      end

      # Snapshot all tracked variables. Returns a frozen Hash of { name => Marshal blob }.
      def snapshot!
        scan_binding
        @tracked.transform_values(&:dup).freeze
      end

      # Restore tracked variables from a snapshot token.
      def rollback!(token)
        token.each do |name, blob|
          value = MarshalMd.load(blob)
          @binding.local_variable_set(name, value)
        end
        # Remove variables that exist now but didn't exist in the snapshot
        current_vars = @binding.local_variables.map(&:to_s)
        snapshot_vars = token.keys.map(&:to_s)
        (current_vars - snapshot_vars).each do |name|
          # Can't remove local variables in Ruby, but we can set them to nil
          @binding.local_variable_set(name.to_sym, nil) if @tracked.key?(name)
        end
        @tracked = token.transform_values(&:dup)
      end

      # Human-readable diff between two snapshot tokens.
      def diff(token_a, token_b)
        all_keys = (token_a.keys + token_b.keys).uniq
        lines = []

        all_keys.each do |name|
          in_a = token_a.key?(name)
          in_b = token_b.key?(name)

          if in_a && in_b
            if token_a[name] != token_b[name]
              val_a = safe_inspect(MarshalMd.load(token_a[name]))
              val_b = safe_inspect(MarshalMd.load(token_b[name]))
              lines << "~ #{name}: #{val_a} → #{val_b}"
            end
          elsif in_b
            val = safe_inspect(MarshalMd.load(token_b[name]))
            lines << "+ #{name} = #{val}"
          else
            val = safe_inspect(MarshalMd.load(token_a[name]))
            lines << "- #{name} = #{val}"
          end
        end

        lines.empty? ? "(no changes)" : lines.join("\n")
      end

      # Render current tracked variables as Markdown.
      def to_md
        scan_binding
        lines = []
        lines << "#{@tracked.size} tracked, #{@excluded.size} excluded"
        @tracked.each do |name, blob|
          val = safe_inspect(MarshalMd.load(blob))
          lines << "- `#{name}` = #{val}"
        end
        @excluded.each do |name, reason|
          lines << "- `#{name}` (excluded: #{reason})"
        end
        lines.join("\n")
      end

      # Scan the binding for new/changed variables.
      # Call this after each eval to pick up changes.
      def scan_binding
        @binding.local_variables.each do |sym|
          name = sym.to_s
          next if @excluded.key?(name)

          value = @binding.local_variable_get(sym)
          begin
            blob = MarshalMd.dump(value)
            @tracked[name] = blob
          rescue TypeError => e
            @excluded[name] = e.message
            @tracked.delete(name)
            @on_exclude&.call(name, e)
          end
        end
      end

      private

      def safe_inspect(value)
        str = value.inspect
        str.length > 80 ? "#{str[0, 77]}..." : str
      end
    end
  end
end
