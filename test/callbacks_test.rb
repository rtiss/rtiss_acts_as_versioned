require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/audited_thing')

# Contracts the application relies on in its own callbacks:
# * attributes assigned in before_destroy end up in the deletion version
# * restoring? tells a restore apart from a normal create
class CallbacksTest < ActiveSupport::TestCase
  def setup
    AuditedThing.reset_test_state!
  end

  def teardown
    AuditedThing.reset_test_state!
  end

  def test_before_destroy_attributes_are_stored_in_deletion_version
    AuditedThing.current_user = 1
    record = AuditedThing.create!(name: 'Sun')
    assert_equal 1, record.find_version(1).changed_by

    AuditedThing.current_user = 2
    record.destroy

    deletion = AuditedThing::Version.where(audited_thing_id: record.id).ordered.last
    assert deletion.deleted_in_original_table
    assert_equal 2, deletion.version
    assert_equal 2, deletion.changed_by, 'deletion version must contain the value assigned in before_destroy'
    assert_equal 1, record.find_version(1).changed_by, 'older versions stay unchanged'
  end

  def test_restoring_is_true_in_callbacks_during_restore
    AuditedThing.current_user = 1
    record = AuditedThing.create!(name: 'Sun')
    AuditedThing.current_user = 2
    record.destroy

    AuditedThing.current_user = 3
    AuditedThing.restoring_seen_in_before_create = []
    AuditedThing.restore_deleted(record.id)

    assert_equal [true], AuditedThing.restoring_seen_in_before_create
    restored = AuditedThing.find(record.id)
    assert_equal 3, restored.changed_by, 'restored record contains the restoring user'
    assert_equal 3, restored.find_version(3).changed_by, 'version of the restore contains the restoring user'
    assert_equal 2, restored.find_version(3).record_restored_from_version
    assert_equal false, restored.restoring?, 'a freshly loaded record is not restoring'
  end

  def test_restoring_is_reset_after_restore
    record = AuditedThing.create!(name: 'Sun')
    record.destroy
    AuditedThing.restore_deleted(record.id)

    restored_instance = AuditedThing.last_validated
    assert_equal record.id, restored_instance.id
    assert_equal false, restored_instance.restoring?
  end

  def test_restoring_is_false_for_normal_create
    AuditedThing.current_user = 1
    record = AuditedThing.create!(name: 'Sun', changed_by: 9)

    assert_equal [false], AuditedThing.restoring_seen_in_before_create
    assert_equal false, record.restoring?
    assert_equal 9, record.changed_by, 'a normal create keeps an explicitly assigned value'
  end

  def test_restoring_is_reset_when_restore_fails
    record = AuditedThing.create!(name: 'Sun')
    record.destroy
    AuditedThing.reject_saves = true

    assert_raises(RuntimeError) { AuditedThing.restore_deleted(record.id) }
    assert_not AuditedThing.exists?(record.id)
    assert_equal false, AuditedThing.last_validated.restoring?
  end
end
