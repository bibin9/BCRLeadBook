# Data model, backup format and CSV export

## Database (SQLite, schema version 1)

| Table | Key | Purpose |
|---|---|---|
| `companies` | `id` (random 128-bit hex) | name (required), location, trivia, `rapport_notes` (general, used only when no person was selected), `quality` (hot/warm/cold/future or NULL), `target_month` (`yyyy-MM` or NULL), `created_at`, `updated_at` (epoch ms) |
| `contacts` | `id` → `company_id` (CASCADE) | name, title, phone, `phone_norm` (digits, for search), email, `notes` (= personal & rapport notes), `is_decision_maker` |
| `products` | `id` → `company_id` (CASCADE) | `line` (medical/motor/property/marine/liability/other), `custom_line`, `label`, `expiry_date` (`yyyy-MM-dd` or NULL = unknown), insurer, notes |
| `meetings` | `id` → `company_id` (CASCADE); `contact_id`, `next_contact_id` → contacts (SET NULL) | dated history; `meeting_at`, `summary` |
| `tasks` | `id` (+ integer `seq`, used as the notification id) → `company_id` (CASCADE); `contact_id`, `product_id`, `meeting_id` (SET NULL) | `action`, `due_date` (`yyyy-MM-dd`), `reminder_time` (`HH:mm` or NULL), `status` (pending/completed), `completed_at` |
| `drafts` | `key` (`new` or `co:<companyId>`) | autosaved unfinished quick-entry forms (JSON) |
| `settings` | `key` | reminder defaults etc. |

Rules worth knowing:

- `created_at` is set once and never changed by edits. `updated_at` changes whenever the company or any of its contacts, products, meetings or tasks change.
- **Target month** (company) and **follow-up date** (task) are separate fields and never overwrite each other. The company's "next follow-up" is *derived* from its earliest pending task.
- Each "Add Meeting" inserts a new `meetings` row. Rapport notes live on the contact and company context on the company, so both persist across meetings.
- Dates without a time are compared as local calendar dates; expired = before today's local date.

## Backup file (`bcr-leadbook-backup-YYYYMMDD-HHmm.json`)

```json
{
  "format": "bcr-leadbook-backup",
  "version": 1,
  "app": "BCR LeadBook",
  "created_at": "2026-10-03T08:30:00.000Z",
  "counts": {"companies": 2, "contacts": 3, "products": 4, "meetings": 5, "tasks": 3},
  "companies": [ ... ], "contacts": [ ... ], "products": [ ... ],
  "meetings": [ ... ], "tasks": [ ... ],
  "settings": {"reminder_default_time": "09:00"}
}
```

Rows use the same column names as the tables above, so IDs and relationships are preserved exactly. Restore validates: valid JSON, correct `format`, supported `version` (a newer version asks you to update the app), every record readable, no duplicate IDs, counts match, and no record points at something missing. Only then does the app ask for confirmation, and the replacement runs in one transaction (all or nothing). Drafts and machine-specific flags are not part of a backup. Backups are **not encrypted**.

When the format changes, bump `backupVersion` in `lib/data/backup_service.dart` and teach `BackupService.parse` to read the older versions.

## CSV export (Settings → Export to CSV)

One CSV cannot represent several contacts and products per company without losing data, so the export is six related files that share `company_id`. UTF-8 with byte-order mark (Excel shows non-English text correctly), comma-separated, CRLF line ends.

| File | One row per | Notable columns |
|---|---|---|
| `leads_overview.csv` | company | quality, target month, next follow-up date + action, contact/product counts, **`contacts`** and **`products`** as readable text (` \| ` between items, e.g. `Medical (Staff), expires 2027-03-15, insurer X \| Motor, expires 2027-07-20`), last meeting + summary, company context |
| `renewals.csv` | policy with a known expiry | renewal worklist, soonest first: company, line, label, expiry_date, current_insurer, **contact_name / contact_phone / contact_email** (decision-maker, else first contact) |
| `contacts.csv` | contact | company_id, company_name, name, title, phone, email, decision_maker |
| `products.csv` | policy | company_id, product_line, other_line_text, policy_label, expiry_date (blank = unknown), current_insurer, notes |
| `meetings.csv` | meeting entry | meeting_date_time, person_met, next_call_contact, meeting_summary |
| `follow_ups.csv` | task | next_action, due_date, reminder_time, status, completed_at, linked_contact, linked_product |

**Personal & rapport notes** (`contacts.csv: rapport_notes`, `leads_overview.csv: company_rapport_notes`) are included only if you tick the option; otherwise those columns are absent. Cells starting with `=` or `@` (and `+`/`-` that are not phone numbers) are prefixed with `'` so spreadsheets cannot run them as formulas.
