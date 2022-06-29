module ElasticsearchRepositories
  module Response

    # Encapsulates the collection of records returned from the database
    #
    # Implements Enumerable and forwards its methods to the {#records} object,
    # which is provided by an {ElasticsearchRepositories::Adapter} implementation.
    #
    class Records
      include Enumerable

      delegate :each, :empty?, :size, :slice, :[], :to_a, :to_ary, to: :records

      attr_accessor :options

      attr_reader :klass_or_klasses, :response

      # @param [Class,Array<Class>] klass_or_klasses
      # @param [ElasticsearchRepositories::Response::Response] response
      def initialize(klass_or_klasses, response, options={})
        
        @klass_or_klasses = klass_or_klasses
        @response = response

        # Include module provided by the adapter in the singleton class
        #
        adapter = Adapter.new(klass_or_klasses)
        self.singleton_class.include adapter.records_mixin

        self.options = options
      end

      # Returns the hit IDs
      #
      def ids
        response.results.map(&:id)
      end

      # Returns the {Results} collection
      #
      def results
        response.results
      end

      # Yields [record, hit] pairs to the block
      #
      def each_with_hit(&block)
        records.to_a.zip(results).each(&block)
      end

      # Yields [record, hit] pairs and returns the result
      #
      def map_with_hit(&block)
        records.to_a.zip(results).map(&block)
      end

      # Delegate methods to `@records`
      #
      def method_missing(method_name, *arguments)
        records.respond_to?(method_name) ? records.__send__(method_name, *arguments) : super
      end

      # Respond to methods from `@records`
      #
      def respond_to?(method_name, include_private = false)
        records.respond_to?(method_name) || super
      end

    end
  end
end
