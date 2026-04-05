# frozen_string_literal: true

require "spec_helper"

RSpec.describe Claw::Resource do
  let(:klass) do
    Class.new do
      include Claw::Resource
    end
  end

  it "raises NotImplementedError for snapshot!" do
    expect { klass.new.snapshot! }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for rollback!" do
    expect { klass.new.rollback!(:token) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for diff" do
    expect { klass.new.diff(:a, :b) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for to_md" do
    expect { klass.new.to_md }.to raise_error(NotImplementedError)
  end
end
