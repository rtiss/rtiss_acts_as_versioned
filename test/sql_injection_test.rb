require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/good_thing')

# Values passed to find_version, restore_deleted and restore_deleted_version
# often come from request params. They must be bound/cast and never end up in the SQL text.
class SqlInjectionTest < ActiveSupport::TestCase
  PAYLOAD = '999 OR 1=1'

  def setup
    @other = GoodThing.create!(name: 'Other', why_good: 'just there')
    @thing = GoodThing.create!(name: 'Sun', why_good: 'Keeps us warm')
    @thing.update!(name: 'Moon')
  end

  def test_find_version_casts_version
    assert_raises(RuntimeError) { @thing.find_version(PAYLOAD) }
    assert_equal 'Moon', @thing.find_version('2').name
  end

  def test_find_version_does_not_return_versions_of_other_records
    assert_raises(RuntimeError) { @other.find_version('2 OR 1=1') }
  end

  def test_restore_deleted_casts_id
    @thing.destroy
    # the deleted record has the highest version in the table, an injected "OR 1=1" would restore it
    assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted("0 OR 1=1") }
    assert !GoodThing.exists?(@thing.id)
  end

  def test_restore_deleted_version_casts_id_and_version
    @thing.destroy
    assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted_version(@thing.id, PAYLOAD) }
    assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted_version("0 OR 1=1", 1) }
    assert !GoodThing.exists?(@thing.id)

    GoodThing.restore_deleted_version(@thing.id.to_s, '1')
    assert_equal 'Sun', GoodThing.find(@thing.id).name
  end

  def test_restore_deleted_with_unknown_id_raises_record_not_found
    assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted(0) }
    assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted_version(0, 1) }
  end

  def test_payload_never_appears_in_sql
    @thing.destroy
    sql = capture_sql do
      assert_raises(RuntimeError) { @thing.find_version(PAYLOAD) }
      assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted(PAYLOAD) }
      assert_raises(ActiveRecord::RecordNotFound) { GoodThing.restore_deleted_version(PAYLOAD, PAYLOAD) }
    end
    assert sql.any?
    sql.each { |statement| assert_no_match(/OR 1=1/i, statement) }
  end

  private

  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql] unless payload[:name] == 'SCHEMA'
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
