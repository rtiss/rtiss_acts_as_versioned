require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/good_thing')

# Tests for the features added by the TISS fork:
# deleted_in_original_table, restore, record_restored, find_version, find_newest_version, highest_version.
#
# Based on test/models/tools/acts_as_versioned_test.rb in the TISS main project,
# but using the gem's own test model GoodThing.
class TissTest < ActiveSupport::TestCase
  def test_versioning
    count = GoodThing.count

    oid1 = create_object('Sun').id
    oid2 = create_object('Rain').id
    oid3 = create_object('Coffee').id
    oid4 = create_object('Music').id
    oid5 = create_object('Sleep').id

    assert_equal count + 5, GoodThing.count

    2.upto(5) { |index| edit_object(oid1, "Sun#{index}") }
    2.upto(7) { |index| edit_object(oid2, "Rain#{index}") }
    2.upto(9) { |index| edit_object(oid3, "Coffee#{index}") }
    2.upto(6) { |index| edit_object(oid4, "Music#{index}") }
    2.upto(3) { |index| edit_object_with_sleep(oid5, "Sleep#{index}") }

    assert versions_correct?(oid1, 5)
    assert versions_correct?(oid2, 7)
    assert versions_correct?(oid3, 9)
    assert versions_correct?(oid4, 6)

    assert timestamps?(oid1)
    assert timestamps?(oid2)
    assert timestamps?(oid3)
    assert timestamps?(oid4)
    assert strong_timestamps?(oid5)

    destroy_record(oid2)
    assert record_unavailable_in_original_table?(oid2)
    assert deleted_record_versioned?(oid2, 8)

    restore_record(oid2)
    assert restored_record_available_in_original_table?(oid2)
    assert restored_record_versioned?(oid2, 9)

    assert save_record_without_changes(oid1)
  end

  def test_all_versioned_attributes_are_copied
    object = GoodThing.create!(name: 'Sun', why_good: 'Keeps us warm')
    object.update!(why_good: 'Makes plants grow')

    assert_equal 'Keeps us warm', object.find_version(1).why_good
    assert_equal 'Makes plants grow', object.find_version(2).why_good
    assert_equal 'Sun', object.find_version(2).name
  end

  def test_deleted_in_original_table
    record = create_object('Friends')
    version_record = record.versions.first
    assert_not_nil version_record

    assert !version_record.deleted_in_original_table
    record.destroy

    version_record = record.find_newest_version
    assert_not_nil version_record
    assert_equal 2, version_record.version
    assert version_record.deleted_in_original_table
  end

  def test_find_versions
    object = create_object("Books")
    versions = object.versions
    assert_equal 1, versions.count
    assert_equal "Books", versions[0].name

    edit_object(object.id, "Libraries")
    versions.reload

    assert_equal 2, versions.count
    assert_equal "Books", versions[0].name
    assert_equal "Libraries", versions[1].name

    versions = object.versions.where(name: 'Libraries')
    assert_equal 1, versions.count
    assert_equal "Libraries", versions[0].name

    assert_equal "Books", object.versions.first.name
    assert_equal "Libraries", object.versions.last.name

    versions = object.versions.order("name desc")
    assert_equal 2, versions.count
    assert_equal "Libraries", versions[0].name
    assert_equal "Books", versions[1].name

    # mind the missing s
    assert_equal "Books", object.find_version(1).name
    assert_equal "Libraries", object.find_version(2).name

    assert_raises(RuntimeError) { object.find_version(3) }

    assert_equal "Libraries", object.find_newest_version.name
  end

  def test_restore
    object = create_object("Trees")
    version = object.find_version(1)

    assert_raises(RuntimeError) { version.restore }
    assert !version.deleted_in_original_table

    object.destroy
    version = object.find_newest_version
    assert version.deleted_in_original_table

    version.restore
    version = object.find_newest_version
    assert !version.deleted_in_original_table
    assert version.record_restored?
    assert_equal 2, version.record_restored_from_version
  end

  def test_original_record_exists
    object = create_object("Bicycles")
    version = object.find_version(1)
    assert version.original_record_exists?

    object.destroy
    assert !version.original_record_exists?

    version.restore
    assert version.original_record_exists?
  end

  def test_restore_deleted
    object = create_object("Holidays")
    oid = object.id
    version = object.find_version(1)

    assert_raises(RuntimeError) { restore_record(oid) }
    assert !version.deleted_in_original_table

    object.destroy
    version = object.find_version(2)
    assert version.deleted_in_original_table

    restore_record(oid)
    version = object.find_version(3)
    assert !version.deleted_in_original_table
  end

  def test_restore_deleted_version
    object = GoodThing.create!(name: 'Sun', why_good: 'Keeps us warm')
    oid = object.id

    edit_object(oid, "Moon")
    assert_equal "Moon", GoodThing.find(oid).name

    assert_not_nil object.find_version(2)
    object.destroy

    version = object.find_version(3)
    assert version.deleted_in_original_table

    GoodThing.restore_deleted_version(oid, 1)
    restored = GoodThing.find(oid)
    assert_equal "Sun", restored.name
    assert_equal "Keeps us warm", restored.why_good
    assert_equal 4, restored.version
    assert_equal 1, restored.find_version(4).record_restored_from_version
  end

  # the new version number must come from the highest version, not from the version row with the highest id
  def test_restore_uses_highest_version_not_highest_id
    object = create_object('Stars')
    edit_object(object.id, 'Planets')
    object.destroy
    # e.g. an old version imported later: highest id, low version number
    GoodThing::Version.create!(good_thing_id: object.id, version: 0, name: 'Imported')

    GoodThing.restore_deleted_version(object.id, 2)
    assert_equal 4, GoodThing.find(object.id).version
    assert_equal [0, 1, 2, 3, 4], GoodThing::Version.where(good_thing_id: object.id).order(:version).pluck(:version)
  end

  def test_destroy_unsaved_record
    object = GoodThing.new(name: "Never saved")
    assert_nothing_raised { object.destroy }
    assert_equal(-1, object.highest_version)
  end

  private

  def create_object(name)
    GoodThing.create!(name: name, why_good: "#{name} is good")
  end

  def edit_object(id, name)
    GoodThing.find(id).update!(name: name)
  end

  def edit_object_with_sleep(id, name)
    sleep(2)
    GoodThing.find(id).update!(name: name)
  end

  def versions_correct?(id, highest_version)
    versions = GoodThing.find(id).versions
    1.upto(highest_version) do |current_version|
      current_version_record = versions.find_by(version: current_version)
      return false if current_version_record.nil? || current_version_record.deleted_in_original_table == true
    end
    versions.size == highest_version
  end

  # updated_at must never go backwards from one version to the next
  def timestamps?(id)
    versions = GoodThing.find(id).versions
    versions.size.downto(2) do |version|
      current_version = versions.find_by(version: version)
      predecessor_version = versions.find_by(version: version - 1)
      return false if current_version.updated_at < predecessor_version.updated_at
    end
    true
  end

  # with a pause between the edits: created_at is copied from the original record and stays the same,
  # updated_at must differ between versions
  def strong_timestamps?(id)
    versions = GoodThing.find(id).versions
    versions.size.downto(2) do |version|
      current_version = versions.find_by(version: version)
      predecessor_version = versions.find_by(version: version - 1)
      return false if current_version.updated_at == predecessor_version.updated_at ||
                      current_version.created_at != predecessor_version.created_at
    end
    true
  end

  def destroy_record(id)
    GoodThing.destroy(id)
  end

  def record_unavailable_in_original_table?(id)
    !GoodThing.exists?(id: id)
  end

  def deleted_record_versioned?(id, highest_version)
    deleted = GoodThing::Version.find_by(version: highest_version, good_thing_id: id)
    deleted != nil && deleted.deleted_in_original_table == true
  end

  def restore_record(id)
    GoodThing.restore_deleted(id)
  end

  def restored_record_available_in_original_table?(id)
    GoodThing.exists?(id: id)
  end

  def restored_record_versioned?(id, version_of_restored_record)
    restored = GoodThing.find(id).versions.find_by(version: version_of_restored_record)
    restored != nil && !restored.deleted_in_original_table
  end

  def save_record_without_changes(id)
    versions_before_save = GoodThing.find(id).versions.count
    record = GoodThing.find(id)
    record.update(name: record.name)
    versions_after_save = GoodThing.find(id).versions.count
    versions_before_save == versions_after_save
  end
end
