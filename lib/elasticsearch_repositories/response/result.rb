module ElasticsearchRepositories
  module Response

    # Encapsulates the "hit" returned from the Elasticsearch client

    class Result < ::Hash

      # Return document `_id` as `id`
      #
      def id
        self.dig('_source', 'id')&.to_s || self['_id']
      end

      # Return document `_type` as `_type`
      #
      def type
        self['_type']
      end

    end
  end
end
