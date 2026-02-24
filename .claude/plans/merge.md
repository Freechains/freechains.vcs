# Git Merge & Freechains — Plano de Resolução de Conflitos

## Mecanismos de Merge Automático no Git

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

## Detectar Conflitos Antes do Merge

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

## Freechains — Resolução de Conflitos por Reputação

### Fluxo

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
