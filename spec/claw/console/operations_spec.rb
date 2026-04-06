# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "rack/test"

RSpec.describe "Console Operations" do
  include Rack::Test::Methods

  let(:claw_dir) { Dir.mktmpdir("claw-ops-") }
  let(:memory) { Claw::Memory.new }
  let(:runtime) { Claw::Runtime.new }

  before do
    FileUtils.mkdir_p(File.join(claw_dir, "log"))
    FileUtils.mkdir_p(File.join(claw_dir, "traces"))
    FileUtils.mkdir_p(File.join(claw_dir, "tools"))
    File.write(File.join(claw_dir, "system_prompt.md"), "# Original Prompt")

    Claw::Console::Server.setup(
      claw_dir: claw_dir,
      runtime: runtime,
      memory: memory,
      port: 4567
    )
  end

  after { FileUtils.rm_rf(claw_dir) }

  def app
    Claw::Console::Server
  end

  # --- Memory CRUD ---

  describe "POST /api/memory" do
    it "adds a memory entry" do
      post "/api/memory", JSON.generate({ content: "test fact" }), "CONTENT_TYPE" => "application/json"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data["success"]).to be true
      expect(data["entry"]["content"]).to eq("test fact")
    end

    it "returns 400 when memory is nil" do
      Claw::Console::Server.memory_instance = nil
      post "/api/memory", JSON.generate({ content: "x" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end
  end

  describe "DELETE /api/memory/:id" do
    it "removes a memory entry" do
      entry = memory.remember("to forget")
      delete "/api/memory/#{entry[:id]}"
      expect(last_response).to be_ok
      expect(memory.long_term.map { |m| m[:id] }).not_to include(entry[:id])
    end
  end

  describe "GET /api/memory" do
    it "returns stored memories" do
      memory.remember("alpha")
      memory.remember("beta")
      get "/api/memory"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data.size).to be >= 2
      contents = data.map { |m| m["content"] }
      expect(contents).to include("alpha", "beta")
    end

    it "returns empty when no memory instance" do
      Claw::Console::Server.memory_instance = nil
      get "/api/memory"
      expect(last_response).to be_ok
      expect(JSON.parse(last_response.body)).to eq([])
    end
  end

  # --- Prompt Management ---

  describe "POST /api/prompt" do
    it "updates the system prompt" do
      post "/api/prompt", JSON.generate({ content: "# New Prompt" }), "CONTENT_TYPE" => "application/json"
      expect(last_response).to be_ok
      expect(File.read(File.join(claw_dir, "system_prompt.md"))).to eq("# New Prompt")
    end
  end

  describe "GET /api/prompt/sections" do
    it "returns dynamic sections array" do
      get "/api/prompt/sections"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data).to be_an(Array)
    end
  end

  # --- Tool Management ---

  describe "POST /api/tools/load" do
    it "returns 400 when registry not available" do
      allow(Claw).to receive(:tool_registry).and_return(nil)
      post "/api/tools/load", JSON.generate({ name: "foo" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end
  end

  describe "POST /api/tools/unload" do
    it "returns 400 when registry not available" do
      allow(Claw).to receive(:tool_registry).and_return(nil)
      post "/api/tools/unload", JSON.generate({ name: "foo" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end
  end

  # --- Snapshot Management ---

  describe "POST /api/snapshots" do
    it "creates a new snapshot" do
      binding_obj = Object.new.instance_eval { binding }
      runtime.register("binding", Claw::Resources::BindingResource.new(binding_obj))
      post "/api/snapshots", "", "CONTENT_TYPE" => "application/json"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data["success"]).to be true
      expect(data["id"]).to be_a(Integer)
    end

    it "returns 400 when no runtime" do
      Claw::Console::Server.runtime = nil
      post "/api/snapshots", "", "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end
  end

  describe "POST /api/snapshots/:id/rollback" do
    it "rolls back to a snapshot" do
      binding_obj = Object.new.instance_eval { binding }
      runtime.register("binding", Claw::Resources::BindingResource.new(binding_obj))
      runtime.snapshot!(label: "test")
      post "/api/snapshots/1/rollback", "", "CONTENT_TYPE" => "application/json"
      expect(last_response).to be_ok
    end

    it "returns 400 when no runtime" do
      Claw::Console::Server.runtime = nil
      post "/api/snapshots/1/rollback", "", "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end
  end

  describe "GET /api/snapshots" do
    it "returns snapshot list with runtime" do
      binding_obj = Object.new.instance_eval { binding }
      runtime.register("binding", Claw::Resources::BindingResource.new(binding_obj))
      runtime.snapshot!(label: "s1")
      get "/api/snapshots"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data.size).to eq(1)
      expect(data.first["label"]).to eq("s1")
    end
  end
end
