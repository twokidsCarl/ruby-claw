# frozen_string_literal: true

module Claw
  # Manages the tool lifecycle: indexing, searching, loading, and tracking.
  # Bridges project tools (Claw::Tool classes) with Mana's tool registration.
  class ToolRegistry
    attr_reader :index, :loaded_tools

    def initialize(tools_dir: nil, hub: nil)
      @tools_dir = tools_dir
      @index = ToolIndex.new(tools_dir)
      @hub = hub
      @loaded_tools = {} # name → tool class
    end

    # Search local index (and optionally hub) for tools matching a keyword.
    #
    # @param keyword [String]
    # @return [Array<Hash>] [{name:, description:, source:, loaded:}]
    def search(keyword)
      results = @index.search(keyword).map do |entry|
        { name: entry.name, description: entry.description,
          source: "project", loaded: @loaded_tools.key?(entry.name) }
      end

      # Query hub if configured and local results are sparse
      if @hub && results.size < 3
        hub_results = @hub.search(keyword) rescue []
        hub_results.each do |hr|
          next if results.any? { |r| r[:name] == hr[:name] }
          results << hr.merge(source: "hub", loaded: false)
        end
      end

      results
    end

    # Load a tool by name. Requires the file, registers with Mana.
    #
    # @param name [String]
    # @return [String] success/error message
    def load(name)
      return "Tool '#{name}' is already loaded" if @loaded_tools.key?(name)

      # Try local index first
      klass = @index.load_tool(name)

      # Try downloading from hub if not found locally
      if klass.nil? && @hub
        downloaded = download_from_hub(name)
        klass = @index.load_tool(name) if downloaded
      end

      return "Tool '#{name}' not found" unless klass

      register_with_mana(klass)
      @loaded_tools[name] = klass
      "Tool '#{name}' loaded successfully"
    end

    # Check if a tool is currently loaded.
    def loaded?(name)
      @loaded_tools.key?(name)
    end

    # Unload a tool (remove from Mana's registered tools).
    def unload(name)
      return "Tool '#{name}' is not loaded" unless @loaded_tools.key?(name)

      # Remove from Mana's registrations
      Mana.instance_variable_get(:@registered_tools)&.reject! { |t| t[:name] == name }
      Mana.instance_variable_get(:@tool_handlers)&.delete(name)
      @loaded_tools.delete(name)
      "Tool '#{name}' unloaded"
    end

    # Download a tool from the hub into the local tools directory.
    def download_from_hub(name)
      return false unless @hub && @tools_dir

      @hub.download(name, target_dir: @tools_dir)
      @index.scan! # Refresh index
      true
    rescue => e
      false
    end

    private

    def register_with_mana(klass)
      definition = klass.to_tool_definition
      Mana.register_tool(definition) do |input|
        kwargs = input.transform_keys(&:to_sym)
        klass.new.call(**kwargs)
      rescue => e
        "error: #{e.class}: #{e.message}"
      end
    end
  end
end
