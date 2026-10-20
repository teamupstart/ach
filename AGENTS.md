# ACH — Agent Context

## Project Overview

Ruby gem (`ach`, v0.6.4) for building and parsing NACHA-format ACH files. It handles
field ordering, alignment, padding (nines lines), and checksum totals so callers do
not have to manage the raw 94-character fixed-width format by hand.

The gem supports both generating ACH files from scratch and parsing existing ACH files
(fixed-width or line-delimited).

## Tech Stack

- **Language**: Ruby (no minimum version enforced, but tested with modern MRI)
- **Test framework**: RSpec 3.x
- **Build / task runner**: Rake
- **Dependency management**: Bundler (`Gemfile` + `ach.gemspec`)

## Development Commands

```bash
# Install dependencies
bundle install

# Run all tests (default Rake task)
bundle exec rake spec
# or equivalently
bundle exec rspec

# Build the gem
bundle exec rake build

# Generate RDoc
bundle exec rake rdoc

# Release (build + gem push)
bundle exec rake release
```

There is no linter configured in the repo. No CI configuration file is present.

## Key Architecture

### Record Layer (`lib/ach/records/`)

Every ACH record type is a subclass of `ACH::Records::Record`, which extends
`ACH::FieldIdentifiers` to get a DSL for declaring fields:

- `field(name, klass, stringify_lambda, default, validate)` — declares a read/write
  field with optional formatting lambda and validation (Regexp or Proc).
- `const_field(name, val)` — declares a constant field (record-type bytes, etc.).
- `to_ach` — renders the record as a 94-character string; output is uppercased unless
  `case_sensitive = true`.

Record classes:

| File | Class | Record type byte |
|------|-------|-----------------|
| `file_header.rb` | `FileHeader` | `1` |
| `batch_header.rb` | `BatchHeader` | `5` |
| `entry_detail.rb` | `EntryDetail` | `6` |
| `entry_detail.rb` | `CtxEntryDetail` | `6` (CTX SEC) |
| `entry_detail.rb` | `BalancingEntryDetail` | `6` (offset entry) |
| `addendum.rb` | `Addendum` / `NotificationOfChange` / `Return` | `7` |
| `batch_control.rb` | `BatchControl` | `8` |
| `file_control.rb` | `FileControl` | `9` |
| `nines.rb` | `Nines` | `9999…` (padding) |

### Domain Layer

- **`ACH::ACHFile`** (`lib/ach/ach_file.rb`) — top-level object. Holds a `FileHeader`,
  array of `Batch` objects, and a `FileControl`. `to_s` serialises the whole file,
  auto-computing checksums, block count, and padding. `parse` / `parse_fixed` populate
  the object from an existing ACH string.
- **`ACH::Batch`** (`lib/ach/batch.rb`) — holds a `BatchHeader`, array of entry
  objects (with addenda), and a `BatchControl`. `to_ach` computes debit/credit totals
  and entry hash, and auto-sets `service_class_code` if not already set.

### Constants (`lib/ach.rb`)

Transaction codes are exposed as module constants:

```ruby
ACH::CHECKING_CREDIT       # '22'
ACH::CHECKING_DEBIT        # '27'
ACH::SAVING_CREDIT         # '32'
ACH::SAVING_DEBIT          # '37'
ACH::LOAN_CREDIT           # '52'
# …and prenote variants
```

`ACH::DEFAULT_EOL` is `"\r\n"` (CRLF) per NACHA spec.

### Encoding

Non-ASCII characters in string fields are silently stripped to empty string via
`String#encode` with `:invalid => :replace, :undef => :replace, :replace => ''`.

## Important File Locations

```
lib/
  ach.rb                         # Entry point, constants, requires
  ach/
    ach_file.rb                  # ACHFile class (build + parse)
    batch.rb                     # Batch class
    field_identifiers.rb         # DSL mixin for field declarations
    records/
      record.rb                  # Base Record class
      entry_detail.rb            # EntryDetail, CtxEntryDetail, BalancingEntryDetail
      addendum.rb                # Addendum + NOC/Return subclasses
      batch_header.rb
      batch_control.rb
      file_header.rb
      file_control.rb
      nines.rb                   # Padding record
    string_formatting_helper.rb
    errors.rb                    # ACH::InvalidError
    version.rb
spec/
  ach/
    fixtures/                    # Sample ACH text files used in parse specs
    records/                     # Per-record-type specs
    parse_spec.rb                # Round-trip parse tests
    ach_file_spec.rb
    batch_spec.rb
```

## Conventions

- Amounts are always in **cents** (integers), not dollars.
- Routing numbers must be exactly 9 digits (validated by `/\A\d{9}\z/`).
- Trace numbers are 7-digit integers; `originating_dfi_identification` is the leading
  8 digits of the full 15-digit trace number.
- When building a file, assign trace numbers manually after adding all entries
  (`batch.entries.each.with_index(1) { |e, i| e.trace_number = i }`).
- `company_descriptive_date` accepts a `Date`, a `DateTime`, or a same-day ACH string
  in `SDHHMM` format.
- `full_company_identification` preserves a leading `1` prefix that `company_identification`
  strips (relevant for non-EIN identifiers).
