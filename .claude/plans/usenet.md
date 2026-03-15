# Usenet: Email/Newsgroup Clients as Freechains GUI

## Overview

Use existing email/newsgroup clients as a GUI frontend for
Freechains by exposing chain messages in standard mailbox
formats (MH/Maildir).
Message format is identical to email (RFC 2822), and
threading works natively via `Message-ID`, `In-Reply-To`,
`References` headers.

## Status: Research

## Protocols

- **NNTP** — newsgroup protocol (port 119, 563 with SSL)
- Newsgroup hierarchy: `comp.lang.lua`, `rec.sport.*`, etc.
- Message format identical to email (RFC 2822) with extra
  headers: `Newsgroups:`, `Message-ID:`, `References:`,
  `In-Reply-To:`

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
- For local use without concurrent delivery, MH is as
  good as Maildir

### Maildir

- Atomic delivery via `tmp/ → new/`, flags in filename
- Advantages over MH are irrelevant for local newsgroups
  (no concurrent delivery)

## Recommended Client: Claws Mail

- C/GTK, lightweight, active, ~40 plugins
- Native MH support; mbox via plugin
- Native NNTP support (newsgroups)
- Built-in RSS/Atom reader
- Plugins in **C** (`.so`), **Python**, **Perl**
- Extensible without recompiling

### Claws Mail vs Sylpheed

| Aspect           | Sylpheed          | Claws Mail           |
|------------------|-------------------|----------------------|
| Last stable      | 3.7.0 (jan 2018)  | 4.3.1 (feb 2025)    |
| Status           | minimal maint.    | active community     |
| Plugins          | ~3                | ~40                  |
| Scripting        | no                | Python, Perl         |
| NNTP             | yes               | yes                  |

## Local Reading Without Server

- Write directly to MH/Maildir without SMTP/NNTP:
  create files with correct RFC 2822 headers
- Alternative: local Dovecot (IMAP on localhost) +
  any IMAP client
- Claws Mail can read MH directories directly

## Related: Local Microblogging

- **twtxt**: `.txt` file with timestamped posts;
  threading by hashes (Yarn.social)
- Philosophy: "one file = your feed", no server
- Only CLI clients exist; GUI would be novel
- **maildir/MH as local forum**: threading works
  natively via email headers

## TODO

- [ ] Define mapping: chain → MH directory
- [ ] Define mapping: post → RFC 2822 message file
- [ ] Map chain threading to `Message-ID`/`References`
- [ ] Prototype: export chain as MH folder
- [ ] Test with Claws Mail
- [ ] Evaluate Claws Mail Python plugin for integration
- [ ] Consider twtxt as alternative format
