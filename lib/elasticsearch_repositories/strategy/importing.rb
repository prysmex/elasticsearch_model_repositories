module ElasticsearchRepositories
  module Strategy
    
    #
    # This module contains all methods used by BaseStrategy regarding:
    # - importing data
    #
    module Importing

      # @param [String] start_time in case time based indices
      # @param [String] end_time in case time based indices
      def reindexing_index_iterator(start_time = nil, end_time = nil, &block)
        yield *[
          where(''),
          {
            strategy: self,
            index_without_id: index_without_id,
            settings: settings.to_hash,
            mappings: mappings.to_hash,
            index: target_index_name(nil),
            es_query: {query: {match_all: {}}},
            es_query_options: {}
          }
        ]
      end

      # Proc to prevent n+1 queries while importing
      #
      # @todo this is only for ActiveRecord based models
      #
      # @return []
      def reindexing_includes_proc
        Proc.new do |query|
          query.where('')
        end
      end
      
    end
  end
end