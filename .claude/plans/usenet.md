# Usenet: Email/Newsgroup Clients as Freechains GUI

## Overview

Use existing email/newsgroup clients as a GUI frontend for
Freechains by exposing chain messages in standard mailbox
formats (MH).
Message format is identical to email (RFC 2822), and
threading works natively via `Message-ID`, `In-Reply-To`,
`References` headers.
Git is the transport layer that makes email, Usenet, and
Freechains interoperate — it natively handles
content-addressed, signed, immutable objects.

## Status: Research

## Protocols

- **NNTP** — newsgroup protocol (port 119, 563 with SSL)
- Newsgroup hierarchy: `comp.lang.lua`, `rec.sport.*`, etc.
- Message format identical to email (RFC 2822) with extra
  headers: `Newsgroups:`, `Message-ID:`, `References:`,
  `In-Reply-To:`

## Topology Comparison

| Property  | Email (MH)    | Usenet    | Freechains  |
|-----------|---------------|-----------|-------------|
| Topology  | 1:1           | 1:many    | many:many   |
| Unit      | message       | article   | block       |
| Address   | mailbox       | newsgroup | chain       |
| Transport | SMTP/git push | NNTP/git  | p2p/git     |
| Identity  | optional GPG  | none      | mandatory   |
| Expiry    | keep          | expires   | never       |

## Mailbox Formats

| Format      | Structure                    | Locking  | Concurrency | Shell Use     |
|-------------|------------------------------|----------|-------------|---------------|
| **mbox**    | 1 file per folder            | required | poor        | hard          |
| **MH**      | 1 numbered file per message  | none     | ok          | very easy     |
| **Maildir** | 1 file per msg, cur/new/tmp  | none     | excellent   | easy          |

### MH (Recommended for Freechains)

- One numbered file per message in a plain directory
- Easy shell manipulation: `ls inbox/`, `cat inbox/42`
- State in `.mh_sequences` (can desync)
- Traditional newsgroup spool (INN) uses MH-like format
- Git-friendly by design — no conversion needed
- For local use without concurrent delivery, MH is as
  good as Maildir
- Usenet articles are already MH-compatible (RFC 2822)

### Maildir

- Atomic delivery via `tmp/ → new/`, flags in filename
- Advantages over MH are irrelevant for local newsgroups
  (no concurrent delivery)

### MH Spec on Non-Integer Filenames

From the nmh `mh-folders` man page:
> "All files that are not positive integers must be ignored
> by a MH-compatible implementation."

Non-integer files (e.g., `.hash-map`, sidecars) are silently
ignored — not rejected.
The directory can contain them safely.

## GPG Signing

### Double Signing

- Email signature covers email bytes (MIME body)
- Git commit signature covers the commit object
- These can never be the same bytes — unification is
  impossible
- **Resolution**: same GPG key signs both artifacts
  independently; identity link is cryptographic (same key
  fingerprint)

### Git Bundle as Transport

- Preserves exact commit hashes and signatures
- Transport-agnostic: USB, email, HTTP, sneakernet
- Best option when exact commit identity must be preserved

## The Local Numbering Problem

### Core Issue

MH numbering is **purely local and sequential**.
Article `47` locally may be `312` on another machine.
You cannot `git push` two MH newsgroup folders directly
without filename collisions.

### How Traditional NNTP Clients Solve It

Leafnode and others maintain a `Message-ID → local number`
mapping table.
The local number is disposable; the Message-ID is canonical.

### Message-ID vs Content Address

- Usenet `Message-ID` is server-minted, not content-derived
  — forgeable
- Git blob SHA = hash of content — same model as Freechains
- In this architecture, Message-ID becomes metadata;
  git/Freechains hash is authoritative

## Timestamp + Hash Numbering Scheme

### Requirements

- Monotonically increasing (temporal order for
  `next`/`prev`/`scan`)
- Globally deterministic (same article → same integer on
  any machine)
