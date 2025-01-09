# frozen_string_literal: true

module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by BaseStrategy regarding:
    #
    # - importing data
    #
    module Importing

      # When reindexing data for a model by calling #reload_indices your indexing strategy might
      # have multiple indices (for example time-based yearly indices). If that is the case, you need
      # to override this method and ensure that the query to load data and the options passed meet your
      # requirements
      #
      # @param [String] start_time in case time based indices
      # @param [String] end_time in case time based indices
      # @yieldparam [] query to import data from DB
      # @yieldparam [Hash] options passed while reindexing data
      # @yieldreturn [void]
      def reload_indices_iterator(_start_time = nil, _end_time = nil)
        yield(
          where(''),
          {
            settings: settings.to_hash,
            mappings: mappings.to_hash,
            index: target_index_name(nil),
            verify_count_query: {query: {match_all: {}}}
          }
        )
      end

      # Proc to prevent n+1 queries while importing
      #
      # @todo this is only for ActiveRecord based models
      #
      # @return []
      def reindex_process_query
        proc { |query| query.where('') }
      end

    end
  end
end