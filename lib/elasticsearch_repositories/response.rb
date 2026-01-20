# frozen_string_literal: true

module ElasticsearchRepositories
  module Response

      # Executes, then Encapsulate the response returned from the Elasticsearch client
      #
      # Implements Enumerable and forwards its methods to the {#results} object.
      #
      class Response
        DEFAULT_SIZE = 10

        attr_reader :strategy_or_wrapper, :search, :search_size

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
            @search_size = if (body = search.definition[:body]).is_a?(Hash)
              body[:size] || body['size'] # from query definition
            end
            @search_size ||= DEFAULT_SIZE
            search.execute!
          end
        end

        # Returns the collection of "hits" from Elasticsearch
        #
        # @return [Array<Result>]
        def results
          with_cache('results') do
            raw_results.map { |hit| Result.new.merge! hit }
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

        # @note remember to consider track_total_hits
        # @return [Integer] total number of hits
        def total
          total = response.dig('hits', 'total')
          total.respond_to?(:each_pair) ? total['value'] : total
        end

        # @note remember to consider track_total_hits
        # @return [Integer] total number of pages
        def total_pages(safe: false)
          return if safe && @search_size.zero?

          (total / @search_size.to_f).ceil
        end

        # @note remember to consider track_total_hits
        # @return [Boolean]
        def incomplete_page?
          raw_results.size < @search_size
        end

        # @return [Array<Hash>]
        def raw_results
          response.dig('hits', 'hits')
        end

        # Returns the max_score
        def max_score
          response.dig('hits', 'max_score')
        end

        # @return [Integer] time in ms
        def took
          response['took']
        end

        # @return [Boolean]
        def timed_out?
          response['timed_out']
        end

        # Returns the statistics on shards
        def shards
          response['_shards']
        end

        # @return [Aggregations]
        def aggregations
          with_cache('aggregations') do
            Aggregations.new.merge!(response['aggregations'] || {})
          end
        end

        # @return [Suggestions]
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