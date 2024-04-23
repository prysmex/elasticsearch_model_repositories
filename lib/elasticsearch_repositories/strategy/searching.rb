# frozen_string_literal: true

module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by +BaseStrategy+ regarding:
    #
    # - excecuting a search
    #
    module Searching

      SCROLL_DURATION = '30s'

      # @return [Boolean]
      def self.stop?(resp, index, limit)
        return true if resp.raw_results.empty? || resp.incomplete_page?
        return true if !limit.nil? && index > (limit - 1)
        return true if block_given? && yield(resp, index)

        false
      end

      # @return [Boolean]
      def self.query_has_sorting?(query_or_payload)
        query_or_payload.respond_to?(:[]) && (query_or_payload[:sort] || query_or_payload['sort']).present?
      end

      # Builds a search request and a response ready to make a request
      #
      # @param [] query_or_payload (see +ElasticsearchRepositories::SearchRequest+)
      # @param [Hash] options to be passed to +SearchRequest+ and +Response::Response+
      # @return [ElasticsearchRepositories::Response::Response]
      def search(query_or_payload, options = {})
        search = ElasticsearchRepositories::SearchRequest.new(self, query_or_payload, options)
        ElasticsearchRepositories::Response::Response.new(self, search, options)
      end

      # Calls search, then auto_search_after
      #
      # @param [] query_or_payload (see +ElasticsearchRepositories::SearchRequest+)
      # @param [Hash] search_options to be passed to +SearchRequest+ and +Response::Response+
      # @param [Hash] search_after_options
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def search_and_auto_search_after(query_or_payload, search_options = {}, limit: nil, **_kwargs, &)
        unless Searching.query_has_sorting?(query_or_payload)
          raise ArgumentError.new('query_or_payload must have sort to support search_after')
        end

        responses = [search(query_or_payload, search_options)]
        current_response = responses.first
        return responses if Searching.stop?(current_response, 0, limit, &)

        query_or_payload = query_or_payload.dup

        i = 1
        loop do
          puts i
          raw_results = current_response.raw_results
          query_or_payload[:search_after] = raw_results.last['sort']

          current_response = search(query_or_payload, search_options)
          responses.push(current_response) if raw_results.present?

          break if Searching.stop?(current_response, i, limit, &)

          i += 1
        end

        responses
      end

      # Calls search, then Elasticsearch's scroll API in a loop until a stop condition is met. By by default,
      # data is scrolled until no more records are found, +limit+ can be passed to limit the amount of calls
      # or a custom block.
      #
      # Scroll duration has a default but can be passed allong with options
      #
      # The scroll context will automatically be cleared unless +clear+ is +false+
      #
      # @param [] query_or_payload (see +ElasticsearchRepositories::SearchRequest+)
      # @param [Hash] search_options to be passed to +SearchRequest+ and +Response::Response+
      # @param [Integer] limit amount of scroll API calls
      # @param [Boolean] clear automatically clears context
      # @param [Hash] options to be passed to scroll API
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def search_and_auto_scroll(query_or_payload, search_options = {}, limit: nil, clear: true, **options, &)
        options[:scroll] = search_options[:scroll] ||= SCROLL_DURATION

        responses = [search(query_or_payload, search_options)]
        response = responses.first
        scroll_id = response.response['_scroll_id']

        unless Searching.stop?(response, 0, limit, &)
          i = 1
          # start scrolling loop
          loop do
            raw_response = client.scroll(
              body: { scroll_id: },
              **options
            )

            scroll_id = raw_response['_scroll_id']

            # since scroll API returns a Elasticsearch::API::Response, we wrap it in
            # a +ElasticsearchRepositories::Response::Response+ so we have the same
            # methods as the 'search' method
            mock_response = ElasticsearchRepositories::Response::Response.new(self, response.search)
            mock_response.instance_variable_set(:@search_size, response.instance_variable_get(:@search_size))
            mock_response.instance_variable_get(:@cache)['response'] = raw_response

            responses.push(mock_response) if mock_response.raw_results.present?
            break if Searching.stop?(mock_response, i, limit, &)

            i += 1
          end
        end

        if clear
          client.clear_scroll(
            body: { scroll_id: }
          ) rescue nil
        end

        responses
      end

      # @note search_after is not a frozen context, need to implement Point In Time
      # @return [Array<ElasticsearchRepositories::Response::Response>]
      def search_and_auto_search_after_or_auto_scroll(*args, **options, &)
        if Searching.query_has_sorting?(args.first)
          search_and_auto_search_after(*args, **options, &)
        else
          search_and_auto_scroll(*args, **options, &)
        end
      end

    end

  end
end