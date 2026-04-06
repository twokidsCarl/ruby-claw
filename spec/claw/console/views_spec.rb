# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "rack/test"

RSpec.describe "Console Views" do
  include Rack::Test::Methods

  let(:claw_dir) { Dir.mktmpdir("claw-views-") }

  before do
    FileUtils.mkdir_p(File.join(claw_dir, "log"))
    FileUtils.mkdir_p(File.join(claw_dir, "traces"))
    File.write(File.join(claw_dir, "system_prompt.md"), "# Test Prompt")

    Claw::Console::Server.setup(claw_dir: claw_dir)
  end

  after { FileUtils.rm_rf(claw_dir) }

  def app
    Claw::Console::Server
  end

  %w[/ /prompt /monitor /traces /memory /tools /snapshots /experiments].each do |path|
    describe "GET #{path}" do
      it "renders successfully" do
        get path
        expect(last_response).to be_ok
        expect(last_response.body).to include("<!DOCTYPE html>")
        expect(last_response.body).to include("claw")
      end
    end
  end

  describe "GET /" do
    it "contains dashboard cards" do
      get "/"
      expect(last_response.body).to include("stat-version")
      expect(last_response.body).to include("stat-tools")
    end
  end

  describe "GET /prompt" do
    it "contains prompt editor" do
      get "/prompt"
      expect(last_response.body).to include("prompt-template")
      expect(last_response.body).to include("save-prompt")
    end
  end

  describe "GET /monitor" do
    it "contains event stream container" do
      get "/monitor"
      expect(last_response.body).to include("event-stream")
      expect(last_response.body).to include("event-filter")
    end
  end

  describe "GET /traces" do
    it "contains trace layout" do
      get "/traces"
      expect(last_response.body).to include("trace-list")
      expect(last_response.body).to include("trace-detail")
    end
  end

  describe "static assets" do
    it "serves style.css" do
      get "/style.css"
      expect(last_response).to be_ok
      expect(last_response.content_type).to include("text/css")
    end

    it "serves app.js" do
      get "/app.js"
      expect(last_response).to be_ok
      expect(last_response.content_type).to include("javascript")
    end
  end
end
