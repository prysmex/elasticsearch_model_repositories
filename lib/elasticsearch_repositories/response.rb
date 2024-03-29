# frozen_string_literal: true

module ElasticsearchRepositories
  module Response

      # Executes, then Encapsulate the response returned from the Elasticsearch client
      #
      # Implements Enumerable and forwards its methods to the {#results} object.
      #
      class Response
        attr_reader :strategy_or_wrapper, :search

        include Enumerable

        # TODO: 'delegate' is rails specific
        delegate :each, :empty?, :size, :slice, :[], :to_ary, to: :results

        # @param [BaseStrategy|MultistrategyWrapper] strategy_or_wrapper
        # @param [ElasticsearchRepositories::SearchRequest] search
        # @param [Hash] options
        # @option options [Boolean] :use_cache
        def initialize(strategy_or_wrapper, search, options = {})
          @strategy_or_wrapper = strategy_or_wrapper
          @search       = search
          @use_cache    = options[:use_cache] || true
          @cache        = {}
        end

        # Returns the Elasticsearch response
        #
        # @return [Hash]
        def response
          with_cache('response') do
            @search_size = search.definition&.dig(:body, :size) # from query definition
            search.execute!
          end
        end

        # Returns the collection of "hits" from Elasticsearch
        #
        # @return [Results]
        def results
          with_cache('results') do
            response.dig('hits', 'hits').map { |hit| Result.new.merge! hit }
          end
        end

        # Returns the collection of records from the database
        #
        # @return [Records]
        def records(options = {})
          with_cache('records') do
            Records.new(strategy_or_wrapper.host_class, self, options)
          end
        end

        # Returns the total number of hits
        def total
          total = response.dig('hits', 'total')
          total.respond_to?(:each_pair) ? total['value'] : total
        end

        # Returns the total number of pages
        def total_pages(size = @search_size)
          if size.nil?
            raise ArgumentError.new(
              "missing 'size' argument, pass it to .total_pages(size) or ensure query definition contains :size"
            )
          end

          return 0 if size.zero?

          (total / size.to_f).ceil
        end

        # Returns the max_score
        def max_score
          response.dig('hits', 'max_score')
        end

        # Returns the "took" time
        def took
          response['took']
        end

        # Returns whether the response timed out
        def timed_out
          response['timed_out']
        end

        # Returns the statistics on shards
        def shards
          response['_shards']
        end

        # Returns aggregations
        def aggregations
          with_cache('aggregations') do
            Aggregations.new.merge!(response['aggregations'] || {})
          end
        end

        # Returns suggestions
        def suggestions
          with_cache('suggestions') do
            Suggestions.new.merge!(response['suggest'] || {})
          end
        end

        # Calls block when passed variable is nil or when @use_cache is true
        def with_cache(key)
          return @cache[key] if @cache[key] && @use_cache

          @cache[key] = yield
        end

        # Clears all cache
        def clear_cache!
          @cache.clear
        end

      end

  end
end