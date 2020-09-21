module ElasticsearchRepositories
  module Strategy
    module Indexing

      #method called by callbacks
      def index_record_to_es(action, record)
        indexer_options = {
          index: target_index_name(record),
          mappings: mappings.to_hash,
          settings: settings.to_hash,
          id: record.id,
          body: as_indexed_json(record),
          index_without_id: index_without_id
        }
        record._index_document(action, indexer_options)
      end

    end
  end
end