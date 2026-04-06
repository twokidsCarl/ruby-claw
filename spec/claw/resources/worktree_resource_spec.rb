# frozen_string_literal: true

require "tmpdir"

RSpec.describe Claw::Resources::WorktreeResource do
  let(:parent_dir) { Dir.mktmpdir("claw-wt-parent-") }

  before do
    # Initialize a git repo in parent_dir with a file
    system("git", "-C", parent_dir, "init", out: File::NULL, err: File::NULL)
    system("git", "-C", parent_dir, "config", "user.email", "test@test.com")
    system("git", "-C", parent_dir, "config", "user.name", "Test")
    File.write(File.join(parent_dir, "test.txt"), "hello")
    system("git", "-C", parent_dir, "add", "-A", out: File::NULL, err: File::NULL)
    system("git", "-C", parent_dir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
  end

  after do
    # Cleanup worktree path if it exists
    wt_path = "#{parent_dir}-test-branch"
    if Dir.exist?(wt_path)
      system("git", "-C", parent_dir, "worktree", "remove", wt_path, "--force", out: File::NULL, err: File::NULL)
      FileUtils.rm_rf(wt_path) if Dir.exist?(wt_path)
    end
    system("git", "-C", parent_dir, "branch", "-D", "test-branch", out: File::NULL, err: File::NULL)
    FileUtils.rm_rf(parent_dir)
  end

  it "creates a worktree directory" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )
    expect(Dir.exist?(wt.path)).to be true
    expect(File.exist?(File.join(wt.path, "test.txt"))).to be true
    wt.cleanup!
  end

  it "snapshots and rollbacks" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )

    # Initial snapshot
    snap1 = wt.snapshot!
    expect(snap1).to be_a(String)
    expect(snap1.size).to be >= 7

    # Modify and snapshot
    File.write(File.join(wt.path, "new.txt"), "world")
    snap2 = wt.snapshot!
    expect(snap2).not_to eq(snap1)

    # Rollback
    wt.rollback!(snap1)
    expect(File.exist?(File.join(wt.path, "new.txt"))).to be false

    wt.cleanup!
  end

  it "provides diff between snapshots" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )

    snap1 = wt.snapshot!
    File.write(File.join(wt.path, "another.txt"), "data")
    snap2 = wt.snapshot!

    diff = wt.diff(snap1, snap2)
    expect(diff).to include("another.txt")

    wt.cleanup!
  end

  it "provides to_md" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )

    md = wt.to_md
    expect(md).to include("init")

    wt.cleanup!
  end

  it "cleans up worktree and branch" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )
    wt_path = wt.path

    wt.cleanup!
    expect(Dir.exist?(wt_path)).to be false
  end

  it "includes Claw::Resource" do
    wt = Claw::Resources::WorktreeResource.new(
      parent_path: parent_dir,
      branch_name: "test-branch"
    )
    expect(wt).to be_a(Claw::Resource)
    wt.cleanup!
  end
end
