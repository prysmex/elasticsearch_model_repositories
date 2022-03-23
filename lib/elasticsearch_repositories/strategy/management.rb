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

      # create an index with mappings and settings
      #
      # @param [Boolean] force if true, deletes the index if exists
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#create options
      # @return [Hash, nil] nil if already exists
      def create_index(force: false, index: current_index_name, settings: self.settings.to_hash, mappings: self.mappings.to_hash, **options)
        delete_index(index: index) if force

        return if index_exists?(index: index)
        @client.indices.create(
          index: index,
          body: {
            settings: settings,
            mappings: mappings
          },
          **options
        )
      end

      # delete an index with mappings and settings
      #
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#delete options
      # @return [Hash, nil] nil if not found
      def delete_index(index: self.current_index_name, **options)
        @client.indices.delete(index: index, **options)
      rescue Elastic::Transport::Transport::Errors::NotFound => e
        client.transport.logger.debug("[!!!] Index #{index} does not exist (#{e.class})") if client.transport.logger
      end

      # Returns true if the index exists
      #
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#exists options
      # @param [Boolean] true if exists
      def index_exists?(index: self.current_index_name, **options)
        self.client.indices.exists(index: index, **options)
      end

      # Performs the "refresh" operation for the index (useful e.g. in tests)
      # @param [String] index
      # @param [Hash] options Elasticsearch::XPack::API::Indices::IndicesClient#refresh options
      # @return [Hash, nil] nil if not found
      def refresh_index(index: self.current_index_name, **options)
        self.client.indices.refresh(index: index, **options)

      rescue Elastic::Transport::Transport::Errors::NotFound => e
        client.transport.logger.debug("[!!!] Index #{index} does not exist (#{e.class})") if client.transport.logger
      end
      
    end

  end
end