module ElasticsearchRepositories
  class SearchRequest
    attr_reader :strategy_or_wrapper, :definition
    
    include ActiveSupport::Callbacks
    define_callbacks :execute

    # @param strategy_or_wrapper [BaseStrategy|MultistrategyWrapper] instance
    # @param query_or_payload [String,Hash,Object] The search request definition
    #                                              (String, Hash, or object responding to `to_hash`)
    # @param options [Hash] Optional parameters to be passed to the Elasticsearch client
    def initialize(strategy_or_wrapper, query_or_payload, options={})
      @strategy_or_wrapper   = strategy_or_wrapper

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

      __index_name    = options[:index] || strategy_or_wrapper.search_index_name

      if body
        @definition = options.merge({ index: __index_name, body: body })
      else
        @definition = options.merge({ index: __index_name, q: q })
      end
    end

    # Performs the request and returns the response from client
    #
    # @note ActiveSupport::Callbacks only give us access to the
    #   strategy instance and we need the search definition.
    #
    #   Since strategies are stored in a model class instance
    #   variable, we cannot set state without compromising Thread
    #   safety. For that reason, we duplicate the strategy to set
    #   the definition and then run the callbacks
    #
    # @return [Hash] The response from Elasticsearch
    def execute!
      run_callbacks :execute do
        strategy_or_wrapper.client.search(@definition)
      end
    end

  end
end