module ElasticsearchRepositories
  module Response

      # Executes, then Encapsulate the response returned from the Elasticsearch client
      #
      # Implements Enumerable and forwards its methods to the {#results} object.
      #
      class Response
        attr_reader :strategy, :search

        include Enumerable

        #ToDo 'delegate' is rails specific
        delegate :each, :empty?, :size, :slice, :[], :to_ary, to: :results

        def initialize(strategy, search, options={})
          @strategy     = strategy
          @search       = search
        end

        # Returns the Elasticsearch response
        #
        # @return [Hash]
        #
        def response
          search.execute!
        end

        # Returns the collection of "hits" from Elasticsearch
        #
        # @return [Results]
        #
        def results
          @results ||= response.dig('hits', 'hits').map { |hit| Result.new().merge! hit }
        end

        # Returns the collection of records from the database
        #
        # @return [Records]
        #
        def records(options = {})
          @records ||= Records.new(strategy.host_class, self, options)
        end

        # Returns the total number of hits
        #
        def total
          total = response.dig('hits', 'total')
          total.respond_to?(:each_pair) ? total['value'] : total
        end

        # Returns the max_score
        #
        def max_score
          response.dig('hits', 'max_score')
        end

        # Returns the "took" time
        #
        def took
          response['took']
        end

        # Returns whether the response timed out
        #
        def timed_out
          response['timed_out']
        end

        # Returns the statistics on shards
        #
        def shards
          @shards ||= response['_shards']
        end

        # Returns aggregations
        #
        def aggregations
          @aggregations ||= Aggregations.new().merge! response['aggregations']
        end

        # Returns suggestions
        #
        def suggestions
          @suggestions ||= Suggestions.new().merge! response['suggest']
        end
        
      end

  end
end