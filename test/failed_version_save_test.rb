require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/good_thing')

# Test hook: versions named 'Forbidden' are invalid. Only affects records with exactly this name.
GoodThing::Version.validate do
  errors.add(:name, 'must not be Forbidden') if name == 'Forbidden'
end

# If the version record can't be saved, the save/destroy/restore of the original record must fail and be rolled back.
class FailedVersionSaveTest < ActiveSupport::TestCase
  def test_create_raises_and_rolls_back
    count = GoodThing.count
    error = assert_raises(ActiveRecord::RecordNotSaved) { GoodThing.create(name: 'Forbidden') }
    assert_match(/must not be Forbidden/, error.message)
    assert_kind_of GoodThing::Version, error.record
    assert_equal count, GoodThing.count
  end

  def test_update_raises_and_rolls_back
    thing = GoodThing.create!(name: 'Sun')
    assert_raises(ActiveRecord::RecordNotSaved) { thing.update(name: 'Forbidden') }
    # after the rollback the in-memory object is stale (Rails behaviour), so use a fresh one
    assert_raises(ActiveRecord::RecordNotSaved) { GoodThing.find(thing.id).update!(name: 'Forbidden') }
    assert_equal 'Sun', GoodThing.find(thing.id).name
    assert_equal 1, thing.versions.count
  end

  def test_save_without_revision_is_not_affected
    thing = GoodThing.create!(name: 'Sun')
    thing.name = 'Forbidden'
    assert thing.save_without_revision
    assert_equal 'Forbidden', GoodThing.find(thing.id).name
  end

  def test_destroy_raises_and_rolls_back
    thing = GoodThing.create!(name: 'Sun')
    thing.name = 'Forbidden'
    thing.save_without_revision
    assert_raises(ActiveRecord::RecordNotSaved) { thing.destroy }
    assert GoodThing.exists?(thing.id)
    assert_equal 1, thing.versions.count
  end

  def test_restore_raises_and_rolls_back
    thing = GoodThing.create!(name: 'Sun')
    thing.destroy
    deleted_version = thing.find_version(2)
    deleted_version.update_column(:name, 'Forbidden')

    assert_raises(ActiveRecord::RecordNotSaved) { GoodThing.restore_deleted(thing.id) }
    assert !GoodThing.exists?(thing.id)
    assert_equal 2, GoodThing::Version.where(good_thing_id: thing.id).count
  end
end
