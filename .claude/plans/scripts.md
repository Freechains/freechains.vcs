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

- Smart contracts are **Lua scripts** stored in the genesis
  block
- They run automatically on every new post
- Return value:
  - `false` → reject the block
  - `true` → accept the block
- Both paths can have **side effects** (generate files,
  update state, etc.)

## User-Submitted Scripts

- Users can post new scripts to the chain
- Acceptance requires **likes from the nodes that will
  execute them** (consent-based execution)
- The `why` field serves as the input/argument to the
  script

## Filesystem Layout

```
.freechains/scripts/    ← script storage
```

## Use Case: UERJ Academic Site

- Chain for an academic department (UERJ)
- User drops a thesis file as a post
- The contract processes the thesis and generates relevant
  HTML pages
- Everything in Lua
- The chain becomes a self-publishing academic repository

## Design Questions

- [ ] How are genesis scripts specified? (inline vs ref)
- [ ] Script sandboxing / resource limits
- [ ] How do side effects persist across nodes?
- [ ] Determinism: must all nodes produce the same side
  effects?
- [ ] Script versioning: can genesis scripts be updated?
- [ ] How does the like-based consent work for
  user-submitted scripts?
- [ ] What Lua APIs are available to scripts?
- [ ] How do scripts access post content (payload, headers,
  metadata)?

## TODO

- [ ] Define script API (input/output contract)
- [ ] Define consent mechanism for user-submitted scripts
- [ ] Prototype: genesis script that validates post format
- [ ] Prototype: UERJ thesis → HTML generator
- [ ] Define `.freechains/scripts/` structure
- [ ] Sandboxing strategy for untrusted scripts
