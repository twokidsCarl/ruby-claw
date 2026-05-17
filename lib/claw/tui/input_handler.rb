# frozen_string_literal: true

require "ripper"

module Claw
  module TUI
    # Enhanced input handling: syntax highlighting, tab completion, auto-indent.
    module InputHandler
      # ANSI color codes for each Ripper token type. Keep in sync with the
      # palette in lib/claw/tui/styles.rb (magenta keywords, green strings,
      # blue numbers, yellow symbols, cyan literals, dim comments).
      TOKEN_COLORS = {
        # Keywords (def, end, if, do, etc.) — magenta
        on_kw: "\e[35m",
        # Constants (Class, Module names) — cyan
        on_const: "\e[36m",
        # String literals — green
        on_tstring_beg:    "\e[32m",
        on_tstring_content:"\e[32m",
        on_tstring_end:    "\e[32m",
        # Embedded expressions in strings stay green at the boundary
        # markers; the inner expression gets normal coloring
        # Numbers — blue
        on_int:   "\e[34m",
        on_float: "\e[34m",
        on_imaginary: "\e[34m",
        on_rational:  "\e[34m",
        # Symbols — yellow
        on_symbeg:        "\e[33m",
        on_dyna_symbeg:   "\e[33m",
        on_label:         "\e[33m",
        on_label_end:     "\e[33m",
        # Comments — dim
        on_comment:    "\e[2m",
        on_embdoc_beg: "\e[2m",
        on_embdoc:     "\e[2m",
        on_embdoc_end: "\e[2m",
      }.freeze
      RESET = "\e[0m"

      # A few Ruby identifiers come through as :on_kw and are styled like
      # keywords, but historically we colored them cyan (literals). Override
      # so the visual stays consistent with prior behavior.
      LITERAL_KEYWORDS = %w[true false nil self __method__ __callee__].freeze

      # Syntax-highlight Ruby code with proper tokenization.
      #
      # Uses Ripper.lex (stdlib) rather than ad-hoc regex, which means:
      # - New Ruby keywords (case/in patterns in 3.0+, `it` block param in 3.4+)
      #   are highlighted as the parser sees them, without us maintaining a
      #   keyword list
      # - String interpolation, heredocs, %w() literals etc. don't get
      #   mis-colored (the old regex e.g. broke on "hello #{x}")
      # - Comments inside strings are not falsely dimmed
      #
      # Returns ANSI-colored string. If Ripper raises (extremely rare — it
      # tolerates syntactically incomplete input), the original code is
      # returned uncolored rather than crashing the TUI.
      def self.highlight(code)
        return code if code.nil? || code.empty?

        tokens = Ripper.lex(code)
        return code if tokens.nil? || tokens.empty?

        # Ripper.lex returns [[line, col], type, token, state]. The tokens
        # in order, concatenated, reproduce the original string exactly.
        # Track whether the previous token was a symbol-begin so the
        # following identifier inherits the symbol color (a literal :foo
        # comes through as two tokens: :on_symbeg "::" + :on_ident "foo").
        out = +""
        in_symbol = false
        tokens.each do |(_pos, type, token, _state)|
          if type == :on_symbeg || type == :on_dyna_symbeg
            out << "\e[33m#{token}#{RESET}"
            in_symbol = true
          elsif in_symbol && %i[on_ident on_const on_op on_kw].include?(type)
            out << "\e[33m#{token}#{RESET}"
            in_symbol = false
          elsif type == :on_kw && LITERAL_KEYWORDS.include?(token)
            out << "\e[36m#{token}#{RESET}"
            in_symbol = false
          elsif (color = TOKEN_COLORS[type])
            out << "#{color}#{token}#{RESET}"
            in_symbol = false
          else
            out << token
            # Whitespace between :symbeg and the identifier shouldn't break the
            # carry-over. Only reset on a non-whitespace, non-symbol token.
            in_symbol = false unless type == :on_sp
          end
        end
        out
      rescue StandardError
        # Ripper failures should never crash the renderer
        code
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

          # Include private methods (def in eval creates private methods)
          candidates.concat(
            receiver.private_methods(false).map(&:to_s).reject { |m| m.start_with?("_") || (m.include?("!") && m.length < 3) }
          )

          # Include tracked REPL definitions
          if receiver.instance_variable_defined?(:@__claw_definitions__)
            candidates.concat(receiver.instance_variable_get(:@__claw_definitions__).keys)
          end
        rescue
          # Binding is invalid or inaccessible; skip local completions
        end

        # Slash commands
        candidates.concat(Claw::Commands::COMMANDS.map { |c| "/#{c}" })
        candidates.concat(%w[/help /ask /new /plan /cd /source /doc /find])

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
