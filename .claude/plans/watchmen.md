# Watchmen: Filesystem Change Detection & Auto-Commit

## Overview

Watch for filesystem changes and automatically commit them
to git.
This enables real-time tracking of file edits in chain
directories.

## Status: Research

## Approaches

### 1. `inotifywait` (Linux)

- Package: `inotify-tools`
- Events: `modify`, `create`, `delete`, `close_write`
- Recursive watching with `-m -r`

```bash
inotifywait -m -r -e close_write ./src |
while read dir event file; do
    git add "$dir$file"
    git commit -m "auto: save $file"
done
```

### 2. `fswatch` (macOS)

```bash
fswatch -o ./src | xargs -n1 -I{} sh -c \
    'git add -A && git commit -m "auto-commit"'
```

### 3. `watchman` (Cross-platform, by Meta)

- Daemon-based, efficient for large trees
- JSON API

### 4. `entr` (Debounced)

- Avoids commit spam on rapid saves
- `-p` waits for first change before running

```bash
find ./src -name "*.atmos" | entr -p sh -c \
    'git add -A && git commit -m "wip"'
```

## Git Hooks (Complementary)

Hooks live in `.git/hooks/` and run on git events:

| Hook          | When                          |
|---------------|-------------------------------|
| `pre-commit`  | Before a commit is created    |
| `post-commit` | After a commit is created     |
| `pre-push`    | Before pushing                |

Hooks validate/transform; watchers detect changes.
The two can be combined.

## Makefile Integration

```makefile
watch:
    inotifywait -m -r -e close_write ./src | \
    while read dir event file; do \
        git add -A && git commit -m "wip: $$file"; \
    done
```

## TODO

- [ ] Choose watcher tool for Freechains
- [ ] Define which directories/files to watch
- [ ] Define commit message format
- [ ] Handle debouncing / rapid saves
- [ ] Integrate with chain structure
- [ ] Test on Linux and macOS
