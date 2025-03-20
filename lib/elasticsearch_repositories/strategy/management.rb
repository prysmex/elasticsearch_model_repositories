# frozen_string_literal: true

module ElasticsearchRepositories
  module Strategy

    #
    # This module contains all methods used by BaseStrategy regarding:
    # - creating the index
    # - deleting the index
    # - check if index exists
    # - refreshing the index
    #
    module Management

      # Create an index with mappings and settings
      #
      # @param [String] index
      # @param [Boolean] force if true, deletes the index if exists
      # @param [ElasticsearchRepositories::Strategy::Configuration::Settings] settings
      # @param [ElasticsearchRepositories::Strategy::Configuration::Mappings] mappings
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#create options
      #
      # @return [Hash, nil] nil if already exists
      def create_index(
        index: current_index_name,
        force: false,
        settings: self.settings.to_hash,
        mappings: self.mappings.to_hash,
        **
      )
        delete_index(index:) if force

        return if index_exists?(index:)

        client.indices.create(
          index:,
          body: {
            settings:,
            mappings:
          },
          **
        )
      end

      # delete an index with mappings and settings
      #
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#delete options
      # @return [Hash, nil] nil if not found
      def delete_index(index: current_index_name, **)
        client.indices.delete(index:, **)
      rescue Elastic::Transport::Transport::Errors::NotFound => e
        client.transport.logger&.debug("[!!!] Index #{index} does not exist (#{e.class})")
      end

      # Returns true if the index exists
      #
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#exists options
      # @param [Boolean] true if exists
      def index_exists?(index: current_index_name, **)
        client.indices.exists(index:, **)
      end

      # Performs the "refresh" operation for the index (useful e.g. in tests)
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#refresh options
      # @return [Hash, nil] nil if not found
      def refresh_index(index: current_index_name, **)
        client.indices.refresh(index:, **)
      rescue Elastic::Transport::Transport::Errors::NotFound => e
        client.transport.logger&.debug("[!!!] Index #{index} does not exist (#{e.class})")
      end

      # Lists all indices.
      #
      # If get_from_api is true, indices will be fetched using
      # elastisearch's cat api and the search_index_name. Otherwise,
      # the reload_indices_iterator will be used
      #
      # @param [Boolean] get_from_api
      # @return [Array<String>]
      def all_indices(*args, get_from_api: false)
        array = []

        if get_from_api
          begin
            client.cat.indices(
              index: search_index_name, h: %w[index] # 'docs.count'
            ).each_line do |line|
              index = line.chomp.split
              array.push(index) if index.present?
            end
          rescue Elastic::Transport::Transport::Errors::NotFound => e
            client.transport.logger&.debug(e.message)
          end
        else
          reload_indices_iterator(*args) do |_import_db_query, iterator_options|
            index = iterator_options[:index]
            array.push(index) if index
          end
        end

        array
      end

    end

  end
end