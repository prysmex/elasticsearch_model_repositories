module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by +BaseStrategy+ regarding:
    #
    # - excecuting a search
    #
    module Searching

      SCROLL_DURATION = '1m'.freeze
  
      #
      # Builds a search request and a response ready to make a request
      #
      # @param [] query_or_payload (see +ElasticsearchRepositories::SearchRequest+)
      # @param [Hash] options to be passed to +SearchRequest+ and +Response::Response+
      # @return [ElasticsearchRepositories::Response::Response]
      def search(query_or_payload, options = {})
        search = ElasticsearchRepositories::SearchRequest.new(self, query_or_payload, options)
        ElasticsearchRepositories::Response::Response.new(self, search, options)
      end

      # Scrolls with Elasticsearch's scroll API based on a search response
      #
      # @param [ElasticsearchRepositories::Response::Response] a search response
      # @param [Hash] options to be passed to scroll API
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def scroll(response, options = {})
        options[:scroll] ||= SCROLL_DURATION

        responses = []
        
        current_response = response
        i = 0
        loop do
          response_hash = current_response.response

          scroll_id = response_hash['_scroll_id']
          raise StandardError.new('response passed to scroll does not contain _scroll_id') unless scroll_id

          raw_response = self.client.scroll(
            :body => { :scroll_id => scroll_id }, 
            **options
          )

          # since scroll API returns a Elasticsearch::API::Response, we wrap it in
          # a +ElasticsearchRepositories::Response::Response+ so we have the same
          # methods as the 'search' method
          current_response = ElasticsearchRepositories::Response::Response.new(self, nil)
          current_response.instance_variable_get('@cache')['response'] = raw_response

          break if raw_response.dig('hits', 'hits').empty?
          break if block_given? && !yield(current_response, i)

          responses.push(current_response)

          i += 1
        end

        responses
      end

      # Calls search, then scrolls
      #
      # @param [] query_or_payload (see +ElasticsearchRepositories::SearchRequest+)
      # @param [Hash] search_options to be passed to +SearchRequest+ and +Response::Response+
      # @param [Hash] scroll_options
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def search_and_scroll(query_or_payload, search_options = {}, scroll_options = {}, &block)
        scroll_options[:scroll] = search_options[:scroll] ||= SCROLL_DURATION

        response = search(query_or_payload, search_options)
        responses = scroll(response, scroll_options, &block)
        [response] + responses
      end
  
    end

  end
end