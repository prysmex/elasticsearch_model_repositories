module ElasticsearchRepositories
  module Strategy
    
    #
    # This module contains all methods used by BaseStrategy regarding:
    # - indexing a document (update, create, delete)
    #
    module Indexing

      #
      # Call this method to index a record into elasticsearch, if you want to index a record
      # to all of its model's strategies, use #index_to_all_indices
      #
      # @param [String] action ('update', 'create', 'delete')
      # @param [your_model_instance] record
      #
      # @return [void]
      def index_record_to_es(action, record)
        indexer_options = {
          index: target_index_name(record),
          mappings: mappings.to_hash,
          settings: settings.to_hash,
          id: record.id,
          body: as_indexed_json(record),
          index_without_id: index_without_id
        }
        yield indexer_options if block_given?
        record._index_document(action, indexer_options)
      end

    end

  end
end