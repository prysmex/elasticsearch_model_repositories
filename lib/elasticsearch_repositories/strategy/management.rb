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

      # Lists all indices.
      #
      # If use_search_index_name is true, indices will be fetched using
      # elastisearch's cat api and the search_index_name. Otherwise,
      # the reindexing_index_iterator will be used
      #
      # @param [Boolean] use_search_index_name 
      # @return [Array<String>]
      def all_indices(*args, use_search_index_name: false)
        array = []

        if use_search_index_name
          # iterate with search_index_name
          self.client.cat.indices(
            index: self.search_index_name, h: ['index', 'docs.count']
          ).each_line do |line|
            index, count = line.chomp.split("\s")
            array.push(index) if index.present?
          end
        else
          # iterate with reindexing_index_iterator
          self.reindexing_index_iterator(*args) do |import_db_query, iterator_options|
            array.push(iterator_options[:index]) if iterator_options[:index]
          end
        end

        array
      end
      
    end

  end
end