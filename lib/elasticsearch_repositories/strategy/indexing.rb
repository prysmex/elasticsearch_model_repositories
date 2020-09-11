module ElasticsearchRepositories
  module Strategy
    module Indexing

      #method called by callbacks
      def index_record_to_es(action, record)
        record._index_document(action, self)
      end

    end
  end
end