# -*- encoding : utf-8 -*-
# Copyright (c) 2005 Rick Olson
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

VERSION = '0.9.3'

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    # Specify this act if you want to save a copy of the row in a versioned table.  This assumes there is a 
    # versioned table ready and that your model has a version field.  This works with optimistic locking if the lock_version
    # column is present as well.
    #
    # The class for the versioned model is derived the first time it is seen. Therefore, if you change your database schema you have to restart
    # your container for the changes to be reflected. In development mode this usually means restarting WEBrick.
    #
    #   class Page < ActiveRecord::Base
    #     # assumes pages_versions table
    #     acts_as_versioned
    #   end
    #
    # Example:
    #
    #   page = Page.create(:title => 'hello world!')
    #   page.version       # => 1
    #
    #   page.title = 'hello world'
    #   page.save
    #   page.version       # => 2
    #   page.versions.size # => 2
    #
    #   page.revert_to(1)  # using version number
    #   page.title         # => 'hello world!'
    #
    #   page.revert_to(page.versions.last) # using versioned instance
    #   page.title         # => 'hello world'
    #
    #   page.versions.earliest # efficient query to find the first version
    #   page.versions.latest   # efficient query to find the most recently created version
    #
    #
    # Simple Queries to page between versions
    #
    #   page.versions.before(version) 
    #   page.versions.after(version)
    #
    # Access the previous/next versions from the versioned model itself
    #
    #   version = page.versions.latest
    #   version.previous # go back one version
    #   version.next     # go forward one version
    #
    # See ActiveRecord::Acts::Versioned::ClassMethods#acts_as_versioned for configuration options
    module Versioned
      CALLBACKS = [:set_new_version, :save_version, :save_version?]
      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end

      module ClassMethods
        # == Configuration options
        #
        # * <tt>class_name</tt> - versioned model class name (default: PageVersion in the above example)
        # * <tt>table_name</tt> - versioned model table name (default: page_versions in the above example)
        # * <tt>foreign_key</tt> - foreign key used to relate the versioned model to the original model (default: page_id in the above example)
        # * <tt>inheritance_column</tt> - name of the column to save the model's inheritance_column value for STI.  (default: versioned_type)
        # * <tt>version_column</tt> - name of the column in the model that keeps the version number (default: version)
        # * <tt>sequence_name</tt> - name of the custom sequence to be used by the versioned model.
        # * <tt>limit</tt> - number of revisions to keep, defaults to unlimited
        # * <tt>if</tt> - symbol of method to check before saving a new version.  If this method returns false, a new version is not saved.
        #   For finer control, pass either a Proc or modify Model#version_condition_met?
        #
        #     acts_as_versioned :if => Proc.new { |auction| !auction.expired? }
        #
        #   or...
        #
        #     class Auction
        #       def version_condition_met? # totally bypasses the <tt>:if</tt> option
        #         !expired?
        #       end
        #     end
        #
        # * <tt>if_changed</tt> - Simple way of specifying attributes that are required to be changed before saving a model.  This takes
        #   either a symbol or array of symbols.
        #
        # * <tt>extend</tt> - Lets you specify a module to be mixed in both the original and versioned models.  You can also just pass a block
        #   to create an anonymous mixin:
        #
        #     class Auction
        #       acts_as_versioned do
        #         def started?
        #           !started_at.nil?
        #         end
        #       end
        #     end
        #
        #   or...
        #
        #     module AuctionExtension
        #       def started?
        #         !started_at.nil?
        #       end
        #     end
        #     class Auction
        #       acts_as_versioned :extend => AuctionExtension
        #     end
        #
        #  Example code:
        #
        #    @auction = Auction.find(1)
        #    @auction.started?
        #    @auction.versions.first.started?
        #
        # == Database Schema
        #
        # The model that you're versioning needs to have a 'version' attribute. The model is versioned 
        # into a table called #{model}_versions where the model name is singlular. The _versions table should 
        # contain all the fields you want versioned, the same version column, and a #{model}_id foreign key field.
        #
        # A lock_version field is also accepted if your model uses Optimistic Locking.  If your table uses Single Table inheritance,
        # then that field is reflected in the versioned model as 'versioned_type' by default.
        #
        # Acts_as_versioned comes prepared with the ActiveRecord::Acts::Versioned::ActMethods::ClassMethods#create_versioned_table 
        # method, perfect for a migration.  It will also create the version column if the main model does not already have it.
        #
        #   class AddVersions < ActiveRecord::Migration
        #     def self.up
        #       # create_versioned_table takes the same options hash
        #       # that create_table does
        #       Post.create_versioned_table
        #     end
        # 
        #     def self.down
        #       Post.drop_versioned_table
        #     end
        #   end
        # 
        # == Changing What Fields Are Versioned
        #
        # By default, acts_as_versioned will version all but these fields: 
        # 
        #   [self.primary_key, inheritance_column, 'version', 'lock_version', versioned_inheritance_column]
        #
        # You can add or change those by modifying #non_versioned_columns.  Note that this takes strings and not symbols.
        #
        #   class Post < ActiveRecord::Base
        #     acts_as_versioned
        #     self.non_versioned_columns << 'comments_count'
        #   end
        # 
        def acts_as_versioned(options = {}, &extension)
          # don't allow multiple calls
          return if self.included_modules.include?(ActiveRecord::Acts::Versioned::ActMethods)

          send :include, ActiveRecord::Acts::Versioned::ActMethods

          cattr_accessor :versioned_class_name, :versioned_foreign_key, :versioned_table_name, :versioned_inheritance_column, 
            :version_column, :max_version_limit, :track_altered_attributes, :version_condition, :version_sequence_name, :non_versioned_columns,
            :version_association_options, :version_if_changed, :deleted_in_original_table_flag, :record_restored_column

          self.versioned_class_name         = options[:class_name]  || "Version"
          self.versioned_foreign_key        = options[:foreign_key] || self.to_s.foreign_key
          self.versioned_table_name         = options[:table_name]  || if self.table_name then "#{table_name}_h" else "#{table_name_prefix}#{base_class.name.demodulize.underscore}_h#{table_name_suffix}" end

          self.versioned_inheritance_column = options[:inheritance_column] || "versioned_#{inheritance_column}"
          self.version_column               = options[:version_column]     || 'version'
          self.deleted_in_original_table_flag = options[:deleted_in_original_table_flag]     || 'deleted_in_original_table'
          self.record_restored_column       = options[:record_restored_column]     || 'record_restored'
          self.version_sequence_name        = options[:sequence_name]
          self.max_version_limit            = options[:limit].to_i
          self.version_condition            = options[:if] || true
          self.non_versioned_columns        = [self.primary_key, inheritance_column, self.version_column, 'lock_version', versioned_inheritance_column] + options[:non_versioned_columns].to_a.map(&:to_s)
          if options[:association_options].is_a?(Hash) && options[:association_options][:dependent] == :nullify
            raise "Illegal option :dependent => :nullify - this would produce orphans in version model"
          end
          self.version_association_options  = {
                                                :class_name  => "#{self.to_s}::#{versioned_class_name}",
                                                :foreign_key => versioned_foreign_key
                                              }.merge(options[:association_options] || {})

          if block_given?
            extension_module_name = "#{versioned_class_name}Extension"
            silence_warnings do
              self.const_set(extension_module_name, Module.new(&extension))
            end

            options[:extend] = self.const_get(extension_module_name)
          end

          class_eval <<-CLASS_METHODS, __FILE__, __LINE__ + 1
            has_many :versions, **version_association_options do
              # finds earliest version of this record
              def earliest
                @earliest ||= order('#{version_column}').first
              end

              # find latest version of this record
              def latest
                @latest ||= order('#{version_column} desc').first
              end
            end
            before_save  :set_new_version
            after_save   :save_version
            after_save   :clear_old_versions
            after_destroy :set_deleted_flag

            unless options[:if_changed].nil?
              self.track_altered_attributes = true
              options[:if_changed] = [options[:if_changed]] unless options[:if_changed].is_a?(Array)
              self.version_if_changed = options[:if_changed].map(&:to_s)
            end

            include options[:extend] if options[:extend].is_a?(Module)
          CLASS_METHODS

          # create the dynamic versioned model
          const_set(versioned_class_name, Class.new(ActiveRecord::Base)).class_eval do
            def self.reloadable? ; false ; end
            # find first version before the given version
            # TODO: replace "version" in selects with version_column, use select-method instead of find
            def self.before(version)
              where("#{original_class.versioned_foreign_key} = ? and version < ?", version.send(original_class.versioned_foreign_key), version.version).order('version desc').first
            end

            # find first version after the given version.
            def self.after(version)
              where("#{original_class.versioned_foreign_key} = ? and version > ?", version.send(original_class.versioned_foreign_key), version.version).order('version').first
            end

            def previous
              self.class.before(self)
            end

            def next
              self.class.after(self)
            end

            def versions_count
              page.version # TODO: ?!
            end

            def restore(perform_validation = true)
              id = self.send(self.original_class.versioned_foreign_key)
              if self.original_class.exists?(id)
                raise RuntimeError.new("Record exists in restore, id = #{id} class = #{self.class.name}")
              end

              version_hash = self.attributes
              version_hash.delete "id"
              version_hash.delete self.original_class.deleted_in_original_table_flag.to_s
              version_hash.delete self.original_class.record_restored_column.to_s
              version_hash.delete self.original_class.versioned_foreign_key.to_s

              restored_record = self.original_class.new(version_hash)
              restored_record.id = id
              if restored_record.respond_to? :updated_at=
                restored_record.updated_at = Time.now
              end
              # DON'T EVEN THINK ABOUT CALCULATING THE VERSION NUMBER USING THE VERSIONS ASSOCIATION HERE:
              # There is a problem in ActiveRecord. An association Relation will be converted to an Array internally, when the SQL-select is
              # executed.
              # Some ActiveRecord-Methods (for example #ActiveRecord::Base::AutosaveAssociation#save_collection_association) try to use ActiveRecord methods
              # with these Relations, and if these Relations have been converted to Arrays, these calls fail with an Exception
              new_version_number = self.class.where(self.original_class.versioned_foreign_key => id).order('id desc').first.send(restored_record.version_column).to_i + 1
              restored_record.send("#{restored_record.version_column}=", new_version_number)
              unless restored_record.save_without_revision(perform_validation)
                raise RuntimeError.new("Couldn't restore the record, id = #{id} class = #{self.class.name}")
              end
              restored_record.save_version(true, false, self.send(self.original_class.version_column))
            end

            def record_restored?
              self.read_attribute(self.original_class.record_restored_column) != nil
            end
            alias :record_restored :record_restored?

            def record_restored_from_version
              self.read_attribute(self.original_class.record_restored_column)
            end

            def original_record_exists?
              original_class.exists?(self.send original_class.versioned_foreign_key)
            end
          end

          versioned_class.cattr_accessor :original_class
          versioned_class.original_class = self
          versioned_class.table_name = versioned_table_name
          versioned_class.belongs_to self.to_s.demodulize.underscore.to_sym, 
            :class_name  => "::#{self.to_s}", 
            :foreign_key => versioned_foreign_key,
            :optional => true
          versioned_class.send :include, options[:extend]         if options[:extend].is_a?(Module)
          versioned_class.sequence_name = version_sequence_name if version_sequence_name
        end
      end

      module ActMethods
        def self.included(base) # :nodoc:
          base.extend ClassMethods
        end

        # Saves a version of the model in the versioned table.  This is called in the after_save callback by default
        def save_version(save_this=false, deleted_flag=false, restored_from_version=nil)
          if @saving_version || save_this
            @saving_version = nil
            rev = self.class.versioned_class.new
            clone_versioned_model(self, rev)
            rev.send("#{self.class.version_column}=", send(self.class.version_column))
            rev.send("#{self.class.versioned_foreign_key}=", id)
            rev.send("#{self.class.deleted_in_original_table_flag}=", deleted_flag)
            rev.send("#{self.class.record_restored_column}=", restored_from_version)
            if rev.respond_to? :updated_at=
              rev.updated_at = Time.now
            end
            rev.save
          end
        end

        def set_deleted_flag
          return if self.id.nil?

          rev = self.class.versioned_class.new
          clone_versioned_model(self, rev)
          rev.send("#{self.class.version_column}=", highest_version+1)
          rev.send("#{self.class.versioned_foreign_key}=", id)
          rev.send("#{self.class.deleted_in_original_table_flag}=", true)
          rev.send("#{self.class.record_restored_column}=", nil)
          if rev.respond_to? :updated_at=
            rev.updated_at = Time.now
          end
          rev.save
        end

        # Clears old revisions if a limit is set with the :limit option in <tt>acts_as_versioned</tt>.
        # Override this method to set your own criteria for clearing old versions.
        def clear_old_versions
          return if self.class.max_version_limit == 0
          excess_baggage = send(self.class.version_column).to_i - self.class.max_version_limit
          if excess_baggage > 0
            self.class.versioned_class.delete_all ["#{self.class.version_column} <= ? and #{self.class.versioned_foreign_key} = ?", excess_baggage, id]
          end
        end

        # Reverts a model to a given version.  Takes either a version number or an instance of the versioned model
        def revert_to(version)
          if version.is_a?(self.class.versioned_class)
            @reverted_from = version.send(self.class.version_column)
            return false unless version.send(self.class.versioned_foreign_key) == id and !version.new_record?
          else
            @reverted_from = version
            version = versions.where(self.class.version_column => version).first
            return false unless version
          end
          self.clone_versioned_model(version, self)
          send("#{self.class.version_column}=", version.send(self.class.version_column))
          true
        end

        # Reverts a model to a given version and saves the model.
        # Takes either a version number or an instance of the versioned model
        def revert_to!(version)
          if revert_to(version)
            set_new_version
            save_without_revision
            save_version(true, false, @reverted_from)
          else
            false
          end
        end

        # Temporarily turns off Optimistic Locking while saving.  Used when reverting so that a new version is not created.
        def save_without_revision(perform_validation = true)
          ret = false
          without_locking do
            without_revision do
              ret = save(:validate => perform_validation)
            end
          end
          return ret
        end

        def save_without_revision!
          without_locking do
            without_revision do
              save!
            end
          end
        end
        
        def altered?
          track_altered_attributes ? (version_if_changed - changed).length < version_if_changed.length : changed?
        end

        # Clones a model.  Used when saving a new version or reverting a model's version.
        def clone_versioned_model(orig_model, new_model)
          self.class.versioned_columns.each do |col|
            new_model.send("#{col.name}=", orig_model.send(col.name)) if orig_model.has_attribute?(col.name)
          end

          clone_inheritance_column(orig_model, new_model)
        end

        def clone_inheritance_column(orig_model, new_model)
          if orig_model.is_a?(self.class.versioned_class) && new_model.class.column_names.include?(new_model.class.inheritance_column.to_s)
            new_model[new_model.class.inheritance_column] = orig_model[self.class.versioned_inheritance_column]
          elsif new_model.is_a?(self.class.versioned_class) && new_model.class.column_names.include?(self.class.versioned_inheritance_column.to_s)
            new_model[self.class.versioned_inheritance_column] = orig_model[orig_model.class.inheritance_column]
          end
        end

        # Checks whether a new version shall be saved or not.  Calls <tt>version_condition_met?</tt> and <tt>changed?</tt>.
        def save_version?
          version_condition_met? && altered?
        end

        # Checks condition set in the :if option to check whether a revision should be created or not.  Override this for
        # custom version condition checking.
        def version_condition_met?
          case
          when version_condition.is_a?(Symbol)
            send(version_condition)
          when version_condition.respond_to?(:call) && (version_condition.arity == 1 || version_condition.arity == -1)
            version_condition.call(self)
          else
            version_condition
          end
        end

        # Executes the block with the versioning callbacks disabled.
        #
        #   @foo.without_revision do
        #     @foo.save
        #   end
        #
        def without_revision(&block)
          self.class.without_revision(&block)
        end

        # Turns off optimistic locking for the duration of the block
        #
        #   @foo.without_locking do
        #     @foo.save
        #   end
        #
        def without_locking(&block)
          self.class.without_locking(&block)
        end

        def empty_callback() end #:nodoc:

