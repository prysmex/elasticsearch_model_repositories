# frozen_string_literal: true

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
      def initialize(klass_or_klasses, response, options = {})
        @klass_or_klasses = klass_or_klasses
        @response = response

        # Include module provided by the adapter in the singleton class
        #
        adapter = Adapter.new(klass_or_klasses)
        singleton_class.include adapter.records_mixin

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
      def each_with_hit(&)
        records.to_a.zip(results).each(&)
      end

      # Yields [record, hit] pairs and returns the result
      #
      def map_with_hit(&)
        records.to_a.zip(results).map(&)
      end

      # Delegate to `@records` if it responds to method (public only)
      #
      # @override
      def method_missing(method_name, *, **)
        if (current_records = records).respond_to?(method_name)
          current_records.public_send(method_name, *, **)
        else
          super
        end
      end

      # Respond to methods from `@records` (public only)
      #
      # @override
      def respond_to_missing?(method_name, _include_private = false)
        records.respond_to?(method_name) || super
      end

    end
  end
end
