# frozen_string_literal: true

require "sinatra/base"
require "json"

module Claw
  module Console
    # Local web server for agent observability and operations.
    # Serves the console UI and provides API endpoints.
    class Server < Sinatra::Base
      set :views, File.join(__dir__, "views")
      set :public_folder, File.join(__dir__, "public")
      set :bind, "127.0.0.1"
      set :port, 4567
      set :server, :webrick

      # Allow all hosts in development/testing (console is localhost-only)
      set :host_authorization, { permitted_hosts: [] }

      # Shared state — configured before starting
      class << self
        attr_accessor :event_logger, :runtime, :memory_instance, :claw_dir
      end

      # Configure the server with runtime references.
      def self.setup(claw_dir:, runtime: nil, memory: nil, port: 4567)
        self.claw_dir = claw_dir
        self.runtime = runtime
        self.memory_instance = memory
        self.event_logger = EventLogger.new(File.join(claw_dir, "log"))
        set :port, port
      end

      # --- Pages ---

      get "/" do
        erb :index
      end

      get "/prompt" do
        erb :prompt
      end

      get "/monitor" do
        erb :monitor
      end

      get "/traces" do
        erb :traces
      end

      get "/memory" do
        erb :memory
      end

      get "/tools" do
        erb :tools
      end

      get "/snapshots" do
        erb :snapshots
      end

      get "/experiments" do
        erb :experiments
      end

      # --- API Endpoints ---

      get "/api/status" do
        content_type :json
        {
          version: Claw::VERSION,
          state: self.class.runtime&.state,
          snapshot_count: self.class.runtime&.snapshots&.size || 0,
          memory_count: self.class.memory_instance&.long_term&.size || 0,
          tool_count: Mana.registered_tools.size,
          event_count: self.class.event_logger&.count || 0
        }.to_json
      end

      get "/api/events" do
        content_type "text/event-stream"
        cache_control :no_cache

        stream(:keep_open) do |out|
          SSE.stream_events(out, self.class.event_logger)
        end
      end

      get "/api/traces" do
        content_type :json
        traces_dir = File.join(self.class.claw_dir, "traces")
        unless Dir.exist?(traces_dir)
          return [].to_json
        end

        files = Dir.glob(File.join(traces_dir, "*.md")).sort.reverse.first(50)
        files.map do |f|
          { id: File.basename(f, ".md"), filename: File.basename(f),
            size: File.size(f), modified: File.mtime(f).iso8601 }
        end.to_json
      end

      get "/api/traces/:id" do
        content_type :json
        halt 400, { error: "Invalid trace ID" }.to_json unless params[:id] =~ /\A[a-zA-Z0-9_\-]+\z/

        path = File.join(self.class.claw_dir, "traces", "#{params[:id]}.md")
        halt 404, { error: "Trace not found" }.to_json unless File.exist?(path)

        { id: params[:id], content: File.read(path) }.to_json
      end

      get "/api/memory" do
        content_type :json
        mem = self.class.memory_instance
        unless mem
          return [].to_json
        end

        mem.long_term.to_json
      end

      get "/api/prompt" do
        content_type :json
        prompt_path = File.join(self.class.claw_dir, "system_prompt.md")
        content = File.exist?(prompt_path) ? File.read(prompt_path) : ""

        sections = Mana.instance_variable_get(:@prompt_sections)&.filter_map(&:call) || []

        { template: content, sections: sections }.to_json
      end

      get "/api/prompt/sections" do
        content_type :json
        sections = Mana.instance_variable_get(:@prompt_sections)&.filter_map(&:call) || []
        sections.to_json
      end

      get "/api/tools" do
        content_type :json
        registry = Claw.tool_registry
        core_tools = Mana.registered_tools.map { |t| { name: t[:name], description: t[:description], source: "core" } }

        project_tools = registry ? registry.index.entries.map do |e|
          { name: e.name, description: e.description, source: "project",
            loaded: registry.loaded?(e.name) }
        end : []

        { core: core_tools, project: project_tools }.to_json
      end

      # --- Helpers ---

      helpers do
        def parse_json!
          data = JSON.parse(request.body.read, symbolize_names: true)
          data
        rescue JSON::ParserError
          halt 400, { error: "Invalid JSON" }.to_json
        end

        def require_field!(data, field)
          halt 400, { error: "Missing field: #{field}" }.to_json unless data[field]
        end
      end

      # --- Mutation API ---

      post "/api/memory" do
        content_type :json
        data = parse_json!
        require_field!(data, :content)
        mem = self.class.memory_instance
        halt 400, { error: "Memory not available" }.to_json unless mem

        entry = mem.remember(data[:content])
        { success: true, entry: entry }.to_json
      end

      delete "/api/memory/:id" do
        content_type :json
        halt 400, { error: "Invalid ID" }.to_json unless params[:id] =~ /\A\d+\z/
        mem = self.class.memory_instance
        halt 400, { error: "Memory not available" }.to_json unless mem

        mem.forget(id: params[:id].to_i)
        { success: true }.to_json
      end

      post "/api/prompt" do
        content_type :json
        data = parse_json!
        require_field!(data, :content)
        path = File.join(self.class.claw_dir, "system_prompt.md")
        File.write(path, data[:content])
        { success: true }.to_json
      end

      post "/api/tools/load" do
        content_type :json
        data = parse_json!
        require_field!(data, :name)
        registry = Claw.tool_registry
        halt 400, { error: "Tool registry not available" }.to_json unless registry

        msg = registry.load(data[:name])
        { success: true, message: msg }.to_json
      end

      post "/api/tools/unload" do
        content_type :json
        data = parse_json!
        require_field!(data, :name)
        registry = Claw.tool_registry
        halt 400, { error: "Tool registry not available" }.to_json unless registry

        msg = registry.unload(data[:name])
        { success: true, message: msg }.to_json
      end

      post "/api/snapshots" do
        content_type :json
        runtime = self.class.runtime
        halt 400, { error: "Runtime not available" }.to_json unless runtime

        id = runtime.snapshot!(label: "console")
        { success: true, id: id }.to_json
      end

      post "/api/snapshots/:id/rollback" do
        content_type :json
        halt 400, { error: "Invalid ID" }.to_json unless params[:id] =~ /\A\d+\z/
        runtime = self.class.runtime
        halt 400, { error: "Runtime not available" }.to_json unless runtime

        runtime.rollback!(params[:id].to_i)
        { success: true }.to_json
      end

      get "/api/snapshots" do
        content_type :json
        runtime = self.class.runtime
        return [].to_json unless runtime

        runtime.snapshots.map do |s|
          { id: s.id, label: s.label, timestamp: s.timestamp }
        end.to_json
      end
    end
  end
end
