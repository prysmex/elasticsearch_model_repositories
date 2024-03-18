# frozen_string_literal: true

module ElasticsearchRepositories
  module Response

    # Encapsulates the "hit" returned from the Elasticsearch client

    class Result < ::Hash

      # Return document id. Prioritize id inside source since multiple
      # strategies may point to the same index
      #
      def id
        dig('_source', 'id')&.to_s || self['_id']
      end

      # # Return document `_type` as `_type`
      # #
      # def type
      #   self['_type']
      # end

    end
  end
end
