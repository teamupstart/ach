# ACH — Agent Context

## Project Overview

`ach` is a Ruby gem (v0.6.4) for building and parsing NACHA-format ACH files.
It handles field ordering, alignment, padding (nines records), checksum totals,
and block counting so callers do not manage the raw 94-character fixed-width
format by hand.

The gem supports:
- Generating ACH files from scratch (PPD, CCD, CTX, and other SEC codes)
- Parsing existing ACH files (CRLF-delimited or fixed-width / no line-endings)
- Parsing bank-generated confirmation files (`ACH::ConfirmationFile`)

Owner: @teamupstart/borrower-squad. No CI configuration is present in the repo.

## Tech Stack

- **Language**: Ruby (MRI; no minimum enforced, tested with modern MRI)
- **Test framework**: RSpec 3.x
- **Task runner**: Rake
- **Dependency management**: Bundler (`Gemfile` + `ach.gemspec`)
- No linter is configured

## Development Commands

```bash
# Install dependencies
bundle install

# Run all tests (default Rake task)
bundle exec rake spec
# equivalently
bundle exec rspec

# Build the gem artifact
bundle exec rake build

# Publish (build + gem push)
bundle exec rake release

# Generate RDoc
bundle exec rake rdoc
```

RSpec options (from `.rspec`): `--profile --colour --format progress --tag focus --order rand`.
Use `:focus` tag on an example/group to run only that subset.

## Key Architecture

### Record Layer — `lib/ach/records/`

Every ACH record type is a subclass of `ACH::Records::Record`, which uses the
`ACH::FieldIdentifiers` mixin for a declarative DSL:

- `field(name, klass, stringify_lambda, default, validate)` — read/write field
  with optional formatting lambda and validation (Regexp or Proc).
- `const_field(name, value)` — constant field (record-type byte, etc.).
- `spaceless_routing_field(sym)` — convenience macro; validates `/\A\d{9}\z/`.
- `to_ach` on `Record` renders the record as a 94-character string; uppercased
  unless `record.case_sensitive = true`.
- Non-ASCII characters in string fields are silently stripped to `''` via
  `String#encode` with `invalid: :replace, undef: :replace, replace: ''`
  (constant `FieldIdentifiers::ENCODING_OPTIONS`).

Record classes and their type bytes:

| File | Class | Byte |
|------|-------|------|
| `file_header.rb` | `FileHeader` | `1` |
| `batch_header.rb` | `BatchHeader` | `5` |
| `entry_detail.rb` | `EntryDetail` (PPD/CCD) | `6` |
| `entry_detail.rb` | `CtxEntryDetail` (CTX) | `6` |
| `entry_detail.rb` | `BalancingEntryDetail` | `6` |
| `addendum.rb` | `Addendum` / `NotificationOfChange` / `Return` | `7` |
| `batch_control.rb` | `BatchControl` | `8` |
| `file_control.rb` | `FileControl` | `9` |
| `nines.rb` | `Nines` (padding) | `9999…` |

### Domain Layer

- **`ACH::ACHFile`** — top-level object. Holds a `FileHeader`, array of `Batch`
  objects, and a `FileControl`. `to_s` serialises the full file, auto-computing
  checksums, block count, and padding. Accepts a data string in the constructor
  to parse instead of build.
- **`ACH::Batch`** — holds a `BatchHeader`, array of entry objects (with addenda),
  and a `BatchControl`. `to_ach` computes debit/credit totals, entry hash, and
  auto-sets `service_class_code` (200/220/225) if not already assigned.
- **`ACH::ConfirmationFile`** — parse-only; models bank-generated confirmation
  responses. Uses `FileControlConfirmation` instead of `FileControl`.

### Transaction Code Constants (`lib/ach.rb`)

```ruby
ACH::CHECKING_CREDIT        # '22'
ACH::CHECKING_DEBIT         # '27'
ACH::CHECKING_CREDIT_PRENOTE # '23'
ACH::CHECKING_DEBIT_PRENOTE  # '28'
ACH::SAVING_CREDIT           # '32'
ACH::SAVING_DEBIT            # '37'
ACH::SAVING_CREDIT_PRENOTE   # '33'
ACH::SAVING_DEBIT_PRENOTE    # '38'
ACH::LOAN_CREDIT             # '52'
ACH::LOAN_CREDIT_PRENOTE     # '53'
ACH::SERVICE_CLASS_CODES     # [200, 220, 225, 280]
ACH::DEFAULT_EOL             # "\r\n"
```

`EntryDetail#credit?` / `#debit?` are determined by the second digit of
`transaction_code`: digits 0-4 are credits, 5-9 are debits.

### Parsing

`ACHFile.new(string)` auto-detects format:
- If the string contains `\n` or `\r\n` it calls `parse(data)` (line-delimited).
- Otherwise it calls `parse_fixed(data)` which slices into 94-char chunks first.

## Important File Locations

```
lib/
  ach.rb                          # Entry point, constants, all requires
  ach/
    ach_file.rb                   # ACHFile (build + parse)
    batch.rb                      # Batch
    confirmation_file.rb          # ConfirmationFile (parse-only)
    field_identifiers.rb          # DSL mixin for field declarations
    string_formatting_helper.rb   # Same-day ACH date formatting (SD format)
    errors.rb                     # ACH::InvalidError, ACH::UnrecognizedTypeCode
    version.rb                    # ACH::VERSION
    records/
      record.rb                   # Base Record class
      entry_detail.rb             # EntryDetail, CtxEntryDetail, BalancingEntryDetail
      addendum.rb                 # Addendum, NotificationOfChange, Return
      batch_header.rb             # BatchHeader
      batch_control.rb            # BatchControl
      file_header.rb              # FileHeader
      file_control.rb             # FileControl
      file_control_confirmation.rb
      nines.rb                    # Padding record

spec/
  spec_helper.rb
  support/fields/                 # Shared examples for field validations
  support/records/                # Shared batch summary helpers
  ach/
    fixtures/                     # Sample ACH text files (return_noc.txt, etc.)
    records/                      # Per-record-type specs
    parse_spec.rb                 # Round-trip parse tests
    ach_file_spec.rb
    batch_spec.rb
```

## Conventions and Gotchas

- Amounts are always in **cents** (integers), not dollars.
- Routing numbers must be exactly 9 digits (`/\A\d{9}\z/`).
- `originating_dfi_identification` is 8 digits — the leading 8 digits of the
  15-digit ACH trace number.
- Trace numbers are 7-digit integers; assign them manually after adding all
  entries: `batch.entries.each.with_index(1) { |e, i| e.trace_number = i }`.
- Batch numbers auto-increment from the file index (1-based) if not set.
- `company_descriptive_date` accepts a `Date`, `DateTime`, or same-day ACH
  string in `SDHHMM` format (e.g., `"SD1300"`).
- `company_identification` strips a leading `1` on parse; use
  `full_company_identification` to preserve a leading `1` for non-EIN IDs.
- `service_class_code` on `BatchHeader`/`BatchControl` is auto-calculated by
  `Batch#to_ach` if left nil: 200 (mixed), 220 (credits only), 225 (debits only).
- `ACHFile#to_s` must be called before inspecting computed control fields
  (entry hash, totals, block count) as they are set during serialisation.
- The `BalancingEntryDetail` last entry in a batch causes `BatchControl` to use
  that entry's amount for both debit and credit totals (offset/balanced file).
