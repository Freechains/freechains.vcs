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
re-merge. But propagation interacts badly with peers who
received the vetoed content through normal sync.

#### The problem

1. Peer A vetoes merge M (second parent = Y, from peer B)
2. Veto commit V is on A's surviving branch
3. Meanwhile, neutral peer C synced with B **before** the
   veto — Y is now in C's history through C's own merge
4. C later syncs with A and receives V
5. V says "drop everything from Y's subtree" — but C
   already has Y in its DAG

This is the **typical case**: most peers will have received
content from both sides before any veto propagates. The
peer's "side" becomes a function of sync timing — who
they talked to first — which is arbitrary.

#### Why perspective-relative enforcement fails

A naive fix: "ignore vetos that target your own first-
parent lineage." This fails because:

- Peer C received Y first (by chance), so Y is in C's
  first-parent chain. C ignores the veto.
- Peer D received A's side first. D enforces the veto.
- C and D are on the same network, saw the same content,
  but reach **different conclusions** based on sync order.
- The "side" assignment is non-deterministic — it depends
  on network timing, not community intent.

#### Uniform enforcement with logical drop

The veto must be enforced **uniformly** by all peers,
regardless of sync order. The mechanism:

1. The veto commit V references merge M by hash. The
   **dropped set** is deterministically computed:
   `git rev-list M^2 --not M^1` — all commits reachable
   from M's second parent but not from M's first parent.
   These are the commits the remote side contributed.

2. **Every peer** that receives V excludes the dropped
   set from consensus computation. The DAG still contains
   the commits (git doesn't delete objects), but the
   consensus walk skips them.

3. This is sync-order independent: the dropped set is
   computed from M's hash, which is the same for everyone.

#### Cascade: what happens to peer C?

Peer C already merged Y's content through its own merge
M_c. When C receives the veto:

1. The dropped set (from M) overlaps with C's history —
   C has those commits in its DAG
2. C's own merge M_c brought in dropped commits →
   **M_c is also logically dropped** (it integrated
   rejected content)
3. C's effective HEAD reverts to the first parent of M_c
   (C's state before merging Y's content)

**Content C posted after M_c**: these commits are
children of M_c in the DAG, so they're orphaned by the
logical drop. But their content is independent of Y's
content — they're C's own posts. Two options:

- **Hard drop**: C's post-merge content is also dropped.
  C must re-post it. Simple, but harsh — C loses work
  through no fault of its own.
- **Logical rebase**: the consensus walk "replays" C's
  own commits on top of the pre-merge HEAD, skipping the
  dropped merge. More complex, but preserves C's work.
  Requires that C's commits are semantically independent
  of the dropped content (true for posts, may not be true
  for likes/dislikes that reference dropped posts).

#### Pre-merge guard

The veto also prevents **future** merges that would
reintroduce dropped content:

- Before merging FETCH_HEAD, check: does FETCH_HEAD
  contain any commit in any active dropped set?
- If yes → reject the merge automatically
- This is what prevents re-merge, even unintentionally

#### Reconciliation

To reunify after a veto:

1. Peers who had the vetoed content see it logically
   dropped — their effective HEAD reverts to before
   the merge that brought it in
2. The bad content's authors can re-post legitimate
   parts as **new commits** (new hashes) — these are
   not in any dropped set
3. New commits enter through normal validation
   (12h penalty, reputation checks, etc.)
4. The veto blocks the **specific commits**, not the
   authors — authors can continue participating

If a significant group disagrees with the veto, they
effectively fork: they ignore the veto commit (treat it
as invalid / don't propagate it). This is an explicit
community split — the same outcome as any irreconcilable
disagreement in a decentralized system.

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

1. **Threshold**: Same as post-ban? Different? Should it
   scale with the amount of content in the merge?

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
