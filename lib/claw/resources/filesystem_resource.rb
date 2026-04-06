# frozen_string_literal: true

require "fileutils"
require "open3"

module Claw
  module Resources
    # Reversible resource for the .ruby-claw/ directory using git.
    # Each snapshot is a git commit; rollback checks out a previous commit.
    # Tracks the entire directory — no exclusions.
    class FilesystemResource
      include Claw::Resource

      attr_reader :path

      def initialize(path)
        @path = File.expand_path(path)
        init_git_repo unless git_initialized?
      end

      # Create a git commit capturing the current state. Returns the commit SHA.
      def snapshot!
        git("add", "-A")
        # Check if there are staged changes
        status = git("status", "--porcelain")
        if status.strip.empty?
          # Nothing to commit — return current HEAD
          git("rev-parse", "HEAD").strip
        else
          git("commit", "-m", "snapshot #{Time.now.iso8601}", "--allow-empty-message")
          git("rev-parse", "HEAD").strip
        end
      end

      # Restore directory to a previous commit.
      def rollback!(token)
        # Remove all tracked files, then restore from target commit.
        # Either step may have nothing to do (empty tree), so we allow failures.
        git_try("rm", "-rf", "--quiet", ".")
        git_try("checkout", token, "--", ".")
        git("clean", "-fd")
        git("reset", "HEAD")
      end

      # Git diff between two commits.
      def diff(token_a, token_b)
        result = git("diff", "--stat", token_a, token_b)
        result.strip.empty? ? "(no changes)" : result.strip
      end

      # Summary of recent git history.
      def to_md
        log = git("log", "--oneline", "-10")
        log.strip.empty? ? "(no commits)" : log.strip
      end

      # Merge changes from another FilesystemResource (e.g., child worktree).
      # Performs a git merge from the other's current HEAD.
      def merge_from!(other)
        other_path = other.respond_to?(:path) ? other.path : nil
        raise "Cannot determine path for merge source" unless other_path

        # Determine the branch name to merge
        other_branch = if other.is_a?(Resources::WorktreeResource)
          other.branch_name
        else
          other.instance_eval { git("rev-parse", "--abbrev-ref", "HEAD").strip }
        end

        remote_name = "child_#{object_id}"
        git_try("remote", "add", remote_name, other_path)
        git("fetch", remote_name)
        git_try("merge", "#{remote_name}/#{other_branch}", "--no-edit", "-m", "merge from child")
        git_try("remote", "remove", remote_name)
      end

      private

      def git_initialized?
        File.directory?(File.join(@path, ".git"))
      end

      def init_git_repo
        FileUtils.mkdir_p(@path)
        git("init")
        # Create initial empty commit so HEAD exists
        git("commit", "--allow-empty", "-m", "init")
      end

      def git(*args)
        cmd = ["git", "-C", @path] + args
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          raise "git #{args.first} failed: #{stderr.strip}"
        end
        stdout
      end

      # Like git() but ignores failures (for operations that may have nothing to do).
      def git_try(*args)
        git(*args)
      rescue RuntimeError
        # intentionally swallowed
      end
    end
  end
end
