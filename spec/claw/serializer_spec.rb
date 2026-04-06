# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::Serializer do
  let(:dir) { Dir.mktmpdir("claw-serializer-") }

  after { FileUtils.rm_rf(dir) }

  def make_binding_with(**vars)
    b = Object.new.instance_eval { binding }
    vars.each { |k, v| b.local_variable_set(k, v) }
    b
  end

  describe ".save and .restore" do
    it "round-trips simple values" do
      bind = make_binding_with(x: 42, name: "hello")
      described_class.save(bind, dir)

      target = make_binding_with(x: nil, name: nil)
      described_class.restore(target, dir)

      expect(target.local_variable_get(:x)).to eq(42)
      expect(target.local_variable_get(:name)).to eq("hello")
    end

    it "round-trips arrays and hashes" do
      bind = make_binding_with(arr: [1, 2, 3], hsh: { a: 1 })
      described_class.save(bind, dir)

      target = make_binding_with(arr: nil, hsh: nil)
      described_class.restore(target, dir)

      expect(target.local_variable_get(:arr)).to eq([1, 2, 3])
      restored_hsh = target.local_variable_get(:hsh)
      expect(restored_hsh[:a] || restored_hsh["a"]).to eq(1)
    end

    it "skips underscore-prefixed variables" do
      bind = make_binding_with(_internal: "secret", public_val: "visible")
      described_class.save(bind, dir)

      values = JSON.parse(File.read(File.join(dir, "values.json")))
      expect(values).to have_key("public_val")
      expect(values).not_to have_key("_internal")
    end

    it "creates the directory if it doesn't exist" do
      nested = File.join(dir, "sub", "deep")
      bind = make_binding_with(x: 1)
      described_class.save(bind, nested)
      expect(File.exist?(File.join(nested, "values.json"))).to be true
    end
  end

  describe "restore_values edge cases" do
    it "does nothing when values file does not exist" do
      bind = make_binding_with(x: 99)
      described_class.restore(bind, dir)
      expect(bind.local_variable_get(:x)).to eq(99)
    end

    it "handles corrupted JSON gracefully" do
      File.write(File.join(dir, "values.json"), "not json{{{")
      bind = make_binding_with(x: 0)
      expect { described_class.restore(bind, dir) }.not_to raise_error
      expect(bind.local_variable_get(:x)).to eq(0)
    end
  end

  describe "encode/decode" do
    it "uses marshal_md format for standard objects" do
      bind = make_binding_with(val: { key: "test" })
      described_class.save(bind, dir)

      values = JSON.parse(File.read(File.join(dir, "values.json")))
      expect(values["val"]["type"]).to eq("marshal_md")
    end

    it "falls back to json when marshal_md fails" do
      allow(MarshalMd).to receive(:dump).and_raise(TypeError)

      bind = make_binding_with(val: [1, 2, 3])
      described_class.save(bind, dir)

      values = JSON.parse(File.read(File.join(dir, "values.json")))
      expect(values["val"]["type"]).to eq("json")
    end

    it "skips values when both marshal_md and json fail" do
      # Stub both serialization paths to fail for a specific value
      bad_val = Object.new
      original_dump = MarshalMd.method(:dump)
      allow(MarshalMd).to receive(:dump) do |val|
        raise TypeError if val.equal?(bad_val)
        original_dump.call(val)
      end

      bind = make_binding_with(bad: bad_val, good: 42)

      # bad_val.to_json will produce a string, but JSON.generate on Object raises
      # We need JSON.generate to also fail for bad_val
      original_generate = JSON.method(:generate)
      allow(JSON).to receive(:generate) do |val|
        raise JSON::GeneratorError, "unserializable" if val.equal?(bad_val)
        original_generate.call(val)
      end

      described_class.save(bind, dir)

      values = JSON.parse(File.read(File.join(dir, "values.json")))
      expect(values).not_to have_key("bad")
      expect(values).to have_key("good")
    end
  end

  describe "definitions save/restore" do
    it "saves and restores method definitions" do
      bind = make_binding_with()
      receiver = bind.receiver
      receiver.instance_variable_set(:@__claw_definitions__, {
        "greet" => "def greet(name); \"Hello, \#{name}\"; end"
      })
      described_class.save(bind, dir)

      target_bind = make_binding_with()
      described_class.restore(target_bind, dir)

      expect(target_bind.eval("greet('World')")).to eq("Hello, World")
    end

    it "skips when no definitions defined" do
      bind = make_binding_with()
      described_class.save(bind, dir)
      expect(File.exist?(File.join(dir, "definitions.rb"))).to be false
    end

    it "skips empty definitions" do
      bind = make_binding_with()
      bind.receiver.instance_variable_set(:@__claw_definitions__, {})
      described_class.save(bind, dir)
      expect(File.exist?(File.join(dir, "definitions.rb"))).to be false
    end

    it "handles restore of empty file" do
      File.write(File.join(dir, "definitions.rb"), "   ")
      bind = make_binding_with()
      expect { described_class.restore(bind, dir) }.not_to raise_error
    end

    it "handles restore of invalid Ruby code" do
      File.write(File.join(dir, "definitions.rb"), "def broken(")
      bind = make_binding_with()
      expect { described_class.restore(bind, dir) }.not_to raise_error
    end
  end
end
