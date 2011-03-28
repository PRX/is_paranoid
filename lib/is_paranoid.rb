require 'active_record'

module IsParanoid
  def self.included(base) # :nodoc:
    base.extend SafetyNet
  end

  module SafetyNet
    # Call this in your model to enable all the safety-net goodness
    #
    #  Example:
    #
    #  class Android < ActiveRecord::Base
    #    is_paranoid
    #  end
    def is_paranoid
      class_eval do
        # This is the real magic.  All calls made to this model will
        # append the conditions deleted_at => nil.  Exceptions require
        # using with_destroyed_scope (see self.delete_all,
        # self.count_with_destroyed, and self.find_with_destroyed )
        default_scope :conditions => {:deleted_at => nil}

        # Actually delete the model, bypassing the safety net.  Because
        # this method is called internally by Model.delete(id) and on the
        # delete method in each instance, we don't need to specify those
        # methods separately
        def self.delete_all conditions = nil
          self.with_destroyed_scope { super conditions }
        end

        # Return a count that includes the soft-deleted models.
        def self.count_with_destroyed *args
          self.with_destroyed_scope { count(*args) }
        end

        # Perform a count only on destroyed instances.
        def self.count_only_destroyed *args
          self.with_only_destroyed_scope { count(*args) }
        end

        # Return instances of all models matching the query regardless
        # of whether or not they have been soft-deleted.
        def self.find_with_destroyed *args
          self.with_destroyed_scope { find(*args) }
        end
        
        # Perform a find only on destroyed instances.
        def self.find_only_destroyed *args
          self.with_only_destroyed_scope { find(*args) }
        end

        # Returns true if the requested record exists, even if it has
        # been soft-deleted.
        def self.exists_with_destroyed? *args
          self.with_destroyed_scope { exists?(*args) }
        end

        # Returns true if the requested record has been soft-deleted.
        def self.exists_only_destroyed? *args
          self.with_only_destroyed_scope { exists?(*args) }
        end

        # Override the default destroy to allow us to flag deleted_at.
        # This preserves the before_destroy and after_destroy callbacks.
        # Because this is also called internally by Model.destroy_all and
        # the Model.destroy(id), we don't need to specify those methods
        # separately.
        def destroy
          return false if callback(:before_destroy) == false
          result = destroy_without_callbacks
          callback(:after_destroy)
          result
        end

        # Set deleted_at flag on a model to nil, effectively undoing the
        # soft-deletion.
        def restore
          self.deleted_at_will_change!
          self.deleted_at = nil
          update_without_callbacks
        end

        # Has this model been soft-deleted?
        def destroyed?
          super || !deleted_at.nil?
        end
        
        protected

        # Mark the model deleted_at as now.
        def destroy_without_callbacks
          self.deleted_at = Time.now 
          update_without_callbacks
        end
        
        def self.with_only_destroyed_scope(&block)
          with_destroyed_scope do
            table = connection.quote_table_name(table_name)
            attr = connection.quote_column_name(:deleted_at)
            with_scope(:find => { :conditions => "#{table}.#{attr} IS NOT NULL" }, &block)
          end
        end

        def self.with_destroyed_scope
          find = current_scoped_methods[:find]

          if find[:conditions]
            original = find[:conditions].dup

            begin
              case find[:conditions]
              when Hash:
                if find[:conditions][:deleted_at].nil?
                  find[:conditions].delete(:deleted_at)
                end
              when String:
                conditions = sanitize_conditions(:deleted_at => nil)
                find[:conditions].gsub!(conditions, '1=1')
              end
              
              result = yield
            ensure
              find[:conditions] = original
              return result if result
            end
          else
            yield
          end
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, IsParanoid)