=begin
# Alte finder-Syntax ab Rails 5 nicht mehr verwendbar.
# Assoziation versions stattdessen verwenden
        def find_versions(*args)
          return [] if self.id.nil?

          options = args.extract_options!
          version_condition = "#{self.class.versioned_foreign_key} = #{self.id}"
          if options[:conditions]
            options[:conditions] += " and #{version_condition}"
          else
            options[:conditions] = version_condition
          end
          if args.first.is_a?(Symbol)
            versions.find(args.first, options)
          else # TODO: is_a?(Fixnum)
            versions.find(options)
          end
        end
=end

        def find_newest_version
          return nil if self.id.nil?

          self.class.versioned_class.where("#{self.class.versioned_foreign_key} = #{self.id}").order("version DESC").first
        end

        def highest_version
          v = find_newest_version
          if v then 
            v.version 
          else 
            -1
          end
        end

        def find_version(version)
          return nil if self.id.nil?

          ret = self.class.versioned_class.where("#{self.class.versioned_foreign_key} = #{self.id} and #{self.class.version_column}=#{version}").first
          raise "find_version: version #{version} not found in database" unless ret
          ret
        end

        protected
        # sets the new version before saving
        def set_new_version
          @saving_version = new_record? || save_version?
          self.send("#{self.class.version_column}=", next_version) if new_record? || save_version?
        end

        # Gets the next available version for the current record, or 1 for a new record
        def next_version
          (new_record? ? 0 : versions.calculate(:maximum, version_column).to_i) + 1
        end

        module ClassMethods
          # Returns an array of columns that are versioned.  See non_versioned_columns
          def versioned_columns
            @versioned_columns ||= columns.select { |c| !non_versioned_columns.include?(c.name) }
          end

          # Returns an instance of the dynamic versioned model
          def versioned_class
            const_get versioned_class_name
          end

          # Rake migration task to create the versioned table using options passed to acts_as_versioned
          def create_versioned_table(create_table_options = {})
            # create version column in main table if it does not exist
            if !self.content_columns.find { |c| [version_column.to_s, 'lock_version'].include? c.name }
              self.connection.add_column table_name, version_column, :integer
              self.reset_column_information
            end

            return if connection.table_exists?(versioned_table_name)
            
            self.connection.create_table(versioned_table_name, create_table_options) do |t|
              t.column versioned_foreign_key, :integer
              t.column version_column, :integer
              t.column deleted_in_original_table_flag, :boolean, :default => false
              t.column record_restored_column, :integer, :default => nil
            end

            self.versioned_columns.each do |col|
              self.connection.add_column versioned_table_name, col.name, col.type, 
                :limit     => col.limit, 
                :default   => col.default,
                :scale     => col.scale,
                :precision => col.precision
            end

            if type_col = self.columns_hash[inheritance_column]
              self.connection.add_column versioned_table_name, versioned_inheritance_column, type_col.type, 
                :limit     => type_col.limit, 
                :default   => type_col.default,
                :scale     => type_col.scale,
                :precision => type_col.precision
            end
            
            #self.connection.add_index versioned_table_name, versioned_foreign_key
          end

          # Rake migration task to drop the versioned table
          def drop_versioned_table
            self.connection.drop_table versioned_table_name
          end

          def restore_deleted(id)
            version_record = versioned_class.where("#{versioned_foreign_key} = #{id}").order("version DESC").first
            version_record.restore
          end

          def restore_deleted_version(id, version)
            version_record = versioned_class.where("#{versioned_foreign_key} = #{id} and version = #{version}").first
            version_record.restore
          end

          # Executes the block with the versioning callbacks disabled.
          #
          #   Foo.without_revision do
          #     @foo.save
          #   end
          #
          def without_revision(&block)
            class_eval do 
              CALLBACKS.each do |attr_name|
                alias_method "orig_#{attr_name}".to_sym, attr_name
                alias_method attr_name, :empty_callback
              end
            end
            block.call
          ensure
            class_eval do 
              CALLBACKS.each do |attr_name|
                alias_method attr_name, "orig_#{attr_name}".to_sym
              end
            end
          end

          # Turns off optimistic locking for the duration of the block
          #
          #   Foo.without_locking do
          #     @foo.save
          #   end
          #
          def without_locking(&block)
            current = ActiveRecord::Base.lock_optimistically
            ActiveRecord::Base.lock_optimistically = false if current
            begin
              block.call
            ensure
              ActiveRecord::Base.lock_optimistically = true if current
            end
          end
        end
      end
    end
  end
end

# TISS extension: do not pull this.
module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    class TableDefinition
      ## Erzeugt 4 Spalten created_at, updated_at, version, mutator_id die in 
      ## jeder Daten-Tabelle notwendig sind. Verwendung:
      ##  create_table :adresse do |t|
      ##    t.standard_spalten
      ##    t.string strasse, :size=>120
      ##    t.string plz, :size=>4
      ##  end
      def standard_spalten
        column(:created_at, :datetime)
        column(:updated_at, :datetime)
        column(:version, :integer, :default=>1)
        column(:mutator_id, :integer, :default=>0)
      end
    end
  end
end


ActiveRecord::Base.send :include, ActiveRecord::Acts::Versioned
