module ElasticsearchRepositories
  # Contains an adapter which provides OxM-specific implementations for common behaviour:
  #
  # * {Adapter#records_mixin   Fetching records from the database}
  # * {Adapter#importing_mixin Efficient bulk loading from the database}
  #
  # @see ElasticsearchRepositories::Adapters::Default
  # @see ElasticsearchRepositories::Adapters::ActiveRecord
  #

  # Contains an adapter for specific OxM or architecture.
  #
  class Adapter
    attr_reader :klass

    def initialize(klass)
      @klass = klass
    end

    class << self

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
      def register(name, condition)
        self.adapters[name] = condition
      end

      # @return Hash{adapter_klass => Proc} the collection of registered adapters
      def adapters
        @adapters ||= {}
      end
      
    end

    # Return the module with {Default::Records} interface implementation
    #
    # @api private
    def records_mixin
      adapter.const_get(:Records)
    end

    # Return the module with {Default::Importing} interface implementation
    #
    # @api private
    def importing_mixin
      adapter.const_get(:Importing)
    end

    # Returns the adapter module
    #
    # @api private
    def adapter
      @adapter ||= begin
        self.class.adapters.find( lambda {[]} ) { |name, condition| condition.call(klass) }.first \
        || ElasticsearchRepositories::Adapters::Default
      end
    end

  end
  
end
