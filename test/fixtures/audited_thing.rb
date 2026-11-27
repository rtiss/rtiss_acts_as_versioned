# Test model for application callbacks on destroy and restore, see test/callbacks_test.rb.
# Mimics an application that records who changed a record (changed_by), similar to a mutator/user id column:
#   AuditedThing.current_user = 42
#   AuditedThing.create!(name: 'Sun')   # changed_by => 42
class AuditedThing < ActiveRecord::Base
  acts_as_versioned

  # the "logged-in user" of the application
  cattr_accessor :current_user
  # restoring? as seen by each before_create callback, in call order
  cattr_accessor :restoring_seen_in_before_create, default: []
  # makes every validation fail, to test a failing restore
  cattr_accessor :reject_saves, default: false
  # the last instance that was validated (the restored record is not returned by Version#restore)
  cattr_accessor :last_validated

  validates_presence_of :name
  validate { errors.add(:base, 'rejected') if reject_saves }
  before_validation { self.class.last_validated = self }

  before_create do
    restoring_seen_in_before_create << restoring?
    # a normal create keeps an explicitly assigned value, a restore records the restoring user
    self.changed_by = current_user if changed_by.nil? || restoring?
  end

  # in memory only: the deletion version is built from this state
  before_destroy { self.changed_by = current_user }

  def self.reset_test_state!
    self.current_user = nil
    self.restoring_seen_in_before_create = []
    self.reject_saves = false
    self.last_validated = nil
  end
end
