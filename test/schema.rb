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

  create_table "rolle", :force => true do |t|
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "version",                             :precision => 38, :scale => 0, :default => 1
    t.integer  "mutator_id",                          :precision => 38, :scale => 0, :default => 0
    t.string   "name",                :limit => 50,                                                    :null => false
    t.string   "beschreibung",        :limit => 250
    t.integer  "parent_id",                           :precision => 38, :scale => 0
    t.string   "beschreibung_intern", :limit => 4000
    t.string   "geltungsbereich",     :limit => 1000
    t.string   "vergaberichtlinien",  :limit => 4000
    t.boolean  "ist_delegierbar",                     :precision => 1,  :scale => 0, :default => true
  end

  create_table "rolle_h", :force => true do |t|
    t.integer  "rolle_id",                                  :precision => 38, :scale => 0
    t.integer  "version",                                   :precision => 38, :scale => 0
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "mutator_id",                                :precision => 38, :scale => 0
    t.string   "name",                      :limit => 50
    t.string   "beschreibung",              :limit => 250
    t.boolean  "deleted_in_original_table",                 :precision => 1,  :scale => 0
    t.integer  "record_restored",                           :precision => 38,  :scale => 0, :default => nil
    t.integer  "parent_id",                                 :precision => 38, :scale => 0
    t.string   "beschreibung_intern",       :limit => 4000
    t.string   "geltungsbereich",           :limit => 1000
    t.string   "vergaberichtlinien",        :limit => 4000
    t.boolean  "ist_delegierbar",                           :precision => 1,  :scale => 0, :default => true
  end

  create_table "locked_rolle", :force => true do |t|
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "version",                             :precision => 38, :scale => 0, :default => 1
    t.integer  "lock_version",                             :precision => 38, :scale => 0, :default => 0
    t.integer  "mutator_id",                          :precision => 38, :scale => 0, :default => 0
    t.string   "name",                :limit => 50,                                                    :null => false
    t.string   "beschreibung",        :limit => 250
    t.integer  "parent_id",                           :precision => 38, :scale => 0
    t.string   "beschreibung_intern", :limit => 4000
    t.string   "geltungsbereich",     :limit => 1000
    t.string   "vergaberichtlinien",  :limit => 4000
    t.boolean  "ist_delegierbar",                     :precision => 1,  :scale => 0, :default => true
  end

  create_table "locked_rolle_h", :force => true do |t|
    t.integer  "locked_rolle_id",                                  :precision => 38, :scale => 0
    t.integer  "version",                                   :precision => 38, :scale => 0
    t.integer  "lock_version",                                   :precision => 38, :scale => 0, :default => 0
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "mutator_id",                                :precision => 38, :scale => 0
    t.string   "name",                      :limit => 50
    t.string   "beschreibung",              :limit => 250
    t.boolean  "deleted_in_original_table",                 :precision => 1,  :scale => 0
    t.integer  "record_restored",                           :precision => 38,  :scale => 0, :default => nil
    t.integer  "parent_id",                                 :precision => 38, :scale => 0
    t.string   "beschreibung_intern",       :limit => 4000
    t.string   "geltungsbereich",           :limit => 1000
    t.string   "vergaberichtlinien",        :limit => 4000
    t.boolean  "ist_delegierbar",                           :precision => 1,  :scale => 0, :default => true
  end
end
