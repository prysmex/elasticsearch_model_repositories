module ElasticsearchRepositories
  # Contains an adapter which provides OxM-specific implementations for common behaviour:
  #
  # * {Adapter::Adapter#records_mixin   Fetching records from the database}
  # * {Adapter::Adapter#callbacks_mixin Model callbacks for automatic index updates}
  # * {Adapter::Adapter#importing_mixin Efficient bulk loading from the database}
  #
  # @see ElasticsearchRepositories::Adapter::Default
  # @see ElasticsearchRepositories::Adapter::ActiveRecord
  # @see ElasticsearchRepositories::Adapter::Mongoid
  #
  module Adapter

    # Returns an adapter based on the Ruby class passed
    #
    # @example Create an adapter for an ActiveRecord-based model
    #
    #     class Article < ActiveRecord::Base; end
    #
    #     myadapter = ElasticsearchRepositories::Adapter.from_class(Article)
    #     myadapter.adapter
    #     # => ElasticsearchRepositories::Adapter::ActiveRecord
    #
    # @see Adapter.adapters The list of included adapters
    # @see Adapter.register Register a custom adapter
    #
    def from_class(klass)
      Adapter.new(klass)
    end; module_function :from_class

    # Returns registered adapters
    #
    # @see ::ElasticsearchRepositories::Adapter::Adapter.adapters
    #
    def adapters
      Adapter.adapters
    end; module_function :adapters

    # Registers an adapter
    #
    # @see ::ElasticsearchRepositories::Adapter::Adapter.register
    #
    def register(name, condition)
      Adapter.register(name, condition)
    end; module_function :register

    # Contains an adapter for specific OxM or architecture.
    #
    class Adapter
      attr_reader :klass

      def initialize(klass)
        @klass = klass
      end

      # Registers an adapter for specific condition
      #
      # @param name      [Module] The module containing the implemented interface
      # @param condition [Proc]   An object with a `call` method which is evaluated in {.adapter}
      #
      # @example Register an adapter for DataMapper
      #
      #     module DataMapperAdapter
      #
      #       # Implement the interface for fetching records
      #       #
      #       module Records
      #         def records
      #           klass.all(id: @ids)
      #         end
      #
      #         # ...
      #       end
      #     end
      #
      #     # Register the adapter
      #     #
      #     ElasticsearchRepositories::Adapter.register(
      #       DataMapperAdapter,
      #       lambda { |klass|
      #         defined?(::DataMapper::Resource) and klass.ancestors.include?(::DataMapper::Resource)
      #       }
      #     )
      #
      def self.register(name, condition)
        self.adapters[name] = condition
      end

      # Return the collection of registered adapters
      #
      # @example Return the currently registered adapters
      #
      #     ElasticsearchRepositories::Adapter.adapters
      #     # => {
      #     #  ElasticsearchRepositories::Adapter::ActiveRecord => #<Proc:0x007...(lambda)>,
      #     #  ElasticsearchRepositories::Adapter::Mongoid => #<Proc:0x007... (lambda)>,
      #     # }
      #
      # @return [Hash] The collection of adapters
      #
      def self.adapters
        @adapters ||= {}
      end

      # Return the module with {Default::Records} interface implementation
      #
      # @api private
      #
      def records_mixin
        adapter.const_get(:Records)
      end

      # Return the module with {Default::Callbacks} interface implementation
      #
      # @api private
      #
      # def callbacks_mixin
      #   adapter.const_get(:Callbacks)
      # end

      # Return the module with {Default::Importing} interface implementation
      #
      # @api private
      #
      def importing_mixin
        adapter.const_get(:Importing)
      end

      # Returns the adapter module
      #
      # @api private
      #
      def adapter
        @adapter ||= begin
          self.class.adapters.find( lambda {[]} ) { |name, condition| condition.call(klass) }.first \
          || ElasticsearchRepositories::Adapter::Default
        end
      end

    end
  end
end
