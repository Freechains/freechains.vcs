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

8. **Recovery**: After a merge is dropped, can the remote
   content be re-merged later (by a different peer, or
   after the attacker's posts are individually disliked)?
   Or is it permanently excluded?

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
