# Scripts: Smart Contracts for Freechains

## Overview

Programs embedded in the genesis block that execute on
every new post.
They can reject or accept blocks, with side effects in
both cases.
Ideal for building sites, processing content, and enforcing
chain-specific rules.

## Status: Design

## Core Concept

- Smart contracts are **Lua scripts** stored as **blob
  files in the genesis commit tree** (not inline in the
  commit message)
- They run automatically on every new post
- Return value:
  - `false` → reject the block
  - `true` → accept the block
- Both paths can have **side effects** (generate files,
  update state, etc.)

## User-Submitted Scripts

- Users can post new scripts to the chain
- Any author can spend **1 like** to execute a
  user-submitted script (consent-based execution)
- The `why` field serves as the input/argument to the
  script

## Script API

- Scripts have **full chain read access**
- They can traverse the DAG, read previous posts, and
  aggregate state
- Read-only access to chain history — scripts cannot
  modify existing posts

## Determinism

- Scripts **should** be deterministic, but this **cannot
  be enforced** by the protocol
- If a script produces non-deterministic results, users
  may dislike it enough to remove it
- Best-effort: script authors are expected to write
  deterministic code

## Script Removal

- When a script is removed (via sufficient dislikes):
  - **Previously accepted posts survive** — they are not
    retroactively rejected
  - **Future posts stop being processed** by the removed
    script
- Removal is forward-only

## Scope

- Scripts handle **validation only**
- They accept/reject posts and run side effects
- **Reputation and consensus stay in the protocol** —
  scripts cannot override them

## Filesystem Layout

```
chains/<name>/out/    ← script side-effect output
```

## Use Case: UERJ Academic Site

- Chain for an academic department (UERJ)
- User drops a thesis file as a post
- The contract processes the thesis and generates relevant
  HTML pages
- Everything in Lua
- The chain becomes a self-publishing academic repository

## Design Questions

- [ ] Script sandboxing / resource limits
- [ ] How do side effects persist across nodes?
- [ ] Script versioning: can genesis scripts be updated?

## TODO

- [ ] Define full script API (available Lua functions,
  DAG traversal helpers)
- [ ] Prototype: genesis script that validates post format
- [ ] Prototype: UERJ thesis → HTML generator
- [ ] Define `chains/<name>/out/` structure
- [ ] Sandboxing strategy for untrusted scripts
