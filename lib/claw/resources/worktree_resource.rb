# frozen_string_literal: true

require "open3"
require "fileutils"

module Claw
  module Resources
    # Git worktree-based filesystem resource for child agent isolation.
    # Creates a separate worktree from the parent repo so the child can
    # make changes without affecting the parent's working directory.
    class WorktreeResource
      include Claw::Resource

      attr_reader :path, :branch_name

      def initialize(parent_path:, branch_name:)
        @parent_path = File.expand_path(parent_path)
        @branch_name = branch_name
        @path = "#{@parent_path}-#{branch_name}"
        @cleaned_up = false

        create_worktree!
      end

      # Snapshot via git commit in the worktree.
      def snapshot!
        git("add", "-A")
        status = git("status", "--porcelain")
        if status.strip.empty?
          git("rev-parse", "HEAD").strip
        else
          git("commit", "-m", "snapshot #{Time.now.iso8601}", "--allow-empty-message")
          git("rev-parse", "HEAD").strip
        end
      end

      # Rollback to a previous commit in the worktree.
      def rollback!(token)
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

      # Summary of recent history.
      def to_md
        log = git("log", "--oneline", "-10")
        log.strip.empty? ? "(no commits)" : log.strip
      end

      # Merge from another worktree or filesystem resource.
      def merge_from!(other)
        other_path = other.respond_to?(:path) ? other.path : nil
        raise "Cannot determine path for merge source" unless other_path

        # Determine the branch name to merge
        other_branch = if other.is_a?(WorktreeResource)
          other.branch_name
        else
          # For FilesystemResource, get the current branch name
          other.instance_eval { git("rev-parse", "--abbrev-ref", "HEAD").strip }
        end

        remote_name = "merge_#{other.object_id}"
        git_try("remote", "add", remote_name, other_path)
        git("fetch", remote_name)
        git_try("merge", "#{remote_name}/#{other_branch}", "--no-edit", "-m", "merge from #{other.class.name}")
        git_try("remote", "remove", remote_name)
      end

      # Remove the worktree and delete the branch.
      def cleanup!
        return if @cleaned_up
        @cleaned_up = true

        # Remove worktree
        parent_git("worktree", "remove", @path, "--force")

        # Delete branch
        parent_git_try("branch", "-D", @branch_name)
      rescue => e
        # Best effort cleanup
        FileUtils.rm_rf(@path) if Dir.exist?(@path)
      end

      private

      def create_worktree!
        # Ensure parent has a commit (needed for worktree)
        parent_git_try("rev-parse", "HEAD")

        # Create worktree with a new branch
        parent_git("worktree", "add", @path, "-b", @branch_name)
      end

      def git(*args)
        cmd = ["git", "-C", @path] + args
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          raise "git #{args.first} failed in worktree: #{stderr.strip}"
        end
        stdout
      end

      def git_try(*args)
        git(*args)
      rescue RuntimeError
        # intentionally swallowed
      end

      def parent_git(*args)
        cmd = ["git", "-C", @parent_path] + args
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          raise "git #{args.first} failed in parent: #{stderr.strip}"
        end
        stdout
      end

      def parent_git_try(*args)
        parent_git(*args)
      rescue RuntimeError
        # intentionally swallowed
      end
    end
  end
end
