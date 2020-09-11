module ElasticsearchRepositories
  module Response
    # Common funtionality for classes in the {ElasticsearchRepositories::Response} module
    #
    module Base
      attr_reader :klass, :response, :raw_response

      # @param klass    [Class] The name of the model class
      # @param response [Hash]  The full response returned from Elasticsearch client
      # @param options  [Hash]  Optional parameters
      #
      def initialize(klass, response, options={})
        @klass     = klass
        @raw_response = response
        @response = response
      end

      # @abstract Implement this method in specific class
      #
      def results
        raise NotImplemented, "Implement this method in #{klass}"
      end

      # @abstract Implement this method in specific class
      #
      def records
        raise NotImplemented, "Implement this method in #{klass}"
      end

      # Returns the total number of hits
      #
      def total
        if response.response['hits']['total'].respond_to?(:keys)
          response.response['hits']['total']['value']
        else
          response.response['hits']['total']
        end
      end

      # Returns the max_score
      #
      def max_score
        response.response['hits']['max_score']
      end
    end
  end
end
