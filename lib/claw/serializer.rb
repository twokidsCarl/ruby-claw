# frozen_string_literal: true

require "json"
require "fileutils"

module Claw
  # Runtime state persistence — save/restore variables and method definitions.
  # Enables agent sessions to survive process restarts.
  module Serializer
    VALUES_FILE      = "values.json"
    DEFINITIONS_FILE = "definitions.rb"

    class << self
      # Save binding state to disk: local variable values + method definitions.
      #
      # @param bind [Binding] the binding whose variables to save
      # @param dir [String] directory to write state files into
      def save(bind, dir)
        FileUtils.mkdir_p(dir)
        save_values(bind, dir)
        save_definitions(bind, dir)
      end

      # Restore binding state from disk: set local variables + eval method definitions.
      #
      # @param bind [Binding] the binding to restore into
      # @param dir [String] directory to read state files from
      def restore(bind, dir)
        restore_values(bind, dir)
        restore_definitions(bind, dir)
      end

      private

      # --- Values ---

      def save_values(bind, dir)
        values = {}
        bind.local_variables.each do |name|
          val = bind.local_variable_get(name)
          next if name.to_s.start_with?("_")

          encoded = encode_value(val)
          values[name.to_s] = encoded if encoded
        end

        path = File.join(dir, VALUES_FILE)
        File.write(path, JSON.pretty_generate(values))
      end

      def restore_values(bind, dir)
        path = File.join(dir, VALUES_FILE)
        return unless File.exist?(path)

        values = JSON.parse(File.read(path))
        values.each do |name, entry|
          val = decode_value(entry)
          bind.local_variable_set(name.to_sym, val) unless val.nil?
        end
      rescue JSON::ParserError
        # Corrupted file — skip
      end

      # Encode a value for storage.
      # Strategy: try MarshalMd (human-readable Markdown), fall back to JSON, skip unserializable.
      def encode_value(val)
        # Try MarshalMd first for full Ruby fidelity + human readability
        md = MarshalMd.dump(val)
        { "type" => "marshal_md", "data" => md }
      rescue TypeError
        # MarshalMd failed — try JSON for simple types
        begin
          json = JSON.generate(val)
          { "type" => "json", "data" => json }
        rescue JSON::GeneratorError
          nil # Unserializable — skip
        end
      end

      # Decode a value from its stored representation.
      def decode_value(entry)
        case entry["type"]
        when "marshal_md"
          MarshalMd.load(entry["data"])
        when "marshal"
          # Backward compatibility: load old binary Marshal data
          Marshal.load([entry["data"]].pack("H*")) # rubocop:disable Security/MarshalLoad
        when "json"
          JSON.parse(entry["data"])
        end
      rescue => e
        $stderr.puts "Claw::Serializer decode error: #{e.message}" if $DEBUG
        nil
      end

      # --- Definitions ---

      def save_definitions(bind, dir)
        receiver = bind.receiver
        return unless receiver.instance_variable_defined?(:@__claw_definitions__)

        definitions = receiver.instance_variable_get(:@__claw_definitions__)
        return if definitions.nil? || definitions.empty?

        path = File.join(dir, DEFINITIONS_FILE)
        File.write(path, definitions.values.join("\n\n"))
      end

      def restore_definitions(bind, dir)
        path = File.join(dir, DEFINITIONS_FILE)
        return unless File.exist?(path)

        source = File.read(path)
        return if source.strip.empty?

        bind.eval(source)
      rescue Exception => e # rubocop:disable Lint/RescueException — SyntaxError is not a StandardError
        $stderr.puts "Claw::Serializer restore error: #{e.message}" if $DEBUG
      end
    end
  end
end
