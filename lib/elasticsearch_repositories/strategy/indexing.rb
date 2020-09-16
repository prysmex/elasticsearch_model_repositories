module ElasticsearchRepositories
  module Strategy
    module Indexing

      #method called by callbacks
      #TODO add default options or send strategy instead of options
      def index_record_to_es(action, record)
        record._index_document(action, {})
      end

    end
  end
end