module ElasticsearchRepositories
  module Strategy
    module Searching
    
      class SearchRequest
        attr_reader :strategy, :definition, :options
  
        # @param strategy [Class] The strategy to be used
        # @param query_or_payload [String,Hash,Object] The search request definition
        #                                              (string, JSON, Hash, or object responding to `to_hash`)
        # @param options [Hash] Optional parameters to be passed to the Elasticsearch client
        #
        def initialize(strategy, query_or_payload, options={})
          @strategy   = strategy
          @options = options
  
          __index_name    = options[:index] || strategy.search_index_name
          __document_type = nil
  
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
            @definition = { index: __index_name, type: __document_type, body: body }.update options
          else
            @definition = { index: __index_name, type: __document_type, q: q }.update options
          end
        end
  
        # Performs the request and returns the response from client
        #
        # @return [Hash] The response from Elasticsearch
        #
        def execute!
          strategy.client.search(@definition)
        end
      end
  
      module Methods
        def search(query_or_payload, options = {})
          search = SearchRequest.new(self, query_or_payload, options)
          ElasticsearchRepositories::Response::Response.new(self, search, options)
        end
      end
  
    end
  end
end