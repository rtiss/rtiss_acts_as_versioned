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

require_relative './rtiss_acts_as_versioned/act_methods'
require_relative './rtiss_acts_as_versioned/version'

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
            def self.before(version)
              where("#{original_class.versioned_foreign_key} = ? and #{self.version_column} < ?",
                    version.send(original_class.versioned_foreign_key), version.version)
                .order("#{self.version_column} desc").first
            end

            # find first version after the given version.
            def self.after(version)
              where("#{original_class.versioned_foreign_key} = ? and #{self.version_column} > ?",
                    version.send(original_class.versioned_foreign_key), version.version)
                .order(self.version_column).first
            end

            def previous
              self.class.before(self)
            end

            def next
              self.class.after(self)
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
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::Acts::Versioned