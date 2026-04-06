# frozen_string_literal: true

module Claw
  module TUI
    # Detect @filename references in user input and render file cards.
    module FileCard
      # Pattern to match @filename references (supports glob patterns).
      FILE_REF_PATTERN = /@([\w.*\/\-]+(?:\.\w+)?)/

      # Extract file references from input text.
      #
      # @param input [String] user input
      # @return [Array<String>] list of file reference patterns
      def self.extract_refs(input)
        input.scan(FILE_REF_PATTERN).flatten
      end

      # Resolve a file reference to actual file paths.
      # Supports glob patterns like @*.rb.
      #
      # @param ref [String] file reference (e.g., "user.rb" or "*.rb")
      # @return [Array<String>] resolved file paths
      def self.resolve(ref)
        if ref.include?("*")
          Dir.glob(ref)
        elsif File.exist?(ref)
          [ref]
        else
          []
        end
      end

      # Render a compact file card for display.
      #
      # @param path [String] file path
      # @return [String] rendered card
      def self.render_card(path)
        return "  (file not found: #{path})" unless File.exist?(path)

        stat = File.stat(path)
        ext = File.extname(path).delete(".")
        lines = File.readlines(path).size rescue 0
        size = format_size(stat.size)
        lang = language_for(ext)

        card = Lipgloss::Style.new
          .border(:rounded)
          .border_foreground(Styles::DIM_GRAY)
          .padding(0, 1)
          .render("#{path} | #{lines} lines | #{lang} | #{size}")

        card
      end

      # Read file content for injection into LLM context.
      #
      # @param path [String] file path
      # @return [String] file content (truncated if large)
      def self.read_for_context(path)
        return "" unless File.exist?(path)

        content = File.read(path, 50_001) || ""
        if content.length > 50_000
          content = content[0, 50_000] + "\n... (truncated)"
        end
        "# File: #{path}\n```\n#{content}\n```"
      end

      # --- Helpers ---

      def self.format_size(bytes)
        return "#{bytes}B" if bytes < 1024
        return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024
        "#{(bytes / (1024.0 * 1024)).round(1)}MB"
      end

      def self.language_for(ext)
        { "rb" => "Ruby", "py" => "Python", "js" => "JavaScript", "ts" => "TypeScript",
          "rs" => "Rust", "go" => "Go", "java" => "Java", "c" => "C", "cpp" => "C++",
          "md" => "Markdown", "json" => "JSON", "yml" => "YAML", "yaml" => "YAML",
          "sh" => "Shell", "sql" => "SQL", "html" => "HTML", "css" => "CSS"
        }.fetch(ext, ext.upcase)
      end

      private_class_method :format_size, :language_for
    end
  end
end
