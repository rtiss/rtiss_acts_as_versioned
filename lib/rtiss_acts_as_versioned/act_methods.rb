module ActiveRecord
  module Acts
    module Versioned
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
              ret = save(validate: perform_validation)
            end
          end
          ret
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

        def find_newest_version
          return nil if self.id.nil?

          self.class.versioned_class.where("#{self.class.versioned_foreign_key} = #{self.id}").order("#{self.version_column} DESC").first
        end

        def highest_version
          find_newest_version&.version || -1
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

          def restore_deleted(id)
            version_record = versioned_class.where("#{versioned_foreign_key} = #{id}").order("#{self.version_column} DESC").first
            version_record.restore
          end

          def restore_deleted_version(id, version)
            version_record = versioned_class.where("#{versioned_foreign_key} = #{id} and #{self.version_column} = #{version}").first
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

          # Rake migration task to create the versioned table using options passed to acts_as_versioned
          def create_versioned_table(create_table_options = {})
            # create version column in main table if it does not exist
            unless self.column_names.find { |c| [version_column.to_s, 'lock_version'].include? c }
              self.connection.add_column table_name, version_column, :integer
              self.reset_column_information
            end

            return if connection.table_exists?(versioned_table_name)

            self.connection.create_table(versioned_table_name, **create_table_options) do |t|
              t.column versioned_foreign_key, :integer
              t.column version_column, :integer
              t.column deleted_in_original_table_flag, :boolean, default: false
              t.column record_restored_column, :integer, default: nil
            end

            self.versioned_columns.each do |col|
              self.connection.add_column versioned_table_name, col.name, col.type,
                                         limit: col.limit,
                                         default: col.default,
                                         scale: col.scale,
                                         precision: col.precision
            end

            if type_col = self.columns_hash[inheritance_column]
              self.connection.add_column versioned_table_name, versioned_inheritance_column, type_col.type,
                                         limit: type_col.limit,
                                         default: type_col.default,
                                         scale: type_col.scale,
                                         precision: type_col.precision
            end
          end

          # Rake migration task to drop the versioned table
          def drop_versioned_table
            self.connection.drop_table versioned_table_name
          end
        end
      end
    end
  end
end
