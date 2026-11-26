# rtiss_acts_as_versioned

Simple versioning for ActiveRecord models. Every change to a record is saved as a
copy in a separate history table.

This is a fork of [technoweenie/acts_as_versioned](https://github.com/technoweenie/acts_as_versioned)
(Rick Olson, 2005), used by [TISS](https://tiss.tuwien.ac.at) (TU Wien). It adds a few changes on top
of the original. The most important one: **destroyed records stay in the history table and can be
restored.**

> **Note:** These changes were made for the needs of TISS only. The gem is used and tested only with
> **Oracle** (via `activerecord-oracle_enhanced-adapter`) and **SQLite**. Other databases may work,
> but we do not support them. If you need a general-purpose versioning gem, consider the original
> or one of the actively maintained alternatives.

| Gem version | Rails          | Ruby      |
|-------------|----------------|-----------|
| 0.9.x       | 4.x – 6.x      | 2.x       |
| 0.10.x      | >= 7.1 (activerecord >= 7.1.6) | >= 3.1.6 |

## Installation

```ruby
# Gemfile
gem 'rtiss_acts_as_versioned', '~> 0.10.2'
```

---

## Differences from the original acts_as_versioned

If you know the original gem, these are the changes in the TISS fork.

### 1. History tables use the `_h` suffix

| | Original | TISS fork |
|---|---|---|
| Default table of the version model | `page_versions` | `pages_h` (`"#{table_name}_h"`) |
| Version class | `Page::Version` | `Page::Version` (unchanged) |

You can still change both with `:table_name` and `:class_name`.

### 2. Destroyed records stay in the history (`deleted_in_original_table`)

In the original gem, `destroy` also deleted all versions (`:dependent => :delete_all`).
In this fork:

* the `versions` association has **no** `:dependent` option, so versions survive `destroy`;
* an `after_destroy` callback (`set_deleted_flag`) writes **one more version**
  (`highest_version + 1`) with `deleted_in_original_table = true`. The record's last state
  is therefore always kept;
* `:association_options => { :dependent => :nullify }` is **forbidden** and raises an error,
  because it would leave orphaned versions behind.

Note: `delete` / `delete_all` skip callbacks, so they do **not** create a deletion version.

### 3. Restoring destroyed records

New methods let you bring a destroyed record back from its history:

* `Version#restore` – restores the original record from this version (with the **same `id`**)
* `Model.restore_deleted(id)` – restores from the newest version
* `Model.restore_deleted_version(id, version)` – restores from a specific version
* `Version#original_record_exists?` – checks whether the original record still exists

A restore always creates a **new** version. That version stores, in the `record_restored`
column, which version the record was restored from.

### 4. `record_restored` column

The column holds the version number the record was restored from (`restore`) or reverted to
(`revert_to!`). It is `nil` for normal changes.

* `Version#record_restored?` / `Version#record_restored` → `true`/`false`
* `Version#record_restored_from_version` → `Integer` or `nil`

### 5. Version numbers only ever go up

In the original, `revert_to!(3)` set the record back to version number 3 and did not create a
new version. In the fork:

* `revert_to!(n)` copies the data from version `n` and saves it as a **new version**
  (`max + 1`), with `record_restored = n`. This also applies when `:if` / `:if_changed` would
  not create a version for a normal save. If the record can't be saved (validation), `revert_to!`
  returns `false` and no version is written;
* `restore` also always gives the record a new, higher version number;
* the version column is **always separate from `lock_version`**. Do not set
  `:version_column => 'lock_version'`. Optimistic locking and versioning work side by side.

The history therefore has no gaps and is append-only (an audit trail).

### 6. Extra lookup methods on the instance

* `find_version(n)` – returns version `n`. Raises a `RuntimeError` if it does not exist.
* `find_newest_version` – returns the newest version, including a deletion version.
* `highest_version` – the highest version number, or `-1` if there is none or the record is unsaved.

### 7. Other changes

* `:non_versioned_columns` option to exclude columns directly in the `acts_as_versioned` call.
* `:deleted_in_original_table_flag` and `:record_restored_column` options to rename the extra columns.
* `updated_at` on a version is set to `Time.now` when it is saved.
* `save_without_revision(perform_validation = true)` lets you skip validation.
* `create_versioned_table` also creates the `deleted_in_original_table` and
  `record_restored` columns.
* The `belongs_to` from the version to the original model is `optional: true`
  (the original may already be gone).

---

## Quick start

### 1. Migration

The main table needs a `version` column (integer). The history table holds the foreign key,
`version`, the two fork columns and every column you want versioned.

Easiest way, with the built-in helper:

```ruby
class AddVersioningToPages < ActiveRecord::Migration[7.1]
  def up
    Page.create_versioned_table   # creates pages_h (and pages.version if missing)
  end

  def down
    Page.drop_versioned_table
  end
end
```

Or by hand:

```ruby
create_table :pages do |t|
  t.string  :title
  t.text    :body
  t.integer :version
  t.integer :lock_version, default: 0   # optional, for optimistic locking
  t.timestamps
end

create_table :pages_h do |t|
  t.integer :page_id                       # foreign key to the original
  t.integer :version
  t.string  :title
  t.text    :body
  t.timestamps
  t.boolean :deleted_in_original_table, default: false
  t.integer :record_restored                # nil, or a version number
end
add_index :pages_h, [:page_id, :version], unique: true
```

> `create_versioned_table` reads the columns from the model, so the main table must exist first.
> If you change the schema later, you have to update the `_h` table yourself, and restart the app:
> the version class reads its columns only once.

### 2. Model

```ruby
class Page < ApplicationRecord
  acts_as_versioned
end
```

### 3. Creating and changing records

```ruby
page = Page.create!(title: 'Hello')
page.version            # => 1
page.versions.count     # => 1

page.update!(title: 'Hello World')
page.version            # => 2

page.update!(title: 'Hello World')   # nothing changed, so no new version
page.version            # => 2
```

### 4. Reading versions

```ruby
page.versions                          # all versions (has_many, Page::Version)
page.versions.earliest                 # first version
page.versions.latest                   # newest version
page.versions.where(title: 'Hello')    # works like any normal relation

page.find_version(1).title             # => 'Hello'
page.find_version(99)                  # => RuntimeError
page.find_newest_version.version       # => 2
page.highest_version                   # => 2

v = page.find_version(2)
v.previous                             # version 1
v.next                                 # nil
v.page                                 # the original record (nil if destroyed)
```

### 5. Reverting to an older version

```ruby
page.revert_to(1)       # changes attributes in memory only, does not save
page.revert_to!(1)      # saves it as a NEW version
page.version            # => 3
page.title              # => 'Hello'
page.find_version(3).record_restored_from_version  # => 1
```

### 6. Destroying and restoring

```ruby
id = page.id
page.destroy
Page.exists?(id)                         # => false

v = Page::Version.where(page_id: id).order(:version).last
v.version                                # => 4
v.deleted_in_original_table              # => true
v.original_record_exists?                # => false

Page.restore_deleted(id)                 # restore from the newest version
# or: Page.restore_deleted_version(id, 2)  # restore from version 2
# or: v.restore

page = Page.find(id)                     # same id as before
page.version                             # => 5
page.find_version(5).record_restored     # => true
```

`restore` raises a `RuntimeError` if the original record still exists.

If a version record can't be saved (e.g. a validation on the versioned class fails), `save`, `save!`,
`destroy` and `restore` raise `ActiveRecord::RecordNotSaved` (with the version as `error.record`)
and the change to the original record is rolled back.

### 7. Saving without a new version

```ruby
page.title = 'Typo fix'
page.save_without_revision               # saves, no new version
page.save_without_revision(false)        # same, but skips validation

Page.without_revision do
  Page.find(id).update!(title: 'Silent')
end
```

`without_revision` disables versioning for the class and its subclasses. `without_locking` disables
optimistic locking for all models. Both only affect the current thread (or fiber, depending on
`config.active_support.isolation_level`) and may be nested. `Page.without_revision?` tells you
whether you are inside such a block. `ActiveRecord::Base.lock_optimistically` itself is not
changed by `without_locking`.

### 8. Options

```ruby
class Page < ApplicationRecord
  acts_as_versioned \
    table_name:            :page_history,       # default: pages_h
    class_name:            'Revision',          # default: Version  -> Page::Revision
    foreign_key:           :page_id,            # default: page_id
    version_column:        :version,            # never use :lock_version!
    non_versioned_columns: [:view_count],       # these columns are not versioned
    if_changed:            [:title, :body],     # new version only if one of these changed
    if:                    :versionable?,       # Symbol or Proc(record) -> true/false
    limit:                 50,                  # keep at most N versions (older ones are deleted!)
    sequence_name:         'page_history_seq',  # e.g. for Oracle
    association_options:   { order: 'version' },
    extend:                PageVersionHelpers   # module mixed into Page and Page::Revision
end
```

Columns that are never versioned: primary key, `type` (STI), the version column,
`lock_version` and `versioned_type`. For STI models the `type` value is stored in
`versioned_type` (see `:inheritance_column`).

> ⚠️ `:limit` deletes old versions with `delete_all`. That also removes their deletion and
> restore information. In an audit setting you usually should not use it.

---

## Tests

```sh
bundle exec rake test
```

The tests run against SQLite (`test/database.yml`).

* `test/versioned_test.rb` – the original acts_as_versioned tests, adapted to the fork's behaviour
* `test/tiss_test.rb` – the fork features (destroy, restore, `record_restored`, `find_version`, …),
  using the test model `GoodThing` (`name`, `why_good`), e.g. `GoodThing.create!(name: 'Sun', why_good: 'Keeps us warm')`
* `test/migration_test.rb` – `create_versioned_table`

## Release

```sh
rake build     # updates the gemspec manifest and builds pkg/*.gem
rake release   # commit, tag, push, gem push
```

## Resources

* RubyGems: https://rubygems.org/gems/rtiss_acts_as_versioned
* GitHub (fork): https://github.com/rtiss/rtiss_acts_as_versioned
* Original: https://github.com/technoweenie/acts_as_versioned

## License

MIT, see [MIT-LICENSE](MIT-LICENSE).
