module ElasticsearchRepositories
  # Contains a registry for ElasticsearchRepositories::Adapters::* along with a
  # lambda that is used to match an adapter
  #
  # * {Adapter#records_mixin   Fetching records from the database}
  # * {Adapter#importing_mixin Efficient bulk loading from the database}
  #
  # @see ElasticsearchRepositories::Adapters::ActiveRecord
  #
  #
  class Adapter

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
      #           klass_or_klasses.all(id: @ids)
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
      #       lambda { |klass_or_klasses|
      #         defined?(::DataMapper::Resource) and klass_or_klasses.ancestors.include?(::DataMapper::Resource)
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

    attr_reader :klass_or_klasses

    # @param [Class,Array<Class>] klass_or_klasses
    def initialize(klass_or_klasses)
      @klass_or_klasses = klass_or_klasses
    end

    # Return the Records module from the matching adapter
    #
    # @return [Module]
    def records_mixin
      match_adapter.const_get(:Records)
    end

    # Return the Importing module from the matching adapter
    #
    # @return [Module]
    def importing_mixin
      match_adapter.const_get(:Importing)
    end

    # Returns the adapter module that first evaluates its registered condition as true 
    #
    # @return [Module] ElasticsearchRepositories::Adapters::*
    def match_adapter
      @matched_adapter ||= begin
        self.class.adapters.find( lambda {[]} ) { |name, condition| condition.call(klass_or_klasses) }.first
      end
    end

  end
  
end
