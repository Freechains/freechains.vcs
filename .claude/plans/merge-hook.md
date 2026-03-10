# Git Merge Hook + Consensus (Freechains)

## Objetivo

Rodar verificação de consenso antes que um merge seja efetivado no repositório Git do Freechains.

---

## Hook adequado: `pre-merge-commit`

Roda após o merge commit ser preparado, mas antes de ser finalizado. Sair com código não-zero aborta o merge.

```bash
# .git/hooks/pre-merge-commit
#!/bin/sh
if ! ./scripts/check-consensus.sh; then
  echo "Consensus check failed. Merge aborted."
  exit 1
fi
```

### Outros hooks relevantes

- **`pre-receive`** (server-side) — roda no servidor antes de qualquer ref ser atualizada. Ideal para workflows centralizados.
- **`update`** (server-side) — similar ao `pre-receive`, mas por branch. Mais granular.

---

## Caveat: Fast-forward ignora o hook

Fast-forward merges não criam um merge commit, então o `pre-merge-commit` **não dispara**. Soluções:

1. Forçar `--no-ff` em todos os merges.
2. Usar um wrapper script que sempre passa `--no-ff`.

---

## Por que `--no-ff` faz sentido em geral

- **Preserva topologia** — dá pra ver que aquele grupo de commits entrou junto como uma unidade. Com fast-forward, o branch some no histórico linear.
- **Ponto de merge explícito** — existe um commit concreto onde a integração aconteceu. Útil como âncora para hooks, auditorias e provas de consenso.
- **Registro atômico** — o merge commit pode carregar metadados (quem fez o merge, quando, prova de consenso) na mensagem ou em git notes.
- **Revert limpo** — reverter um merge `--no-ff` é reverter um commit. Com fast-forward, é preciso caçar cada commit individualmente.

---

## Por que `--no-ff` faz ainda mais sentido para o Freechains

- Um merge numa chain é um **evento de consenso deliberado**, não só "atualizar o ponteiro." O merge commit *é* o registro de consenso.
- Cria um ponto claro de antes/depois para anexar a prova de consenso.
- Fast-forward implicaria que os commits já foram aceitos — pulando toda a etapa de validação.
- O merge commit carrega `Freechains-Peer: <pubkey>` no
  trailer, identificando o peer que fez o sync. Assinado
  com GPG (`-S`), o merge se torna uma attestation:
  "peer X viu este estado do branch no tempo T."
  Ver trailer.md para detalhes.

### Verificando no hook

```bash
# Checar que é um merge real (não fast-forward)
if [ -z "$GIT_MERGE_HEAD" ]; then
  echo "Fast-forward detected. Use --no-ff for Freechains merges."
  exit 1
fi
```

---

## Veto & Fork Guards (merge.md)

The pre-merge-commit hook must also enforce veto and fork
decisions:

### Veto guard (dropped set)

If a veto has passed (>50% of prefix reputation voted to
drop a branch), the hook must reject merges that would
reintroduce dropped commits:

```bash
# Check if FETCH_HEAD contains any commit in the dropped set
DROPPED=$(cat .freechains/dropped-sets/*.list 2>/dev/null)
if [ -n "$DROPPED" ]; then
  for hash in $DROPPED; do
    if git merge-base --is-ancestor "$hash" FETCH_HEAD 2>/dev/null; then
      echo "Merge blocked: contains vetoed commit $hash"
      exit 1
    fi
  done
fi
```

### Fork guard (chain identity)

After a hard fork (vote difference crossed threshold),
the hook must reject merges from the other fork:

```bash
# Check if FETCH_HEAD belongs to a different fork identity
# (fork-point + branch-side stored in .freechains/fork)
if [ -f .freechains/fork ]; then
  FORK_POINT=$(head -1 .freechains/fork)
  OUR_SIDE=$(tail -1 .freechains/fork)
  # FETCH_HEAD must descend from our side, not the other
  if ! git merge-base --is-ancestor "$OUR_SIDE" FETCH_HEAD 2>/dev/null; then
    echo "Merge blocked: FETCH_HEAD belongs to other fork"
    exit 1
  fi
fi
```

These guards ensure that once a veto or fork decision is
made, it cannot be undone by a careless or malicious merge.
