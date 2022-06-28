module ElasticsearchRepositories
  module Strategy
    
    #
    # This module contains all methods used by BaseStrategy regarding:
    #
    # - index settings
    # - index mappings
    # - index naming
    #   - search_index_name
    #   - target_index_name
    #   - current_index_name
    #
    module Configuration

      # index name for searching records
      #
      # @return [String]
      def search_index_name
        raise NotImplementedError.new('need to implement own search_index_name method')
      end

      # get the target index for a specific record
      #
      # @param record instance to calculate the index name
      # @return [String]
      def target_index_name(record)
        raise NotImplementedError.new('need to implement own target_index_name method')
      end

      # Used by index management module
      #
      # @return [String]
      def current_index_name
        raise NotImplementedError.new('need to implement own current_index_name method')
      end

      # @return [NilClass, Mappings]
      def mappings
        @cached_mapping
      end

      # set/update the mappings to the strategy
      #
      # @param [Hash] options
      # @return [void]
      def set_mappings(options={}, &block)
        @cached_mapping ||= Mappings.new(options, self)

        @cached_mapping.options.update(options) unless options.empty?
        if block_given?
          @cached_mapping.instance_eval(&block)
        else
          @cached_mapping
        end
      end

      # @return [NilClass, Settings]
      def settings
        @cached_settings
      end

      # set/update the settings to the strategy
      #
      # @return [void]
      def set_settings(settings={}, &block)
        @cached_settings ||= Settings.new(settings)

        @cached_settings.settings.update(settings) unless settings.empty?

        if block_given?
          self.instance_eval(&block)
          return self
        else
          @cached_settings
        end
      end
      
    end
  end
end