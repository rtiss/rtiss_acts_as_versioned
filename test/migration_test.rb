require File.join(File.dirname(__FILE__), 'abstract_unit')
require File.join(File.dirname(__FILE__), 'fixtures/migrations/2_add_versioned_tables')

class Thing < ActiveRecord::Base
  attr_accessor :version
  acts_as_versioned
end

class MigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    # make the test repeatable (the sqlite db file survives between runs)
    ActiveRecord::Base.connection.drop_table :things_h, if_exists: true
    ActiveRecord::Base.connection.drop_table :things, if_exists: true
  end

  def test_versioned_migration
    AddVersionedTables.new.migrate(:up)
    t = Thing.create :title => 'blah blah', :price => 123.45, :type => 'Thing'
    assert_equal 1, t.versions.size

    # check that the price column has remembered its value correctly
    assert_equal t.price,  t.versions.first.price
    assert_equal t.title,  t.versions.first.title

    # make sure that the precision of the price column has been preserved
    assert_equal 7, Thing::Version.columns.find{|c| c.name == "price"}.precision
    assert_equal 2, Thing::Version.columns.find{|c| c.name == "price"}.scale
  end
end
