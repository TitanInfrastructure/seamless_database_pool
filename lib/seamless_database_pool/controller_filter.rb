module SeamlessDatabasePool
  # This module provides a simple method of declaring which read pool connection type should
  # be used for various ActionController actions. To use it, you must first mix it into
  # you controller and then call use_database_pool to configure the connection types. Generally
  # you should just do this in ApplicationController and call use_database_pool in your controllers
  # when you need different connection types.
  #
  # Example:
  # 
  #   ApplicationController < ActionController::Base
  #     include SeamlessDatabasePool::ControllerFilter
  #     use_database_pool :all => :persistent, [:save, :delete] => :master
  #     ...
  
  module ControllerFilter    
    def self.included (base)
      unless base.respond_to?(:use_database_pool)
        base.extend(ClassMethods)
        base.class_eval do
          alias_method_chain :process_action, :seamless_database_pool
          alias_method_chain :redirect_to, :seamless_database_pool
        end
      end
    end
    
    module ClassMethods
      
      def seamless_database_pool_options
        return @seamless_database_pool_options if @seamless_database_pool_options
        @seamless_database_pool_options = superclass.seamless_database_pool_options.dup if superclass.respond_to?(:seamless_database_pool_options)
        @seamless_database_pool_options ||= {}
      end
      
      # Call this method to set up the connection types that will be used for your actions.
      # The configuration is given as a hash where the key is the action name and the value is
      # the connection type (:master, :persistent, or :random). You can specify :all as the action
      # to define a default connection type. You can also specify the action names in an array
      # to easily map multiple actions to one connection type.
      #
      # The configuration is inherited from parent controller classes, so if you have default
      # behavior, you should simply specify it in ApplicationController to have it available
      # globally.
      def use_database_pool (options)
        remapped_options = seamless_database_pool_options
        options.each_pair do |actions, connection_method|
          unless SeamlessDatabasePool::READ_CONNECTION_METHODS.include?(connection_method)
            raise "Invalid read pool method: #{connection_method}; should be one of #{SeamlessDatabasePool::READ_CONNECTION_METHODS.inspect}"
          end
          actions = [actions] unless actions.kind_of?(Array)
          actions.each do |action|
            remapped_options[action.to_sym] = connection_method
          end
        end
        @seamless_database_pool_options = remapped_options
      end
    end
    
    # Force the master connection to be used on the next request. This is very useful for the Post-Redirect pattern
    # where you post a request to your save action and then redirect the user back to the edit action. By calling
    # this method, you won't have to worry if the replication engine is slower than the redirect. Normally you
    # won't need to call this method yourself as it is automatically called when you perform a redirect from within
    # a master connection block. It is made available just in case you have special needs that don't quite fit
    # into this module's default logic.
    def use_master_db_connection_on_next_request
      # wbh the problem with this idea is that it means every action in every controller will be obligated to create a
    	# session.  It's not worth the trade-off, imho
      #session[:next_request_db_connection] = :master if session
    end
    
    def seamless_database_pool_options
      self.class.seamless_database_pool_options
    end
    
    def process_action_with_seamless_database_pool(method_name, *args)
      read_pool_method = nil
      #if session
      #  read_pool_method = session[:next_request_db_connection]
      #  session[:next_request_db_connection] = nil
      #end
      
      read_pool_method ||= seamless_database_pool_options[action_name.to_sym] || seamless_database_pool_options[:all]
      if read_pool_method
        SeamlessDatabasePool.set_read_only_connection_type(read_pool_method) do
          process_action_without_seamless_database_pool(method_name, *args)
        end
      else
        process_action_without_seamless_database_pool(method_name, *args)
      end
    end
    
    def redirect_to_with_seamless_database_pool (options = {}, response_status = {})
      if SeamlessDatabasePool.read_only_connection_type(nil) == :master
        use_master_db_connection_on_next_request
      end
      redirect_to_without_seamless_database_pool(options, response_status)
    end
  end
end
