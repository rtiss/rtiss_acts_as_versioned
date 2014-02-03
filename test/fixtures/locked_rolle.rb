# Same as Rolle except for the presence of the lock_version field
class LockedRolle < ActiveRecord::Base
  set_table_name 'locked_rolle'
	acts_as_versioned

	validates_presence_of :name
	validates_uniqueness_of :name
end
