class Widget < ActiveRecord::Base
  acts_as_versioned :sequence_name => 'widgets_seq', :association_options => {
    :order => 'version desc' # Don't nullify the foreign key column when deleting the original record! :dependent => :nullify option removed
  }
  non_versioned_columns << 'foo'
end