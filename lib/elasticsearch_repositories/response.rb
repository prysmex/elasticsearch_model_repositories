module ElasticsearchRepositories
  module Response

      # Executes, then Encapsulate the response returned from the Elasticsearch client
      #
      # Implements Enumerable and forwards its methods to the {#results} object.
      #
      class Response
        attr_reader :strategy, :search

        include Enumerable

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
          @response ||= HashWrapper.new(search.execute!)
        end

        # Returns the collection of "hits" from Elasticsearch
        #
        # @return [Results]
        #
        def results
          # @results ||= Results.new(strategy.host, self)
          @results ||= response['hits']['hits'].map { |hit| Result.new(hit) }
        end

        # Returns the collection of records from the database
        #
        # @return [Records]
        #
        #TODO should this class be deprecated and merge the Records
        # logic into this class to prevent .records.records and
        # have a similar api as results?
        def records(options = {})
          @records ||= Records.new(strategy.host, self, options)
        end

        # Returns the total number of hits
        #
        def total
          if response['hits']['total'].respond_to?(:keys)
            response['hits']['total']['value']
          else
            response['hits']['total']
          end
        end

        # Returns the max_score
        #
        def max_score
          response['hits']['max_score']
        end

        # Returns the "took" time
        #
        def took
          raw_response['took']
        end

        # Returns whether the response timed out
        #
        def timed_out
          raw_response['timed_out']
        end

        # Returns the statistics on shards
        #
        def shards
          @shards ||= response['_shards']
        end

        # Returns a Hashie::Mash of the aggregations
        #
        def aggregations
          @aggregations ||= Aggregations.new(raw_response['aggregations'])
        end

        # Returns a Hashie::Mash of the suggestions
        #
        def suggestions
          @suggestions ||= Suggestions.new(raw_response['suggest'])
        end

        def raw_response
          @raw_response ||= @response ? @response.to_hash : search.execute!
        end
      end

  end
end