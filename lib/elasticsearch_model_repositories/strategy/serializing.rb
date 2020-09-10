module ElasticsearchModelRepositories
  module Strategy
    module Serializing

      def index_without_id
        false
      end
      
      #todo support different adapters?
      def as_indexed_json(record)
        self.as_json(options.merge root: false)
      end
      
    end
  end
end