- Fits in Claws Mail's `gint` (32-bit signed,
  max **2,147,483,647**)
- Collision-resistant

### Critical Constraint: Claws Uses 32-bit `gint`

From Claws Mail source (`procmsg.h`, `imap.h`):
- `msginfo->msgnum` is typed as `gint` (32-bit signed)
- **Hard maximum: 2,147,483,647 (10 digits)**
- Plain Unix timestamp (~1.7B) nearly exhausts this with
  zero room for hash suffix

### Epoch

**Jan 1, 2025** = Unix timestamp `1735689600`

Using a recent epoch reduces digits needed for the time
component, freeing space for hash digits.

### Recommended: Days + 5 Hash Digits

```
msgnum = days_since_2025 * 100000 + hash5
```

| Property      | Value              |
|---------------|--------------------|
| Time digits   | 5                  |
| Hash digits   | 5                  |
| Total         | 10                 |
| Coverage      | 50 years (to 2075) |
| Slots/day     | 100,000            |
| Max value     | 1,826,281,737      |
| Collision risk | negligible        |

```bash
EPOCH=1735689600
days=$(( ($(date +%s) - EPOCH) / 86400 ))
hash5=$(echo -n "$message_id" | sha256sum \
    | tr -dc '0-9' | cut -c1-5)
msgnum=$(( days * 100000 + hash5 ))
```

### Alternative: Hours + 3 Hash Digits

```
msgnum = hours_since_2025 * 1000 + hash3
```

| Property      | Value                        |
|---------------|------------------------------|
| Slots/hour    | 1,000                        |
| Max value     | 437,861,700                  |
| Collision risk | ~0.05% at 1 article/min     |

### Properties of the Scheme

- **Monotonically increasing**: temporal order preserved,
  Claws navigation works correctly
- **Globally deterministic**: same article on two machines
  → same integer
- **Conflict-free git merges**: same filename = same content
  = git deduplicates silently
- **No sidecar map required**: filename encodes both order
  and identity
- Day-level granularity is sufficient for newsreader ordering

## Recommended Client: Claws Mail

- C/GTK, lightweight, active, ~40 plugins
- Native MH support; mbox via plugin
- Native NNTP support (newsgroups)
- Built-in RSS/Atom reader
- Plugins in **C** (`.so`), **Python**, **Perl**
- Extensible without recompiling
- 32-bit `gint` is the binding constraint for message
  numbers
- **Best client for this architecture**

### Claws Mail vs Sylpheed

| Aspect           | Sylpheed          | Claws Mail           |
|------------------|-------------------|----------------------|
| Last stable      | 3.7.0 (jan 2018)  | 4.3.1 (feb 2025)    |
| Status           | minimal maint.    | active community     |
| Plugins          | ~3                | ~40                  |
| Scripting        | no                | Python, Perl         |
| NNTP             | yes               | yes                  |

### Newsreader Storage Format Matrix

| Client        | Storage           | Std Maildir | MH      |
|---------------|-------------------|-------------|---------|
| Claws Mail    | MH (native)       | no          | yes     |
| Thunderbird   | mbox/maildir-lite | no (lite)   | no      |
| NeoMutt       | NNTP header cache | no          | patch   |
| Gnus (Emacs)  | nnmaildir/nnml    | yes         | no      |
| Pan           | own binary cache  | no          | no      |
| slrn          | NNTP spool        | symlink     | no      |
| tin           | own spool         | no          | no      |

## Leafnode as Bridge

Leafnode is a local NNTP server for single-user use:
- Fetches upstream articles, serves `localhost:119`
- Stores articles as flat files on disk
- Solves `Message-ID → local number` translation internally
- Claws connects as normal NNTP server, unaware of backend

Target architecture: replace upstream (real Usenet) with
a git peer.

```
Claws Mail → localhost:119 → Leafnode → git/Freechains
```

## inotify Hook (Auto-commit on Send)

