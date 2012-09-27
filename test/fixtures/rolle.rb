class Rolle < ActiveRecord::Base
	set_table_name 'rolle'
	acts_as_versioned

	validates_presence_of :name
	validates_uniqueness_of :name
end
