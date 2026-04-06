# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "rack/test"

RSpec.describe Claw::Console::Server do
  include Rack::Test::Methods

  let(:claw_dir) { Dir.mktmpdir("claw-console-") }

  before do
    FileUtils.mkdir_p(File.join(claw_dir, "log"))
    FileUtils.mkdir_p(File.join(claw_dir, "traces"))
    File.write(File.join(claw_dir, "system_prompt.md"), "# Test Prompt")

    described_class.setup(claw_dir: claw_dir)
  end

  after { FileUtils.rm_rf(claw_dir) }

  def app
    described_class
  end

  describe "GET /api/status" do
    it "returns JSON with version" do
      get "/api/status"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data["version"]).to eq(Claw::VERSION)
    end
  end

  describe "GET /api/traces" do
    it "returns empty array when no traces" do
      get "/api/traces"
      expect(last_response).to be_ok
      expect(JSON.parse(last_response.body)).to eq([])
    end

    it "returns trace files" do
      File.write(File.join(claw_dir, "traces", "20260405_010000.md"), "# Trace")
      get "/api/traces"
      data = JSON.parse(last_response.body)
      expect(data.size).to eq(1)
      expect(data.first["id"]).to eq("20260405_010000")
    end
  end

  describe "GET /api/traces/:id" do
    it "returns trace content" do
      File.write(File.join(claw_dir, "traces", "test_trace.md"), "# Trace Content")
      get "/api/traces/test_trace"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data["content"]).to include("Trace Content")
    end

    it "returns 404 for missing trace" do
      get "/api/traces/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /api/prompt" do
    it "returns system prompt and sections" do
      get "/api/prompt"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data["template"]).to include("Test Prompt")
    end
  end

  describe "POST /api/prompt" do
    it "updates the system prompt file" do
      post "/api/prompt", JSON.generate({ content: "# Updated" }), "CONTENT_TYPE" => "application/json"
      expect(last_response).to be_ok
      expect(File.read(File.join(claw_dir, "system_prompt.md"))).to eq("# Updated")
    end
  end

  describe "GET /api/tools" do
    it "returns tool listings" do
      get "/api/tools"
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data).to have_key("core")
      expect(data).to have_key("project")
    end
  end

  describe "GET /api/snapshots" do
    it "returns empty when no runtime" do
      get "/api/snapshots"
      expect(last_response).to be_ok
    end
  end
end
