ActiveRecord::Schema.define(:version => 1) do
  create_table :pages, :force => true do |t|
    t.column :version, :integer
    t.column :title, :string, :limit => 255
    t.column :body, :text
    t.column :created_on, :datetime
    t.column :updated_on, :datetime
    t.column :author_id, :integer
    t.column :revisor_id, :integer
  end

  create_table :pages_h, :force => true do |t|
    t.column :page_id, :integer
    t.column :version, :integer
    t.column :title, :string, :limit => 255
    t.column :body, :text
    t.column :created_on, :datetime
    t.column :updated_on, :datetime
    t.column :author_id, :integer
    t.column :revisor_id, :integer
    t.column :deleted_in_original_table, :boolean
    t.column :record_restored, :integer, :precision => 38,  :scale => 0, :default => nil
  end
  
  add_index :pages_h, [:page_id, :version], :unique => true
  
  create_table :authors, :force => true do |t|
    t.column :page_id, :integer
    t.column :name, :string
  end
  
  create_table :locked_pages, :force => true do |t|
    t.column :lock_version, :integer
    t.column :version, :integer
    t.column :title, :string, :limit => 255
    t.column :body, :text
    t.column :type, :string, :limit => 255
  end

  create_table :locked_pages_revisions, :force => true do |t|
    t.column :page_id, :integer
    t.column :version, :integer
    #t.column :lock_version, :integer
    t.column :title, :string, :limit => 255
    t.column :body, :text
    t.column :version_type, :string, :limit => 255
    t.column :updated_at, :datetime
    t.column :deleted_in_original_table, :boolean
    t.column :record_restored, :integer, :precision => 38,  :scale => 0, :default => nil
  end
  
  add_index :locked_pages_revisions, [:page_id, :version], :unique => true

  create_table :widgets, :force => true do |t|
    t.column :name, :string, :limit => 50
    t.column :foo, :string
    t.column :version, :integer
    t.column :updated_at, :datetime
  end

  create_table :widgets_h, :force => true do |t|
    t.column :widget_id, :integer
    t.column :name, :string, :limit => 50
    t.column :version, :integer
    t.column :updated_at, :datetime
    t.column :deleted_in_original_table, :boolean
    t.column :record_restored, :integer, :precision => 38,  :scale => 0, :default => nil
  end
  
  add_index :widgets_h, [:widget_id, :version], :unique => true
  
  create_table :landmarks, :force => true do |t|
    t.column :name, :string
    t.column :latitude, :float
    t.column :longitude, :float
    t.column :doesnt_trigger_version,:string
    t.column :version, :integer
  end

  create_table :landmark_h, :force => true do |t|
    t.column :landmark_id, :integer
    t.column :name, :string
    t.column :latitude, :float
    t.column :longitude, :float
    t.column :doesnt_trigger_version,:string
    t.column :version, :integer
    t.column :deleted_in_original_table, :boolean
    t.column :record_restored, :integer, :precision => 38,  :scale => 0, :default => nil
  end
  
  add_index :landmark_h, [:landmark_id, :version], :unique => true

  # Test model for the TISS fork features (deleted_in_original_table, restore, ...), see test/tiss_test.rb
  create_table :good_things, :force => true do |t|
    t.column :name, :string, :limit => 50, :null => false
    t.column :why_good, :string, :limit => 250
    t.column :version, :integer, :default => 1
    t.timestamps
  end

  create_table :good_things_h, :force => true do |t|
    t.column :good_thing_id, :integer
    t.column :version, :integer
    t.column :name, :string, :limit => 50
    t.column :why_good, :string, :limit => 250
    t.timestamps
    t.column :deleted_in_original_table, :boolean
    t.column :record_restored, :integer, :default => nil
  end

  add_index :good_things_h, [:good_thing_id, :version], :unique => true
end
