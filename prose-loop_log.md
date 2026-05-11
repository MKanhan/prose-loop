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

## Handoff — 2026-05-11 (Spec 01 + Spec 02 done)

### Estado atual
v1.1.0 funcional, validado em uso real. **Status: active**. Repo git inicializado, branch `main`, 2 commits, working tree clean, 7 arquivos tracked.

- Specs 01 + 02 implementadas.
- `.local/AUDIT.md` signed off (2026-05-11).
- Scanner skip-list inclui LICENSE-class files após false positive no copyright holder (fix em commit 1504aa8).
- audit-scan.sh tem mode 100644 (não +x). Invocação canônica: `bash scripts/audit-scan.sh`. Sandbox bloqueou `chmod +x`.
- URL canônica do portfólio do operador: `kanhan.com.br/en/build/` (corrigida — antes estava como /apps).

### Próxima ação
**Spec 03 — Rubric externalization** (paralelizável com Spec 04).
- Criar `rubrics/default.json` (EN keys) e `rubrics/pt-br-nonfiction.json` (preserva atual).
- Adicionar `--rubric PATH` flag em `prose_loop.sh`.
- Refator de `build_eval_prompt` + `print_score_table` para iterar sobre dimensões da rubrica.
- Manter composite divisor 7.7 para compatibilidade numérica.
- Sanity: composite com `--rubric rubrics/pt-br-nonfiction.json` deve bater (±0.1) com v1.1.0 no mesmo livro.

### Ordem de execução das specs
01 ✅ → 02 ✅ → **03 (next, ‖ com 04)** → 05 → 06.

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
