require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/page')
require File.join(File.dirname(__FILE__), 'fixtures/good_thing')

# revert_to! must always create a new version with the next version number,
# also when :if_changed / :if would not create a version for a normal save.
class RevertTest < ActiveSupport::TestCase
  fixtures :pages, :pages_h, :locked_pages, :locked_pages_revisions, :authors
  set_fixture_class :pages_h => Page::Version

  def test_revert_to_current_version_with_if_changed
    page = locked_pages(:welcome)
    assert page.revert_to!(24)
    assert_new_version page, 25, reverted_from: 24
  end

  def test_revert_to_version_with_unchanged_if_changed_attribute
    page = locked_pages(:welcome)
    page.versions.find_by(version: 23).update_column(:title, page.title)
    assert page.revert_to!(23)
    assert_new_version page, 25, reverted_from: 23
  end

  def test_revert_with_false_if_condition
    Page.feeling_good = false
    page = pages(:welcome)
    assert page.revert_to!(23)
    assert_equal 'Welcome to the weblg', page.reload.title
    assert_new_version page, 25, reverted_from: 23
  ensure
    Page.feeling_good = true
  end

  def test_revert_to_current_version_without_options
    thing = GoodThing.create!(name: 'Sun')
    thing.update!(name: 'Moon')
    assert thing.revert_to!(2)
    assert_new_version thing, 3, reverted_from: 2
    assert_equal [1, 2, 3], thing.versions.order(:version).pluck(:version)
  end

  def test_revert_fails_on_validation_error_without_new_version
    thing = GoodThing.create!(name: 'Sun')
    thing.update!(name: 'Moon')
    GoodThing.create!(name: 'Sun')

    assert !thing.revert_to!(1)
    assert_equal 'Moon', GoodThing.find(thing.id).name
    assert_equal 2, GoodThing.find(thing.id).version
    assert_equal 2, thing.versions.count
  end

  private

  def assert_new_version(record, number, reverted_from:)
    assert_equal number, record.class.find(record.id).version
    numbers = record.versions.pluck(record.class.version_column)
    assert_equal numbers.uniq, numbers, 'duplicate version numbers'
    assert_equal reverted_from, record.find_version(number).record_restored_from_version
  end
end
