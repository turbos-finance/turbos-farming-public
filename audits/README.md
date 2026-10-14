# Audit evidence - Turbos Farming

The original [ExVul report](exvul-farming-2026.pdf) is preserved unchanged.

| Item | Evidence |
|---|---|
| Auditor | ExVul (individual reviewer names not disclosed in the report) |
| Review period | 2026-05-23 through 2026-06-08 |
| Reviewed commit | `697b08719f8fdefadf0cbf85f3a37dcf821f0708` |
| Scope | Farming Move contracts; per-finding source paths and code snippets in chapter 3 |
| Method | Static analysis, manual verification, business-logic testing and PoC where applicable; chapters 1 and 5 |
| Findings | 12: 2 high, 4 medium, 6 low; all marked fixed by the report |

The audited source tree is published under
`source-anchors/697b08719f8fdefadf0cbf85f3a37dcf821f0708/`, excluding operational
environment files and scripts. `evidence/audit-source-provenance.json` records original
file hashes. The original private Git history is not published.

## Deployed-source delta

Deployed v1 originates from `d03cdbc79210214e98539527e33a881e21378d6a`.
Compared with the audited commit, `sources/pool.move` differs by 8 insertions and
9 deletions. The report's fixed statuses do not by themselves prove that every audited
fix is present in this deployment. A per-finding fix/test mapping and review of this delta
remain required. Tests are included; line and branch coverage has not yet been published.
