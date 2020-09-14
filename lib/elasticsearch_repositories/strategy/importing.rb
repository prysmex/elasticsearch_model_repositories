module ElasticsearchRepositories
  module Strategy
    module Importing

      #supports any options sent to the host's class reload_index! method
      def reindexing_index_iterator(start_time = nil, end_time = nil, &block)
        yield *[
          where(''),
          {
            index_without_id: index_without_id,
            settings: settings.to_hash,
            mappings: mappings.to_hash,
            index: target_index_name(nil),
            es_query: {query: {match_all: {}}},
            es_query_options: {}
          }
        ]
      end

      def reindexing_includes_proc
        Proc.new do |query|
          query.where('')
        end
      end
      
    end
  end
end