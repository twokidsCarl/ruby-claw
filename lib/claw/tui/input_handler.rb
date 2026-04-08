# frozen_string_literal: true

module Claw
  module TUI
    # Enhanced input handling: syntax highlighting, tab completion, auto-indent.
    module InputHandler
      # Syntax highlight Ruby code using basic token patterns.
      # Returns ANSI-colored string.
      def self.highlight(code)
        code
          .gsub(/\b(def|end|class|module|if|else|elsif|unless|do|while|until|for|begin|rescue|ensure|return|yield|raise|require|require_relative|include|extend|attr_\w+)\b/) { "\e[35m#{$&}\e[0m" }
          .gsub(/\b(true|false|nil|self)\b/) { "\e[36m#{$&}\e[0m" }
          .gsub(/(#.*)$/) { "\e[2m#{$1}\e[0m" }
          .gsub(/(:[\w!?]+)/) { "\e[33m#{$1}\e[0m" }
          .gsub(/"([^"]*)"/) { "\e[32m\"#{$1}\"\e[0m" }
          .gsub(/'([^']*)'/) { "\e[32m'#{$1}'\e[0m" }
          .gsub(/\b(\d+\.?\d*)\b/) { "\e[34m#{$1}\e[0m" }
      end

      # Generate tab completion candidates from binding, memory, and commands.
      #
      # @param prefix [String] current input prefix
      # @param binding [Binding] caller's binding
      # @param memory [Claw::Memory, nil] memory for fact keywords
      # @return [Array<String>] completion candidates
      def self.completions(prefix, binding:, memory: nil)
        candidates = []

        begin
          # Local variables
          candidates.concat(binding.local_variables.map(&:to_s))

          # Receiver methods (filtered)
          receiver = binding.eval("self")
          candidates.concat(
            receiver.methods.map(&:to_s).reject { |m| m.start_with?("_") || (m.include?("!") && m.length < 3) }
          )
        rescue
          # Binding is invalid or inaccessible; skip local completions
        end

        # Slash commands
        candidates.concat(Claw::Commands::COMMANDS.map { |c| "/#{c}" })
        candidates.concat(%w[/plan /role /cd /source /doc /find /shell /memory /forget /help /ask /new])

        # Memory keywords
        if memory
          begin
            memory.long_term.each do |m|
              words = m[:content].to_s.split(/\s+/).select { |w| w.length > 3 }
              candidates.concat(words)
            end
          rescue
            # Memory access failed; skip
          end
        end

        candidates.uniq.select { |c| c.start_with?(prefix) }.sort
      end

      # Check if code has unclosed blocks (for multi-line continuation).
      def self.incomplete?(code)
        RubyVM::InstructionSequence.compile(code)
        false
      rescue SyntaxError => e
        e.message.include?("unexpected end-of-input") ||
          e.message.include?("unterminated")
      end

      # Calculate auto-indent level based on code structure.
      #
      # @param code [String] current multi-line buffer
      # @return [Integer] number of spaces to indent
      def self.indent_level(code)
        opens = code.scan(/\b(def|class|module|if|unless|while|until|for|do|begin|case)\b/).size
        closes = code.scan(/\bend\b/).size
        [(opens - closes) * 2, 0].max
      end
    end
  end
end
