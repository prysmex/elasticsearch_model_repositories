module ElasticsearchModelRepositories
  module Strategy
    module Configuration

      #index name for searching records
      def search_index_name
      end

      #get the target index for a specific record
      def target_index_name(record)
      end

      #Used by index management module
      def current_index
      end

      #index mappings
      def mappings(options={}, &block)
        @cached_mapping ||= Elasticsearch::Model::Indexing::Mappings.new()

        @cached_mapping.options.update(options) unless options.empty?
        if block_given?
          @cached_mapping.instance_eval(&block)
        else
          @cached_mapping
        end
      end

      # This creates a hash that may be merged in runtime.
      def dynamic_mappings_hash
        mappings.to_hash
      end

      #index settings
      def settings(options={}, &block)
        @cached_setting ||= Elasticsearch::Model::Indexing::Settings.new()

        @cached_setting.options.update(options) unless options.empty?
        if block_given?
          @cached_setting.instance_eval(&block)
        else
          @cached_setting
        end
      end
      
    end
  end
end