```bash
inotifywait -m ~/Mail/sent -e close_write |
while read dir event file; do
    cd ~/Mail
    git add "sent/$file"
    SUBJECT=$(formail -x Subject < "sent/$file")
    git commit -S -m "$SUBJECT"
done
```

## Full Architecture

### Folder Structure

```
~/Mail/
  sent/                    ← email out (MH, git-tracked)
  received/                ← email in
  news/
    comp.lang.lua/
      1735000123456        ← days*100000+hash5
      1735000287341
      .mh_sequences        ← MH sidecar, ignored
```

### Sync Layers

```
Freechains / git       ← canonical, content-addressed, signed
      ↓
  sync script          ← deduplicates by hash, assigns msgnum
      ↓
  MH folders           ← local client view, fully rebuildable
      ↓
  Claws Mail           ← reads MH normally, unaware of hashes
```

MH numbers are a **rebuildable local cache**, not the
canonical store.

## Convergence with Freechains

Email, Usenet articles, and Freechains blocks are all the
same thing: a **signed, addressed, propagated unit of
communication**.
They differ only in execution quality.

| Property           | Email     | Usenet     | Freechains | This arch    |
|--------------------|-----------|------------|------------|--------------|
| Content addressing | no        | no         | yes        | yes (hash)   |
| Mandatory signing  | no        | no         | yes        | yes (GPG)    |
| Immutability       | partial   | no (cancel)| yes        | yes (git)    |
| Spam resistance    | no        | no (kill)  | yes        | partial      |
| Decentralized      | federated | federated  | p2p        | p2p via git  |

The MH+git architecture is essentially reimplementing
Freechains' object model on top of legacy infrastructure —
likely the right migration path.

### The Cancel Message Problem

- Usenet cancel messages are unreliable and abused
- Freechains has no delete — consensus/likes surface or
  bury content
- Git commits are also immutable (`git revert` keeps history)
- Hash-addressed systems make "deletion" a social/consensus
  problem, not cryptographic

## MH + Git: Prior Art & Real-World Landscape

### Real Projects

- **public-inbox** — stores mailing lists in git repos
  (used by Linux kernel!).
  Each message is a blob, threads reconstructed via index.
  Serves IMAP/NNTP on top of the git repo.
  Most relevant precedent for Freechains.
  Deliberately avoids sync complexity by being read-only /
  append-only — aligns with our design.
- **git-appraise** — uses git refs to store code reviews
  as "messages" (same idea, not email)
- **muchsync** — syncs Notmuch (email indexer) via
  rsync/git-like approach
- **sup** — CLI email client (Ruby), local index,
  influenced "email as local data" idea
- **aerc** — TUI email client, alternative backends
  (not git directly)

### Git's Built-in Email Tooling

`git format-patch` generates patch emails,
`git imap-send` uploads a mailbox into IMAP drafts,
`git am` applies mbox-formatted patches.
Used by: Linux kernel, PostgreSQL, Git itself.
This is email *as* a code-review transport — email is the
medium, not the stored artifact.

### DIY Git + Maildir Backup

Common pattern: periodically `git add -A` on a maildir,
then `git commit` only if there are changes.
Deletions are just new commits; history is append-only.
Simple and effective for backup, but no conflict resolution
and not designed for multi-machine sync.

### git-annex + Maildir

**`git-annex-maildir`** (fletcher, GitHub): configures a
git-annex repo for maildir storage — multi-machine sync,
offsite backup, bit-rot detection via checksums.

**"Poor man's IMAP"** (git-annex forum): a check-mail
script adds files on the server, commits, then calls
`git annex sync` locally — replacing IMAP with SSH +
git-annex.

### git-notmuch (Metadata Only)

`git-notmuch` (felipec): treats notmuch tag metadata as a
Git repository.
Edit tag files, `git commit`, push back to the notmuch
database.
Does not version message bodies — only the metadata overlay.

