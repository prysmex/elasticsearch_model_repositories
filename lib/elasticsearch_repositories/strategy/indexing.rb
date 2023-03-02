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
        record_id = custom_doc_id(record) || record.id

        indexer_options = if action == 'delete'
          {
            id: record_id,
            options: {
              index: target_index_name(record),
              id: record_id,
            }
          }
        else
          hash = {
            mappings: mappings,
            settings: settings,
            index_without_id: index_without_id,
            id: record_id,
            options: {
              index: target_index_name(record),
              body: as_indexed_json(record),
              id: record_id,
            }
          }
          hash[:options].delete(:id) if index_without_id
          hash
        end

        yield(indexer_options, action, record) if block_given?
        record.send(:index_document, self, action, **indexer_options)
      end

    end

  end
end