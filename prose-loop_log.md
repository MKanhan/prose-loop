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

## Handoff — 2026-05-11 (Specs 01-05 done; ready for Spec 06)

### Estado atual
**Status: active**. Repo git, branch `main`, 8 commits, working tree clean, ~20 arquivos tracked.

- Specs 01-05 implementadas.
- README.md, CHANGELOG.md, examples/sample-run/ publicados (Spec 05).
- Bug latente encontrado e corrigido durante Spec 05: `print_score_table` abortava silenciosamente sob `set -eo pipefail` quando `cycle_*_compare.json` ainda não existia (commit a06154d). CHANGELOG documenta. <!-- audit:allow operator portfolio site --> URL canônica kanhan.com.br + substack.kanhan.com.
- audit-scan.sh continua mode 100644 (sandbox bloqueia chmod +x); invocação `bash scripts/audit-scan.sh`.

### Verificação executada
- Self-test scanner: passa.
- Audit scan: exit 0.
- Dry-run sobre fixture mini-book (Sonnet): composite 6.13, score table completa com per-chapter rows + markers ◄.
- examples/sample-run/cycle_0_eval.json e score-table.txt criados a partir desse run.
- README cold-read: responde what / how / cost / privacy / license em <2min.

### Próxima ação
**Spec 06 — CI & publication**. Última sprint.
- Shellcheck sobre prose_loop.sh + scripts/audit-scan.sh; aplicar fixes ou disable-comments justificados.
- `.github/workflows/ci.yml` mínima: checkout + install shellcheck + `shellcheck *.sh` + `PROSE_LOOP_CI=1` smoke test (precisa adicionar early-exit em prose_loop.sh).
- Re-audit final sobre repo completo.
- Renomear `## [Unreleased]` no CHANGELOG para `## [1.2.0] - 2026-05-DD`.
- Criar repo público em github.com/<handle>/prose-loop, push main, push tag v1.2.0.
- Adicionar entry em kanhan.com.br/en/build/. <!-- audit:allow operator portfolio site -->

### Ordem de execução das specs
01 ✅ → 02 ✅ → 03 ✅ → 04 ✅ → 05 ✅ → **06 (final)**.

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
