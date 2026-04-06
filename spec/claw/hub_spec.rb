# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Hub do
  let(:hub_url) { "https://toolhub.example.com" }
  let(:hub) { described_class.new(url: hub_url) }

  describe "#search" do
    it "returns matching tools from the hub" do
      stub_request(:get, "https://toolhub.example.com/api/search?q=format")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { name: "format_csv", description: "Format data as CSV", version: "1.0" },
            { name: "format_json", description: "Pretty-print JSON", version: "0.2" }
          ])
        )

      results = hub.search("format")
      expect(results.size).to eq(2)
      expect(results.first[:name]).to eq("format_csv")
    end

    it "returns empty array on HTTP error" do
      stub_request(:get, "https://toolhub.example.com/api/search?q=test")
        .to_return(status: 500)

      expect(hub.search("test")).to eq([])
    end

    it "returns empty array on network error" do
      stub_request(:get, "https://toolhub.example.com/api/search?q=test")
        .to_timeout

      expect(hub.search("test")).to eq([])
    end

    it "handles malformed JSON" do
      stub_request(:get, "https://toolhub.example.com/api/search?q=test")
        .to_return(status: 200, body: "not json")

      expect(hub.search("test")).to eq([])
    end
  end

  describe "#download" do
    let(:target_dir) { Dir.mktmpdir("claw-hub-dl-") }
    after { FileUtils.rm_rf(target_dir) }

    it "downloads a tool file to the target directory" do
      tool_code = <<~RUBY
        class RemoteTool
          include Claw::Tool
          tool_name   "remote_tool"
          description "A tool from the hub"
          def call; "hello"; end
        end
      RUBY

      stub_request(:get, "https://toolhub.example.com/api/tools/remote_tool")
        .to_return(status: 200, body: tool_code)

      path = hub.download("remote_tool", target_dir: target_dir)
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to include("remote_tool")
    end

    it "raises on 404" do
      stub_request(:get, "https://toolhub.example.com/api/tools/missing")
        .to_return(status: 404)

      expect { hub.download("missing", target_dir: target_dir) }
        .to raise_error(RuntimeError, /not found/)
    end
  end
end
