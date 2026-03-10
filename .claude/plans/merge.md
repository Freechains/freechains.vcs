# Git Merge & Freechains

---

## 1. Git Merge Internals

### Parent ordering (invariant)

A merge commit has exactly two parents:
- **First parent** (`^1`) = local HEAD before merge
- **Second parent** (`^2`) = remote FETCH_HEAD

This is a **git invariant**, not a convention. Immutable
after the merge. Any peer can recover which side was local
and which was remote:

```bash
git show <merge>^1   # local branch
git show <merge>^2   # remote branch
git cat-file -p <merge>   # raw: "parent <hash1>" then "parent <hash2>"
```

After propagation: when peer C fetches from peer A (who
already merged B's content), C sees A's merge commit with
A's parent ordering intact. C then creates its own merge.
The chain preserves local/remote distinction at each hop.

### Estratégias (`-s`)
- **`ort`** (padrão atual): detecta renomeações, lida bem com merges cruzados.
- **`recursive`**: antigo padrão, merge three-way recursivo.
- **`resolve`**: mais simples, um único ancestral comum.
- **`octopus`**: múltiplos branches ao mesmo tempo, não aceita conflitos manuais.
- **`ours`**: ignora completamente o outro branch — mantém HEAD integralmente.
- **`subtree`**: variante do `ort` para subárvores de diretório.

### Opções de Desempate (`-X`)
Atuam **somente nas partes em conflito** — mudanças não conflitantes entram normalmente.

- **`-X ours`**: em conflito, vence o lado do HEAD.
- **`-X theirs`**: em conflito, vence o lado do branch mergeado.
- **`-X ignore-space-change`** / **`ignore-all-space`**: ignora diferenças de espaçamento.

> **Distinção importante:**
> | Mecanismo | Escopo |
> |---|---|
> | `-X ours` / `-X theirs` | Só resolve o empate nos conflitos |
> | `-s ours` | Descarta tudo do outro branch |

### Atributos de Merge (`.gitattributes`)
Permite definir drivers por tipo de arquivo: `text`, `binary`, `union` (concatena sem conflito), `ours`, ou drivers externos customizados.

### Rerere
`git rerere` memoriza resoluções de conflito e as reutiliza automaticamente — útil em rebases repetidos.

---

## 2. Detectar Conflitos Antes do Merge

### `git merge-tree` (melhor opção)
Faz o merge virtualmente, sem tocar no working tree:

```bash
git merge-tree --write-tree HEAD branch-alvo
echo $?   # 0 = sem conflito, 1 = tem conflito
```

Disponível de forma completa a partir do Git 2.38. Ideal para automação e CI.

### `--no-commit --no-ff`
Faz o merge mas não commita — permite inspecionar antes de confirmar:

```bash
git merge --no-commit --no-ff branch-alvo
git diff --cached
git merge --abort   # desfaz tudo
```

### `git diff` dos branches
Dá uma visão das divergências (não detecta conflitos diretamente):

```bash
git diff HEAD...branch-alvo
```

---

## 3. Freechains Merge Semantics

### Merge = sync event

- Merges are always `--no-ff` — an explicit merge commit
  is created every time (see merge-hook.md)
- The merge commit is a **sync event**: "peer X integrated
  remote content at time T"
- `Freechains-Peer: <pubkey>` trailer identifies the peer
  (see trailer.md)
- GPG signing (`-S`) makes it a signed attestation
- Merge commits are currently **skipped** in reputation
  computation (reps.md)
- The `pre-merge-commit` hook runs consensus checks before
  the merge is finalized

### Sync flow

```
git fetch <remote> <branch>
git merge --no-commit --no-ff FETCH_HEAD   # dry-run
git merge --abort                          # clean up
git merge --no-edit FETCH_HEAD             # real merge (--no-ff)
```

- Never use `git pull` (bypasses validation)
- Fast-forward skips `pre-merge-commit` hook → must be
  rejected (see merge-hook.md)

### Resolução de Conflitos por Reputação

```
1. merge-tree --write-tree HEAD branch-alvo
       │
       ├── exit 0 → sem conflito → merge normal
       └── exit 1 → tem conflito → consulta reputação
                                        │
                                ours > theirs?
                                   ├── sim → merge -X ours
                                   └── não → merge -X theirs
```

### Bloco de Merge

O commit de merge deve registrar no metadata se houve conflito e quem venceu,
permitindo que outros peers verifiquem a decisão de forma independente:

```
merge-block:
  parents: [hash-A, hash-B]
  conflict: true | false
  winner: "ours" | "theirs" | null   # null se não houve conflito
  rep-ours: 42
  rep-theirs: 31
```

### Considerações

**Determinismo é crítico.** Todos os peers precisam chegar à mesma decisão.
Duas abordagens para garantir isso:
- A reputação usada no desempate é **snapshotada no momento do bloco** e gravada nele.
- Ou a reputação é calculada **até o ancestral comum** (ponto de consenso entre os dois lados), evitando divergências causadas por estado local diferente.

**Empate de reputação** requer critério de desempate secundário determinístico,
por exemplo: hash do bloco, timestamp, ou ordem lexicográfica dos autores.

**Auditabilidade:** gravar `rep-ours` e `rep-theirs` no bloco permite que qualquer
peer audite a decisão depois, mesmo que a reputação tenha mudado desde então.

---

## 4. Merge Voting — Likes/Dislikes on Merge Commits

**Status**: NOT REVIEWED — idea dump, not a design.

### Mechanism

1. Merge commits become **votable objects** — peers can
   post likes/dislikes targeting a merge commit hash
   (using `Freechains-Ref: <merge-hash>`)

2. Dislikes accumulate against the merge. If they cross
   a threshold (analogous to post-ban), the merge is
   **rejected**:
   - The merge commit and all commits reachable only
     through the second parent (remote side) are dropped
   - History reverts to the first parent (local side)
   - Any commits built on top of the merge are also
     dropped (they reference a rejected base)

3. "Dropped" means: for consensus computation, the merge
   and its remote-only descendants are treated as if they
   never existed. The DAG still contains them (git doesn't
   delete objects), but the consensus walk ignores them.

### Veto storage — winning side

The veto record **must be stored on the winning side**
(first parent / surviving branch) as a committed artifact.
This prevents the vetoed content from being re-merged,
even unintentionally:

1. When a merge is vetoed, a **veto commit** is created on
   the surviving branch. It records the hash of the rejected
   merge commit (and thus its second-parent subtree):

   ```
   Freechains-Kind: veto
   Freechains-Ref: <rejected-merge-hash>
   ```

2. The veto commit is a normal post on the winning branch —
   it propagates through replication like any other commit.

3. **Pre-merge guard**: before completing any future merge,
   the `pre-merge-commit` hook checks whether the incoming
   content (FETCH_HEAD subtree) overlaps with any vetoed
   merge. If the second parent of a previously vetoed merge
   is an ancestor of FETCH_HEAD, the merge is **rejected
   automatically** — the vetoed content cannot sneak back in
   through a different peer or a later sync.

4. **Why the winning side**: if the veto were stored only in
   memory or on the losing side, it would be invisible after
   the drop. A new sync with the same (or a superset of the)
   remote content would succeed, silently re-introducing
   everything the community voted to reject. Storing the
   veto on the surviving branch makes it a permanent,
   replicable part of the chain history.

5. **Determinism**: the veto commit hash is deterministic
   (same content, same trailers → same hash across peers),
   so all peers converge on the same veto set.

### Network split — veto propagation

The veto on the winning side must propagate to prevent
re-merge. But propagation creates fundamental problems
when multiple sides issue competing vetos.

#### The competing vetos problem

1. A and B diverge from common ancestor. A has branch X,
   B has branch Y.
2. A merges Y, then vetoes it → V_A: "drop Y's subtree"
3. B merges X, then vetoes it → V_B: "drop X's subtree"
4. Neutral peer C syncs with both. Receives V_A and V_B.

If C enforces both vetos: **everything is dropped** — X
and Y are both excluded, only genesis survives.

If C enforces only one: **which one?** This is exactly
the branch ordering problem the veto was supposed to
complement. Competing vetos collapse into consensus.

#### Neutral peers who received the wrong side first

Even with a single veto, neutral peers are affected:

- Peer C synced with B before the veto — Y is in C's
  history through C's own merge
- C later receives V_A. Uniform enforcement drops Y's
  commits, but C already built on top of them.
- C's own content (posted after merging Y) is orphaned
  as collateral damage.

This is the **typical case**: most peers will have
received content from both sides before any veto
propagates.

#### Resolution: veto threshold > 50%

The threshold determines whether competing vetos can
coexist:

- **Threshold > 50% of total chain reputation**: at most
  one side can ever accumulate enough dislikes to veto.
  Competing vetos are **impossible** — the reputation
  backing V_A and V_B must sum to > 100%, which can't
  happen. Peer C receives both vote sets but only one
  (or neither) crosses the threshold.

- **Threshold ≤ 50%**: competing vetos are possible and
  the system needs a tiebreaker — which reduces to the
  same consensus ordering problem. This is undesirable.

**Therefore: the veto threshold must exceed 50% of total
reputation.** This guarantees that at most one veto can
be active for any given fork. The veto becomes a genuine
**supermajority decision**, not just a faction's preference.

#### Consequence: the veto is rare and decisive

With a >50% threshold:

- A veto requires the **majority** of the community's
  reputation to agree. This is a high bar — appropriate
  for a nuclear option.
- The losing side is genuinely in the minority. The veto
  reflects community consensus, not a factional split.
- If neither side reaches >50%, **no veto passes** and
  normal consensus ordering applies (reputation in common
  prefix, tiebreakers per consensus.md).
- The veto adds value over normal consensus ordering only
  when the community wants to **retroactively reject** a
  merge that already happened — it's not a replacement
  for branch ordering, it's a correction mechanism.

#### Fundamental limit: the veto is social, not algorithmic

The >50% threshold prevents competing vetos mechanically.
But it doesn't help neutral peers C and D **choose which
side to join**.

The decision "which branch do I follow?" cannot be
answered by content-based consensus:

- **Prefix reputation** is the same for both sides — it
  can't break symmetry when both sides have legitimate
  content.
- **Suffix content** (the divergent part) differs by
  definition — each side has different posts. But C and D
  care about **who** wrote the suffix, not just **what**
  it contains.
- **The veto itself is a signed vote**: it carries the
  author's pubkey and reputation. C and D need to look at
  which authors voted for which side — it's a coalition
  decision, not a content decision.

This means the veto mechanism requires some form of
**peer/author affiliation** to function in the general
case. Possible directions:

1. **Author-weighted votes**: C looks at the authors who
   signed veto dislikes on each side. "Authors I follow /
   trust have >50% reputation and voted to drop Y → I
   follow their decision." This is implicit coalition
   membership via trust relationships.

2. **Explicit chain fork**: instead of a veto within one
   chain, the split produces **two new chain identities**
   derived from the original. Peers subscribe to the
   chain whose author set they want to follow. The fork
   is a first-class operation, not a side effect of
   competing votes. The original chain is frozen at the
   fork point — a historical record of the shared past.

3. **Pioneer/owner arbitration**: in chains with a clear
   authority structure (owned chains, or chains where
   pioneers hold decisive reputation), the authority
   resolves the split. This works for hierarchical
   communities but not for fully decentralized ones.

4. **Peer mapping**: each peer maintains a local mapping
   of "peers I sync with" → "authors I trust." When a
   fork occurs, the peer follows the branch containing
   the authors in its trust set. This is subjective
   (different peers may choose differently), but that
   may be correct — a genuine community split SHOULD
   result in different peers going different ways.

**Open question**: which of these directions (or
combination) fits Freechains? Option 4 (peer mapping /
local trust) is the most general but breaks deterministic
consensus — two peers with different trust sets reach
different conclusions. Option 2 (explicit chain fork) is
cleanest but requires new chain identity machinery.
Option 1 (author-weighted votes) reuses existing
reputation but needs a way for peers to express "I follow
these authors" beyond just having their content.

The core tension: **deterministic consensus requires
shared rules, but choosing a side in a genuine split is
inherently subjective.** Any mechanism that resolves this
deterministically (>50% threshold) imposes the majority's
choice on the minority. Any mechanism that allows
subjective choice (peer mapping) breaks consensus
determinism. The right answer depends on whether
Freechains prioritizes network unity (deterministic) or
individual autonomy (subjective fork).

#### Cascade: peers who already merged vetoed content

When a veto passes (>50%), peers who already merged the
vetoed content through normal sync are affected:

1. The **dropped set** is deterministically computed from
   the vetoed merge M: `git rev-list M^2 --not M^1`
2. All peers exclude dropped commits from consensus —
   sync-order independent, same hash → same dropped set
3. A peer C who merged Y before the veto sees its own
   merge M_c logically dropped (it brought in dropped
   commits)
4. C's content posted after M_c is orphaned in the DAG

For orphaned content, two options:
- **Hard drop**: C re-posts. Simple, harsh.
- **Logical rebase**: consensus walk replays C's own
  commits, skipping the dropped merge. Breaks if C's
  commits reference dropped content (likes on dropped
  posts).

#### Pre-merge guard

The veto prevents **future** re-merges:

- Before merging FETCH_HEAD, check: does FETCH_HEAD
  contain any commit in any active dropped set?
- If yes → reject the merge automatically
- This prevents re-merge, even unintentionally

#### Reconciliation

To reunify after a veto:

1. Dropped content's authors can re-post legitimate parts
   as **new commits** (new hashes) — not in any dropped
   set
2. New commits enter through normal validation (12h
   penalty, reputation checks)
3. The veto blocks **specific commits**, not authors

If the minority disagrees with the veto, they can fork:
refuse to propagate the veto commit. This is an explicit
community split — correct outcome when >50% vs <50%
genuinely disagree.

### Why first-parent ordering matters

The rollback is well-defined **because** git preserves
parent ordering. "Drop the merge" always means "keep
local, reject remote." Without this invariant, you
wouldn't know which side to keep.

### What this enables

- **Collective veto on sync events**: if someone syncs
  with a malicious peer and brings in spam/attacks, the
  community can vote to undo it
- **Retroactive defense against T2a**: a merge that
  brought in backdated posts can be voted out after the
  fact — the merge-witness timestamp idea (threats.md)
  makes the manipulation visible, and merge voting
  provides the enforcement mechanism
- **Accountability**: the `Freechains-Peer` trailer
  identifies who performed the merge. Repeated bad merges
  → pattern of bad judgment → peers stop syncing with
  that node

### Open questions (NOT REVIEWED)

1. **Threshold**: Must exceed 50% of total chain reputation
   to prevent competing vetos (see "Resolution" above).
   Exact value TBD — 51%? 67% (supermajority)? Higher
   thresholds make vetos rarer but more legitimate.

2. **Cascading drops**: When a veto drops commits, any
   merge by a neutral peer that already integrated those
   commits is also logically dropped. Content posted by
   the neutral peer after that merge is orphaned. Should
   the system do a hard drop (peer re-posts) or a logical
   rebase (consensus walk replays their commits)? Logical
   rebase is friendlier but more complex — and breaks if
   the orphaned commits reference dropped content (e.g.,
   a like targeting a dropped post).

3. **Timing**: Can a merge be voted out at any time, or
   only within a window (e.g., 24h)? Unbounded voting
   means old consensus can be retroactively disrupted.

4. **Who can vote**: Anyone with reputation? Only peers
   who have the merge in their DAG? Only peers who
   were "online" (had recent activity) when the merge
   happened?

5. **Determinism**: All peers must agree on whether the
   merge is dropped. The threshold check must be
   deterministic — same inputs, same decision. This
   means the vote tally must be computed at a consistent
   DAG state.

6. **Interaction with consensus ordering**: Dropped merges
   change the DAG topology → change `--date-order`
   traversal → change reputation → potentially change
   other vote tallies. Circular dependencies?

7. **Attack surface**: Could merge voting itself be
   weaponized? A cabal with sufficient reputation could
   vote to drop legitimate merges, effectively censoring
   content. This is the same problem as dislike-based
   censorship on posts — does the threshold provide
   adequate protection?

8. **Recovery**: After a merge is dropped, the veto commit
   on the winning side **permanently blocks** re-merging
   the same content. To recover legitimate posts from a
   vetoed merge, they must be re-posted individually (new
   commits, new hashes) — the original merge path is
   closed. This is intentional: it forces content to
   re-enter through normal validation rather than
   piggy-backing on an already-rejected sync. See
   "Reconciliation" above for the full reunification path.

9. **Logical rebase semantics**: If the consensus walk
   replays orphaned commits (from neutral peers who
   merged vetoed content before the veto arrived), what
   happens to commits that reference dropped content?
   A like on a dropped post becomes invalid. A reply to
   a dropped post is orphaned. Must define: (a) which
   commit types can be replayed, (b) which must be
   dropped with the content they reference, and (c) how
   to notify the affected peer that their content was
   collateral damage.

---

## 5. Relationship to Other Mechanisms

| Mechanism              | Scope           | Timing      |
|------------------------|-----------------|-------------|
| 12h penalty on posts   | Individual post | Preventive  |
| Dislike on posts       | Individual post | Reactive    |
| Merge-witness timestamp| Detection       | At merge    |
| **Merge voting**       | **Entire sync** | **Reactive**|
| Consensus ordering     | Branch priority | At merge    |

Merge voting is the only mechanism that operates at the
**sync-event granularity** rather than individual posts.
It's a coarser tool — a nuclear option for when an entire
batch of incoming content is bad.

---

## Related Plans

- [merge-hook.md](merge-hook.md) — `--no-ff` requirement,
  `pre-merge-commit` hook
- [trailer.md](trailer.md) — `Freechains-Peer:` on merges
- [threats.md](threats.md) — T2a merge-witness timestamps
- [reps.md](reps.md) — Reputation computation (skips merges)
- [consensus.md](consensus.md) — Fetch → validate → merge
