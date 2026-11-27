module ActiveRecord
  module Acts
    module Versioned
      module ActMethods
        WITHOUT_REVISION_KEY = :rtiss_acts_as_versioned_without_revision
        WITHOUT_LOCKING_KEY = :rtiss_acts_as_versioned_without_locking

        # Prepended to ActiveRecord::Base.singleton_class: disables optimistic locking inside without_locking blocks
        module LockingOverride
          def locking_enabled?
            return false if ActiveSupport::IsolatedExecutionState[WITHOUT_LOCKING_KEY]

            super
          end
        end

        def self.included(base) # :nodoc:
          base.extend ClassMethods
        end

        # Saves a version of the model in the versioned table.  This is called in the after_save callback by default
        def save_version(save_this=false, deleted_flag=false, restored_from_version=nil)
          return if self.class.without_revision?

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
            save_version_record!(rev)
          end
        end

        # Writes the deletion version (after_destroy callback).
        # The version is built from the in-memory state of the record at this point, so attributes assigned in a
        # before_destroy callback (e.g. who deleted the record) are stored in the deletion version.
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
          save_version_record!(rev)
        end

        # Clears old revisions if a limit is set with the :limit option in <tt>acts_as_versioned</tt>.
        # Override this method to set your own criteria for clearing old versions.
        def clear_old_versions
          return if self.class.max_version_limit == 0
          excess_baggage = send(self.class.version_column).to_i - self.class.max_version_limit
          if excess_baggage > 0
            self.class.versioned_class.where(self.class.versioned_foreign_key => id, self.class.version_column => ..excess_baggage).delete_all
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
        # A revert always creates a new version with the next version number.
        # Returns false if the version is not found or the record can't be saved.
        def revert_to!(version)
          return false unless revert_to(version)

          self.class.transaction do
            send("#{self.class.version_column}=", next_version)
            saved = save_without_revision
            save_version(true, false, @reverted_from) if saved
            saved
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

        # True while Version#restore saves this record, false otherwise.
        # Lets the application tell a restore apart from a normal create in its own callbacks, e.g. to record
        # the restoring user instead of the value copied from the version.
        def restoring?
          !!@restoring
        end

        # Marks the record as being restored for the duration of the block. Used by Version#restore.
        def while_restoring # :nodoc:
          previous = @restoring
          @restoring = true
          yield
        ensure
          @restoring = previous
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
          return false if self.class.without_revision?

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

        def find_newest_version
          return nil if self.id.nil?

          self.class.versioned_class.where(self.class.versioned_foreign_key => id).order(self.class.version_column => :desc).first
        end

        def highest_version
          find_newest_version&.version || -1
        end

        def find_version(version)
          return nil if self.id.nil?

          ret = self.class.versioned_class.find_by(self.class.versioned_foreign_key => id, self.class.version_column => version)
          raise "find_version: version #{version} not found in database" unless ret
          ret
        end

        protected
        # sets the new version before saving
        def set_new_version
          return if self.class.without_revision?

          @saving_version = new_record? || save_version?
          self.send("#{self.class.version_column}=", next_version) if new_record? || save_version?
        end

        # Saves the version record. Raises ActiveRecord::RecordNotSaved if it can't be saved (e.g. a validation on the
        # versioned class fails), so the surrounding save/destroy of the original record is rolled back.
        def save_version_record!(rev)
          return true if rev.save

          raise ActiveRecord::RecordNotSaved.new(
            "Couldn't save version #{rev.send(self.class.version_column)} of #{self.class.name} id = #{id}: " \
            "#{rev.errors.full_messages.join(', ')}", rev)
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
            version_record = versioned_class.where(versioned_foreign_key => id).order(version_column => :desc).first!
            version_record.restore
          end

          def restore_deleted_version(id, version)
            version_record = versioned_class.find_by!(versioned_foreign_key => id, version_column => version)
            version_record.restore
          end

          # Executes the block with versioning disabled for this class (and its subclasses).
          # Only affects the current thread (or fiber, see config.active_support.isolation_level); may be nested.
          #
          #   Foo.without_revision do
          #     @foo.save
          #   end
          #
          def without_revision
            previous = ActiveSupport::IsolatedExecutionState[WITHOUT_REVISION_KEY]
            ActiveSupport::IsolatedExecutionState[WITHOUT_REVISION_KEY] = [*previous, self]
            yield
          ensure
            ActiveSupport::IsolatedExecutionState[WITHOUT_REVISION_KEY] = previous
          end

          # True while inside a without_revision block for this class (or a superclass) in the current thread.
          def without_revision?
            classes = ActiveSupport::IsolatedExecutionState[WITHOUT_REVISION_KEY]
            !classes.nil? && classes.any? { |klass| self <= klass }
          end

          # Turns off optimistic locking for all models for the duration of the block.
          # Only affects the current thread (or fiber, see config.active_support.isolation_level); may be nested.
          #
          #   Foo.without_locking do
          #     @foo.save
          #   end
          #
          def without_locking
            previous = ActiveSupport::IsolatedExecutionState[WITHOUT_LOCKING_KEY]
            ActiveSupport::IsolatedExecutionState[WITHOUT_LOCKING_KEY] = true
            yield
          ensure
            ActiveSupport::IsolatedExecutionState[WITHOUT_LOCKING_KEY] = previous
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
