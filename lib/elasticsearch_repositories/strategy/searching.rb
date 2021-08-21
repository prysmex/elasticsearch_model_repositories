module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by BaseStrategy regarding:
    # - excecuting a search
    #
    module Searching
  
      #
      # Builds a search request and a response ready to make a request
      #
      # @param [<Type>] query_or_payload (see ElasticsearchRepositories::SearchRequest)
      # @param [Hash] options to be passed to +SearchRequest+ and +Response::Response+
      #
      # @return [ElasticsearchRepositories::Response::Response]
      def search(query_or_payload, options = {})
        search = ElasticsearchRepositories::SearchRequest.new(self, query_or_payload, options)
        ElasticsearchRepositories::Response::Response.new(self, search, options)
      end
  
    end

  end
end