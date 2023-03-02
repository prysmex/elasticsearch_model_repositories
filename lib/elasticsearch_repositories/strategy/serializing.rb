module ElasticsearchRepositories
  module Strategy
    
    #
    # This module contains all methods used by BaseStrategy regarding:
    # - serializing a record into an ES document
    #
    module Serializing

      # If true, id is autogenerated by ES
      def index_without_id
        false
      end

      def custom_doc_id(record); end
      
      # Serializes a record into a ES document
      #
      # @todo support different adapters?
      #
      # @param [your_model_instance] record
      # @return [Hash]
      def as_indexed_json(record)
        self.as_json #options.merge root: false
      end
      
    end

  end
end