module ElasticsearchRepositories
  class SearchRequest
    attr_reader :strategy, :definition, :options

    # @param strategy [Class] The strategy to be used
    # @param query_or_payload [String,Hash,Object] The search request definition
    #                                              (String, Hash, or object responding to `to_hash`)
    # @param options [Hash] Optional parameters to be passed to the Elasticsearch client
    def initialize(strategy, query_or_payload, options={})
      @strategy   = strategy
      @options = options

      __index_name    = options[:index] || strategy.search_index_name

      case
        # search query: ...
        when query_or_payload.respond_to?(:to_hash)
          body = query_or_payload.to_hash

        # search '{ "query" : ... }'
        when query_or_payload.is_a?(String) && query_or_payload =~ /^\s*{/
          body = query_or_payload

        # search '...'
        else
          q = query_or_payload
      end

      if body
        @definition = { index: __index_name, body: body }.update options
      else
        @definition = { index: __index_name, q: q }.update options
      end
    end

    # Performs the request and returns the response from client
    #
    # @return [Hash] The response from Elasticsearch
    def execute!
      strategy.client.search(@definition)
    end
  end
end