# prose-loop — Log

ADRs, design rationale, deferred backlog, known issues, handoff. Sprint history (uma vez que git existir) fica em git log.

## Architecture decisions (ADRs)

| # | Decisão | Descartada | Por quê |
|:---:|:---|:---|:---|
| 0001 | Shell script + Claude CLI como motor | SDK Python/TS | Zero install além do que operador já tem; portátil; sem build step |
| 0002 | Snapshots BEFORE/AFTER em `prose_scores/snapshots/` | Re-pontuar e usar delta | Avaliador é ruidoso ciclo-a-ciclo; comparação direta dá sinal mais limpo |
| 0003 | Comparator pass (3º LLM call) decide ACCEPT/REJECT | Delta numérico de score | Score numérico oscila por ruído; comparator vê o texto direto |
| 0004 | Git tag + commit por ciclo aceito; revert via `git checkout --` no reject | Diretório de versões / arquivo de undo | Git já existe no book project; nada a inventar |
| 0005 | (Spec 03, planned) Rubrica como JSON externo, EN keys default | Hardcoded PT-BR | Lock-in de idioma e gênero; impede adoção fora do contexto de origem |
| 0006 | (Spec 01, planned) Auditoria de PII como gate antes de `git init` | Confiar em revisão visual | Risco de leak não vale 1h de scan determinístico |
| 0007 | `specs/` vivem em `.local/specs/`, não tracked | Publicar specs sanitizadas no repo | Specs eram fonte de 18/23 hits PII e exigiriam edição contínua; mover elimina superfície sem perder a metodologia spec-driven internamente. Decidido durante implementação da Spec 01 |

## Handoff — 2026-05-11 (Spec 01 done)

### Estado atual
v1.1.0 funcional, validado em uso real. **Status: active** (saindo de paused). Sprint de publicação open-source em andamento. Spec 01 implementada.
- 6 specs em `.local/specs/` (movidas de `specs/` durante esta sprint — ver ADR 0007).
- `scripts/audit-scan.sh` criado, self-test passa, scan retorna 0 hits.
- Redactions aplicadas em `prose_loop.sh` (linhas 10, 59, 60) e `CLAUDE.md` (linhas 17, 18, 21, 72 com marker `audit:allow`).
- `.local/AUDIT.md` documenta as 5 decisões + verificação. **Pendente sign-off manual do operador** (datar a linha no final do AUDIT.md).
- Sem `.git/` ainda — proposital, Spec 02 cria.

### Próxima ação
**Spec 02 — Repo bootstrap.** Desbloqueada por Spec 01 (pendente apenas sign-off em AUDIT.md).
- Atestar `AUDIT.md` (operador dating a linha de sign-off).
- `git init` no diretório.
- Criar `LICENSE` (MIT, holder a definir).
- Criar `.gitignore` (cobrir `.local/`, `prose_scores/`, `specs/`, `.DS_Store`, etc.).
- Primeiro commit: `LICENSE + .gitignore + prose_loop.sh + CLAUDE.md + prose-loop_log.md + scripts/audit-scan.sh`. Sem `specs/`.
- AC do Spec 02 incluem teste de que `prose_scores/` gerado por run real não aparece em `git status`.

### Ordem de execução das specs
01 (✅ implementado, sign-off pendente) → 02 (bootstrap) → 03 e 04 (paralelos) → 05 (depende de 03, 04) → 06 (fecha, push público).

### Materialidade pra portfolio-state.md
Status do projeto mudou de `paused` para `active`. Operador pode querer atualizar `portfolio-state.md` quando o ciclo encerrar (Spec 06 done + repo público).

### Custo estimado da sprint
Não há gasto Anthropic significativo nas specs 01, 02. Specs 03, 04 envolvem testes via dry-run em fixtures sintéticos (~$0.50-$2). Spec 05 precisa de pelo menos um run completo em mini-book para gerar example output (~$1). Spec 06 sem gasto. Total esperado: <$10.

## Known issues / Tech debt

### v1.1.0 → v1.2.0 break
Spec 03 muda chaves de PT-BR para EN no default rubric. JSONs em `prose_scores/` de runs antigos ficarão ilegíveis pelo novo `print_score_table`. Aceitável — documentado no CHANGELOG (Spec 05). Operador que quiser preservar rodadas antigas roda `--rubric rubrics/pt-br-nonfiction.json`.

### Operador é o único usuário até Spec 06
Até o push público, sem feedback externo. Pode ser que a rubrica EN escolhida em Spec 03 não ressoe com gêneros que o operador não usa (poesia, romance literário). Mitigação: o próprio mecanismo `--rubric` permite override; fica para PRs externos refinarem.

### `extract_json` passa output inteiro como sys.argv[1]
Output de avaliação de livro grande pode estourar o limite de args no exec do Python. Não observado em prática até hoje, mas vale anotar — refator para stdin se necessário. Não bloqueia open-source release.

## Deferred backlog (pós-v1.2.0)

Listado em `CLAUDE.md` → Roadmap → Deferred. Resumo:
- Model routing (Sonnet eval, Opus rewrite)
- HTML report generation
- Asciinema cast
- Multi-OS CI matrix
- Distribution channels (homebrew, etc.)
