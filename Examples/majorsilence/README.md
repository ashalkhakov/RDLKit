# Majorsilence Reporting example reports

86 `.rdl` files from [Majorsilence Reporting](https://github.com/majorsilence/Reporting)
— its `Examples/` gallery and the report definitions its `ReportTests/` suite runs
against. They are Apache 2.0; see `LICENSE` and `NOTICE`. Nothing here has been
modified.

They are kept because they are the closest thing to a conformance corpus that
exists for RDL: real reports, written against a real implementation, exercising
corners of the schema that hand-written fixtures never reach.

Every one of them is **RDL 2005 or older** — not one uses the 2010 `Tablix`
grammar RDLKit was built against:

| Namespace | Files |
| --- | --- |
| none (schema-less) | 48 |
| `.../reporting/2005/01/reportdefinition` | 37 |
| `.../reporting/2003/10/reportdefinition` | 1 |

Which is why most of them do not work yet. `../../RDL-COVERAGE.md` has the
gap analysis and the running score; regenerate it with
`.tools/rdl-coverage.sh`.
