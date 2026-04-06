# frozen_string_literal: true

module Claw
  # Interface for reversible resources managed by Claw::Runtime.
  # All resources that participate in snapshot/rollback must include this module
  # and implement the required methods.
  module Resource
    # Capture current state. Returns an opaque token for later rollback.
    def snapshot!
      raise NotImplementedError, "#{self.class}#snapshot! not implemented"
    end

    # Restore state to a previous snapshot token.
    # Implementations must guarantee success — partial rollback is not acceptable.
    def rollback!(token)
      raise NotImplementedError, "#{self.class}#rollback! not implemented"
    end

    # Compare two snapshot tokens. Returns a human-readable diff string.
    def diff(token_a, token_b)
      raise NotImplementedError, "#{self.class}#diff not implemented"
    end

    # Render current state as Markdown for human/LLM consumption.
    def to_md
      raise NotImplementedError, "#{self.class}#to_md not implemented"
    end

    # Merge changes from another resource instance (e.g., child → parent).
    # Used by V8 Multi-Agent to selectively merge child results back.
    def merge_from!(other)
      raise NotImplementedError, "#{self.class}#merge_from! not implemented"
    end
  end
end
