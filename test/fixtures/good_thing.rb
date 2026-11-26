# Test model for the TISS fork features, e.g.
#   GoodThing.create!(name: 'Sun', why_good: 'Keeps us warm')
class GoodThing < ActiveRecord::Base
  acts_as_versioned

  validates_presence_of :name
  validates_uniqueness_of :name
end
