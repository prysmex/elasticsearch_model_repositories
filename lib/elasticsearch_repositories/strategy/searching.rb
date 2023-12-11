module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by +BaseStrategy+ regarding:
    #
    # - excecuting a search
    #
    module Searching

      SCROLL_DURATION = '30s'.freeze
  
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
      # @param [Integer] limit
      # @param [Boolean] clear
      # @param [Hash] options to be passed to scroll API
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def scroll(response, limit: nil, clear: true, **options, &block)
        stop_proc = -> (response, index) {
          if response.response.dig('hits', 'hits').empty?
            true
          elsif limit.present?
            index > (limit - 1)
          else
            block&.call(response, index)
          end
        }

        options[:scroll] ||= SCROLL_DURATION

        responses = []

        return responses if stop_proc.call(response, 0)

        current_response = response
        scroll_id = current_response.response['_scroll_id']
        raise StandardError.new('response passed to scroll does not contain _scroll_id') unless scroll_id
        
        i = 1
        # start scrolling loop
        loop do
          raw_response = self.client.scroll(
            body:  { scroll_id: scroll_id }, 
            **options
          )

          # since scroll API returns a Elasticsearch::API::Response, we wrap it in
          # a +ElasticsearchRepositories::Response::Response+ so we have the same
          # methods as the 'search' method
          current_response = ElasticsearchRepositories::Response::Response.new(self, nil)
          current_response.instance_variable_get('@cache')['response'] = raw_response

          break if stop_proc.call(current_response, i)

          responses.push(current_response)

          i += 1
        end

        if clear
          self.client.clear_scroll(
            body: { scroll_id: scroll_id }
          ) rescue nil
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
        responses = scroll(response, **scroll_options, &block)
        [response] + responses
      end
  
    end

  end
end