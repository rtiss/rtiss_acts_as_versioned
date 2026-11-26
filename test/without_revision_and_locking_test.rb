require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/good_thing')
require File.join(File.dirname(__FILE__), 'fixtures/page')

# without_revision and without_locking must only affect the current thread and must be nestable.
class WithoutRevisionAndLockingTest < ActiveSupport::TestCase
  fixtures :locked_pages, :locked_pages_revisions

  def test_without_revision_suppresses_versions
    thing = GoodThing.create!(name: 'Sun')
    GoodThing.without_revision { thing.update!(name: 'Moon') }
    assert_equal 1, thing.versions.count
    assert_equal 'Moon', thing.reload.name
  end

  def test_nested_without_revision_restores_versioning
    thing = GoodThing.create!(name: 'Sun')
    GoodThing.without_revision do
      GoodThing.without_revision { thing.update!(name: 'Moon') }
      assert GoodThing.without_revision?
      thing.save_without_revision
    end
    assert !GoodThing.without_revision?

    thing.update!(name: 'Stars')
    assert_equal 2, thing.versions.count
  end

  def test_without_revision_is_reset_after_exception
    thing = GoodThing.create!(name: 'Sun')
    assert_raises(RuntimeError) do
      GoodThing.without_revision { raise 'oh noes' }
    end
    assert !GoodThing.without_revision?

    thing.update!(name: 'Moon')
    assert_equal 2, thing.versions.count
  end

  def test_without_revision_only_affects_the_given_class_and_subclasses
    Page.without_revision do
      assert Page.without_revision?
      assert !GoodThing.without_revision?
    end
    LockedPage.without_revision do
      assert SpecialLockedPage.without_revision?
    end
    SpecialLockedPage.without_revision do
      assert !LockedPage.without_revision?
    end
  end

  def test_without_revision_does_not_affect_other_threads
    assert_equal [true, false], in_block_and_other_thread(GoodThing.method(:without_revision)) { GoodThing.without_revision? }
  end

  def test_without_locking_does_not_affect_other_threads
    assert_equal [false, true], in_block_and_other_thread(LockedPage.method(:without_locking)) { !!LockedPage.locking_enabled? }
  end

  def test_without_locking_allows_saving_stale_records
    page = LockedPage.find(locked_pages(:welcome).id)
    stale = LockedPage.find(page.id)
    page.update!(title: 'fresh')

    stale.title = 'stale'
    assert_raises(ActiveRecord::StaleObjectError) { stale.save! }

    LockedPage.without_locking { stale.save! }
    assert_equal 'stale', page.reload.title
  end

  private

  # Calls the check inside the block (in this thread) and in a second thread while the block is still running.
  # The second thread does not touch the database.
  def in_block_and_other_thread(wrapper, &check)
    inside = nil
    other = nil
    wrapper.call do
      inside = check.call
      other = Thread.new { check.call }.value
    end
    [inside, other]
  end
end
