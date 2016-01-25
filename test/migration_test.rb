require File.join(File.dirname(__FILE__), 'abstract_unit')

if ActiveRecord::Base.connection.supports_migrations? 
  class Thing < ActiveRecord::Base
    attr_accessor :version
    acts_as_versioned
  end

  class MigrationTest < ActiveSupport::TestCase
    self.use_transactional_fixtures = false

    def test_versioned_migration
      # take 'er up
      migrations_path = File.expand_path(File.dirname(__FILE__)) + '/fixtures/migrations'
      require migrations_path + '/2_add_versioned_tables'
      ActiveRecord::Migrator.new(:up, ActiveRecord::Migrator.migrations(migrations_path), 2).run
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
end