### Comparison: Proposal vs Existing Tools

| Tool                  | Git stores     | Sync model       | Scale pain |
|-----------------------|----------------|------------------|------------|
| `git send-email`/`am` | patches        | email transport  | N/A        |
| DIY git + maildir     | message files  | backup only      | low        |
| git-annex + maildir   | message files  | multi-machine    | high       |
| git-notmuch           | tag metadata   | notmuch state    | low        |
| **This proposal**     | MH files       | git push/pull    | low-medium |

No existing tool combines: per-topic repo partitioning +
append-only MH files + GPG-signed commits as delivery
receipt.
The proposal occupies a gap in the landscape.

### Why MH+Git Is Not More Common

- Email has mutable semantics (read/unread, flags, move
  folders) that clash with git's append-only model
- IMAP already solves sync ubiquitously
- Performance: git not optimized for thousands of small
  objects

## Scalability Analysis

### Shared Root Cause with git-annex Failures

Both use Git to track many small files.
Git's index scales O(N) with file count — reading and
rewriting it on every commit is unavoidable.

### Why This Proposal Is Better Positioned

1. **No git-annex daemon overhead.**
   The memory explosions were from git-annex assistant's
   symlink/lock machinery.
   This design uses plain `git add` + `git commit`.

2. **Per-chain repository partitioning.**
   Separate Git repos per Freechains chain naturally caps
   index size.
   A chain is topic/peer-scoped, not a global inbox.

3. **Append-only workload.**
   MH messages are write-once.
   The `lock`/`unlock` cycle that was catastrophically slow
   in git-annex has no equivalent here.

### Scalability Pain Points (Reported)

- 87,000 maildir files (19 GB): git-annex assistant
  consumed all RAM + swap on 512 MB servers
- 150,000 emails: initial add + first sync took hours;
  subsequent incremental syncs were fast
- `git annex lock` on large repos: extremely slow due to
  O(N) index operations

### Practical Threshold

Pain starts at ~87k–150k files *per single repo*.
With per-chain partitioning, hitting that threshold requires
years of traffic on one very active chain.

**Conclusion: same disease, much lower exposure by design.**

## Related: Local Microblogging

- **twtxt**: `.txt` file with timestamped posts;
  threading by hashes (Yarn.social)
- Philosophy: "one file = your feed", no server
- Only CLI clients exist; GUI would be novel
- **maildir/MH as local forum**: threading works
  natively via email headers

## Key Decisions & Rationale

| Decision                    | Rationale                                                    |
|-----------------------------|--------------------------------------------------------------|
| MH over Maildir             | Claws compatibility; Maildir clients lack newsgroup support  |
| Days+hash over hours+hash   | More hash slots (100k vs 1k), same 10-digit budget           |
| Epoch 2025 not Unix epoch   | Saves 5 digits, fits scheme in 32-bit gint                   |
| Local numbers as cache      | Canonical identity in hash; numbers are disposable           |
| Leafnode as translation     | Solves Message-ID→number mapping; Claws needs no mod         |
| Double signing              | Signature bytes cannot be unified; same key proves authorship|

## Open Questions

- [ ] Verify `gint` 32-bit assumption against latest Claws
  source (critical constraint)
- [ ] Leafnode peering over git push/pull instead of
  upstream NNTP
- [ ] GPG signing at git commit layer for newsgroup posts
- [ ] Freechains chain ↔ newsgroup namespace mapping
- [ ] Handling articles arriving out of temporal order
  (hash ensures uniqueness, but day-bucket assignment is
  by arrival not post date)

## TODO

- [ ] Define mapping: chain → MH directory
- [ ] Define mapping: post → RFC 2822 message file
- [ ] Map chain threading to `Message-ID`/`References`
- [ ] Prototype: export chain as MH folder
- [ ] Test with Claws Mail
- [ ] Evaluate Claws Mail Python plugin for integration
- [ ] Consider twtxt as alternative format
