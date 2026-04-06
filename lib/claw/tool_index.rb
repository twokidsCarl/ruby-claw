# frozen_string_literal: true

module Claw
  # Lightweight index of project tools in `.ruby-claw/tools/`.
  # Scans files via regex to extract tool_name and description without requiring them.
  class ToolIndex
    Entry = Struct.new(:name, :description, :path, keyword_init: true)

    attr_reader :entries

    def initialize(tools_dir)
      @tools_dir = tools_dir
      @entries = []
      scan! if tools_dir && Dir.exist?(tools_dir)
    end

    # Rebuild the index by scanning the tools directory.
    def scan!
      @entries = []
      return unless @tools_dir && Dir.exist?(@tools_dir)

      Dir.glob(File.join(@tools_dir, "*.rb")).each do |path|
        entry = extract_metadata(path)
        @entries << entry if entry
      end
    end

    # Search for tools matching a keyword (case-insensitive substring match).
    #
    # @param keyword [String]
    # @return [Array<Entry>]
    def search(keyword)
      return @entries if keyword.nil? || keyword.empty?

      pattern = keyword.downcase
      @entries.select do |e|
        e.name.downcase.include?(pattern) || e.description.downcase.include?(pattern)
      end
    end

    # Find an entry by exact name.
    #
    # @param name [String]
    # @return [Entry, nil]
    def find(name)
      @entries.find { |e| e.name == name }
    end

    # Load a tool class from its file. Returns the class or nil.
    #
    # @param name [String] tool name
    # @return [Class, nil] the class including Claw::Tool
    def load_tool(name)
      entry = find(name)
      return nil unless entry

      before_count = Claw::Tool.tool_classes.size
      Kernel.load(entry.path)
      new_classes = Claw::Tool.tool_classes[before_count..]

      # Prefer the class whose tool_name matches
      new_classes&.find { |c| c.tool_name == name } || new_classes&.first
    end

    private

    # Extract tool_name and description from a .rb file using regex.
    # Avoids require to keep startup fast.
    def extract_metadata(path)
      content = File.read(path, 4096) # Read only the first 4KB

      name_match = content.match(/tool_name\s+["']([^"']+)["']/)
      desc_match = content.match(/description\s+["']([^"']+)["']/)

      return nil unless name_match

      Entry.new(
        name: name_match[1],
        description: desc_match ? desc_match[1] : "",
        path: path
      )
    end
  end
end
