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

## Handoff — 2026-05-11 (v1.2.0 released; Specs 01-06 complete)

### Estado atual
**Status: released**. Repo público em github.com/MKanhan/prose-loop. Tag `v1.2.0` propagada. CI verde (~27s no primeiro run). Release publicada com notes do CHANGELOG. <!-- audit:allow operator portfolio site -->

- 20+ arquivos tracked, ~13 commits.
- Site entry publicada em kanhan.com.br/en/build/ (posição 08, cover "Geometric Theatricality" by Cayetano Gros — crédito no frontmatter). Per-project page em kanhan.com.br/en/prose-loop/. <!-- audit:allow operator portfolio site -->
- Shellcheck clean: 1 SC2155 fix, 2 SC2012 inline disables (ls -t sorts by mtime intencional), 1 SC2034 dead-code removido (`prev_composite` virou redundante após o comparator pass).
- Bug latente fixado durante Spec 05: `print_score_table` abortava silenciosamente sob `set -eo pipefail` quando não havia compare JSONs (commit a06154d).

### Sprint Specs 01-06 — resumo
- **01**: PII audit + redactions; `scripts/audit-scan.sh`; specs/ → .local/ (ADR 0007).
- **02**: `git init`, MIT, `.gitignore`, primeiro commit.
- **03**: Rubric externalization. EN keys default; `--rubric` flag.
- **04**: `--chapter`, `--priority-count`.
- **05**: README, CHANGELOG, examples/sample-run/. Cleanup do PT-BR rubric (era scope creep).
- **06**: shellcheck, CI mínima, tag v1.2.0, push público, release, entry no site.

### Custo total da sprint
<$3 em chamadas Anthropic (dry-runs Sonnet durante verificação Spec 03, 04, 05).

### Follow-ups (fora do escopo deste repo)
- Atualizar `portfolio-state.md` workspace-level: prose-loop muda de "paused" para "released".
- (Opcional) Branch protection no repo público, Dependabot, asciinema cast, multi-OS CI matrix.

### Ordem de execução das specs
01 ✅ → 02 ✅ → 03 ✅ → 04 ✅ → 05 ✅ → 06 ✅ — sprint completa.

## Known issues / Tech debt

### v1.1.0 → v1.2.0 break
Spec 03 muda chaves de PT-BR para EN no default rubric. JSONs em `prose_scores/` de runs antigos ficarão ilegíveis pelo novo `print_score_table`. Aceitável — output JSON é debug por-run, não artefato persistente; basta rodar de novo.

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
