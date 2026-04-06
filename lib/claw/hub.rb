# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Claw
  # Client for the ruby-claw-toolhub community tool repository.
  # Provides search and download of community-contributed tools.
  class Hub
    attr_reader :url

    def initialize(url:)
      @url = url.chomp("/")
    end

    # Search hub for tools matching a keyword.
    #
    # @param keyword [String]
    # @return [Array<Hash>] [{name:, description:, version:, url:}]
    def search(keyword)
      uri = URI("#{@url}/api/search?q=#{URI.encode_www_form_component(keyword)}")
      response = http_get(uri)
      return [] unless response

      results = JSON.parse(response, symbolize_names: true)
      results.map do |r|
        { name: r[:name], description: r[:description] || "",
          version: r[:version], url: r[:url] }
      end
    rescue JSON::ParserError
      []
    end

    # Download a tool file from the hub.
    #
    # @param name [String] tool name
    # @param target_dir [String] directory to write the file
    # @return [String] path to the downloaded file
    def download(name, target_dir:)
      uri = URI("#{@url}/api/tools/#{URI.encode_www_form_component(name)}")
      content = http_get(uri)
      raise "Tool '#{name}' not found on hub" unless content

      safe_name = File.basename(name).gsub(/[^a-zA-Z0-9_\-]/, "_")
      path = File.join(target_dir, "#{safe_name}.rb")
      File.write(path, content)
      path
    end

    private

    def http_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 10

      req = Net::HTTP::Get.new(uri)
      res = http.request(req)

      res.is_a?(Net::HTTPSuccess) ? res.body : nil
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError
      nil
    end
  end
end
