# MaxxBar

## Git worktrees

Create worktrees in `.worktrees/` inside this folder (ignored by git), never as sibling folders next to MaxxBar:

```sh
git worktree add .worktrees/<name> -b <branch> origin/main
```

This folder syncs to iCloud, so before building in a worktree, link its `.build` out of iCloud, with its own folder per worktree:

```sh
mkdir -p ~/Library/Developer/MaxxBar-build/<name>/.build
ln -s ~/Library/Developer/MaxxBar-build/<name>/.build .worktrees/<name>/.build
```

When the branch's pull request has merged and the worktree is clean, remove it:

```sh
git worktree remove .worktrees/<name>
git worktree prune
```
