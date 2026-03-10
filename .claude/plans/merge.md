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

### Network split — veto propagation boundaries

The veto on the winning side creates a **de facto network
partition**. This is intentional, but must be handled
carefully to avoid poisoning peers on the losing side.

#### The problem

1. Peer A vetoes merge M (second parent = Y, from peer B)
2. Veto commit V is on A's surviving branch
3. A's guard blocks fetching from B (B's HEAD descends
   from Y → rejected)
4. But B can still initiate a fetch from A — B has no
   vetos, so A's content passes B's guard
5. B receives V as part of the merge. Now B's guard
   also blocks descendants of Y — **B's own history**
6. The veto has propagated to the losing side and
   poisoned it

#### Solution: perspective-relative enforcement

The pre-merge guard must be **perspective-relative** —
a veto only blocks content that is **foreign** to the
peer's own first-parent lineage:

1. When evaluating a veto, the guard checks: "is the
   vetoed merge's second parent (Y) an ancestor of
   **my own first-parent chain**?"
   - **Yes** → I am on the losing side of this veto.
     **Ignore it** — it's about my own content, not
     foreign content sneaking in.
   - **No** → I am on the winning side (or a neutral
     peer). **Enforce it** — block any FETCH_HEAD
     descended from Y.

2. This means the same veto commit has different effects
   depending on which side of the split you're on:
   - **Winning side peers**: enforce the veto, block
     the vetoed content
   - **Losing side peers**: see the veto but don't
     enforce it against their own history

3. **Determinism is preserved**: the check is purely
   DAG-based. Given the same DAG, all peers on the same
   side reach the same decision. Two peers with identical
   first-parent lineage always agree.

#### Natural partition behavior

With perspective-relative enforcement, the network splits
cleanly:

- **Winning partition**: peers whose first-parent lineage
  does NOT include Y. They enforce the veto. They can sync
  with each other freely. They reject content from the
  losing side.

- **Losing partition**: peers whose first-parent lineage
  includes Y. They receive the veto but ignore it (it
  targets their own history). They can sync with each
  other freely. They can receive winning-side content
  (including the veto commit) without self-poisoning.

- **Cross-partition sync**: winning → losing is blocked
  by the guard (losing side's content descends from Y).
  Losing → winning: the veto propagates, but losing-side
  peers ignore it. The partition is **asymmetric**: losing
  side can receive winning-side content, but not the
  reverse.

#### Reconciliation

To reunify after a veto-induced split:

1. The losing side **individually dislikes** or removes
   the problematic content that triggered the veto
2. A peer on the losing side creates a **new branch**
   from the common prefix (before the fork), re-posting
   only the legitimate content as new commits
3. This new branch does NOT descend from Y → not blocked
   by the veto guard
4. A new merge with the winning side succeeds — the
   legitimate content re-enters through normal validation

Alternatively, if the losing side believes the veto was
unjust, they simply continue independently — the chain
has forked, and both sides evolve separately. This is
the correct outcome when a community genuinely disagrees.

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

2. **Cascading drops**: If merge M1 is dropped, and merge
   M2 was built on top of M1, M2 must also be dropped.
   But M2 might have brought in legitimate content too.
   Is this acceptable collateral?

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

9. **Perspective-relative edge cases**: The guard ignores
   vetos targeting your own first-parent lineage. But what
   if a peer is on NEITHER side (joined after the split)?
   They have no first-parent relationship to Y, so they
   enforce the veto — correct behavior (they align with
   the winning side by default). What if a peer has BOTH
   sides in their history (merged before the veto)? They
   have Y as a second-parent ancestor — the check must
   use **first-parent only** traversal to determine side.

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
