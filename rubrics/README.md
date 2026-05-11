# Rubrics

A rubric is a JSON file defining the scoring dimensions, weights, and per-dimension instructions for the evaluator. `prose_loop.sh` reads one rubric per run (default `rubrics/default.json`, override via `--rubric PATH`).

## Schema

```json
{
  "name": "string",
  "version": 1,
  "dimensions": [
    {
      "key": "snake_case_identifier",
      "label": "Human-readable name",
      "short": "≤6 chars for score table header",
      "weight": 1.0,
      "description": "Instruction to the evaluator for this dimension."
    }
  ]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Identifier shown in logs. |
| `version` | int | yes | Schema version. Currently `1`. |
| `dimensions[]` | array | yes | One or more dimensions. |
| `dimensions[].key` | string | yes | Snake_case. Becomes the key in `cycle_*_eval.json`. |
| `dimensions[].label` | string | yes | Long label used in prompts. |
| `dimensions[].short` | string | yes | Short label for score table. Keep ≤6 chars. |
| `dimensions[].weight` | float | yes | Positive. Affects composite. |
| `dimensions[].description` | string | yes | Sent to the LLM as the scoring instruction. |

## Composite score

`composite = sum(score_i * weight_i) / sum(weight_i)`. Always in [1, 10]. Two rubrics with the same weight totals produce numerically comparable composites.

## Shipped rubrics

- `default.json` — 7 dimensions, English keys, tuned for commercial nonfiction. Weight sum 7.7.
- `pt-br-nonfiction.json` — same 7 dimensions in pt-BR. Same weights. Use to preserve numerical comparability with prose-loop v1.1.0 runs.

## Writing a custom rubric

Copy `default.json`, change `name`, add/remove/reweight dimensions. Validate JSON syntax. Run `bash prose_loop.sh --rubric your-rubric.json --dry-run` and verify the resulting `cycle_0_eval.json` uses your keys.

Tips:
- Keep `short` ≤6 chars or the score table will wrap.
- Descriptions should be terse instructions to a literary critic, not prose.
- Don't reuse a `key` across two dimensions — the JSON output will collide.
