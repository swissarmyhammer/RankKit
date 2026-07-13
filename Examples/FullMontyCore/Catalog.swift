// `FullMonty`'s fixture catalog (plan.md §3a): ~50 developer command-line
// tools, each an id plus a one-line description of what it does — the same
// "id + text" shape as `Searcher.swift`'s own header-comment example
// (`grep`/`glob`/`watch`), expanded here into the living proof of that
// documentation.
//
// New to RankKit — no source file to port: neither CodeContextKit nor
// FoundationModelsMetadataRegistry ships a catalog this shape (plan.md §3a
// "`Examples/FullMonty` is the living proof"). Modeled structurally on
// FoundationModelsMetadataRegistry's `Examples/ExamplesSupport`'s
// `baseGitCommands` fixture, generalized from five git subcommands to a
// broader command-line surface so the demo has enough breadth to show BM25 +
// trigram fusion doing real work.

import RankKit

/// A fixture catalog of ~50 common command-line tools, each an id and one-line description.
///
/// Every `SearchItem`'s `summary` defaults to its `text` — this catalog has
/// nothing shorter to offer the selection prefix.
public let toolCatalog: [SearchItem] = [
    SearchItem(id: "grep", text: "Search file contents with regular expressions"),
    SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
    SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    SearchItem(id: "commit", text: "Record staged changes as a new snapshot in the repository history"),
    SearchItem(id: "push", text: "Upload local branch history to a remote server"),
    SearchItem(id: "pull", text: "Download and merge remote branch history"),
    SearchItem(id: "fetch", text: "Download remote branch history without merging"),
    SearchItem(id: "branch", text: "List, create, or delete lines of independent development"),
    SearchItem(id: "checkout", text: "Switch the working tree to a different branch or commit"),
    SearchItem(id: "stash", text: "Temporarily set aside uncommitted edits to switch tasks"),
    SearchItem(id: "diff", text: "Show changes between commits, the working tree, and the index"),
    SearchItem(id: "log", text: "Show the commit history for the current branch"),
    SearchItem(id: "status", text: "Report the current state of the working tree"),
    SearchItem(id: "merge", text: "Join two or more development histories together"),
    SearchItem(id: "rebase", text: "Reapply commits on top of another base tip"),
    SearchItem(id: "cherry-pick", text: "Apply the changes introduced by an existing commit"),
    SearchItem(id: "tag", text: "Create, list, or delete a reference to a specific commit"),
    SearchItem(id: "clone", text: "Copy a remote repository into a new local directory"),
    SearchItem(id: "reset", text: "Move the current branch tip and optionally the working tree"),
    SearchItem(id: "revert", text: "Create a new commit that undoes an existing commit"),
    SearchItem(id: "blame", text: "Show what revision and author last modified each line of a file"),
    SearchItem(id: "bisect", text: "Binary search commit history to find a regression"),
    SearchItem(id: "remote", text: "Manage the set of tracked remote repositories"),
    SearchItem(id: "submodule", text: "Initialize, update, or inspect nested repositories"),
    SearchItem(id: "worktree", text: "Manage multiple working trees attached to the same repository"),
    SearchItem(id: "cat", text: "Print the contents of a file to standard output"),
    SearchItem(id: "ls", text: "List the files and directories in a path"),
    SearchItem(id: "mkdir", text: "Create a new directory"),
    SearchItem(id: "rmdir", text: "Remove an empty directory"),
    SearchItem(id: "rm", text: "Delete files or directories"),
    SearchItem(id: "cp", text: "Copy files or directories to a new location"),
    SearchItem(id: "mv", text: "Move or rename files and directories"),
    SearchItem(id: "chmod", text: "Change a file's read, write, and execute permissions"),
    SearchItem(id: "chown", text: "Change the owning user and group of a file"),
    SearchItem(id: "findfiles", text: "Search a directory tree for files matching criteria"),
    SearchItem(id: "sed", text: "Apply a stream text transformation to a file's contents"),
    SearchItem(id: "awk", text: "Extract and transform fields from structured text"),
    SearchItem(id: "curl", text: "Transfer data to or from a URL over HTTP and other protocols"),
    SearchItem(id: "wget", text: "Download a file from a URL"),
    SearchItem(id: "ssh", text: "Open a secure remote shell session on another machine"),
    SearchItem(id: "scp", text: "Securely copy files between hosts over SSH"),
    SearchItem(id: "tar", text: "Bundle a directory tree into a single archive file"),
    SearchItem(id: "gzip", text: "Compress a file using the DEFLATE algorithm"),
    SearchItem(id: "ps", text: "List the processes currently running on the system"),
    SearchItem(id: "kill", text: "Send a signal to terminate or interrupt a running process"),
    SearchItem(id: "top", text: "Show a live, sorted view of process resource usage"),
    SearchItem(id: "df", text: "Report free and used disk space by filesystem"),
    SearchItem(id: "du", text: "Report disk usage for files and directories"),
    SearchItem(id: "ping", text: "Send ICMP echo requests to test reachability of a host"),
    SearchItem(id: "netstat", text: "List active network connections and listening ports"),
]

/// Demo queries that overlap with catalog items to show keyword-only retrieval working well.
///
/// The handful of queries `FullMonty` demonstrates the catalog with (plan.md
/// §3a "a handful of queries"). Each is worded to overlap heavily — in
/// wording, not just meaning — with exactly one catalog item's `text`, so
/// the keyword-only (`--no-model`) path already surfaces a clear top match
/// without needing the cosine signal or a selection model.
public let demoQueries: [String] = [
    "search file contents for a pattern using a regular expression",
    "record my staged changes as a new commit",
    "how do I list or delete a branch",
    "temporarily set aside my uncommitted changes to switch tasks",
]
