module ElasticsearchRepositories
  module Response

    # Encapsulates the collection of records returned from the database
    #
    # Implements Enumerable and forwards its methods to the {#records} object,
    # which is provided by an {ElasticsearchRepositories::Adapter::Adapter} implementation.
    #
    class Records
      include Enumerable

      delegate :each, :empty?, :size, :slice, :[], :to_a, :to_ary, to: :records

      attr_accessor :options

      attr_reader :klass, :response, :raw_response

      def initialize(klass, response, options={})
        
        @klass = klass
        @raw_response = response
        @response = response

        # Include module provided by the adapter in the singleton class ("metaclass")
        #
        adapter = Adapter.from_class(klass)
        # puts klass
        # puts adapter.records_mixin
        metaclass = class << self; self; end
        metaclass.__send__ :include, adapter.records_mixin

        self.options = options
      end

      # Returns the hit IDs
      #
      def ids
        response.response['hits']['hits'].map { |hit| hit.dig(:_source, :id)&.to_s || hit['_id'] }
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
