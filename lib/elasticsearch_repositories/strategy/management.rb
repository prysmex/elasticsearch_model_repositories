module ElasticsearchRepositories
  module Strategy
    module Management

      #create an index with mappings and settings
      def create_index!(options={})
        options = options.clone
        target_index = options.delete(:index) || self.current_index_name
        settings     = options.delete(:settings) || self.settings.to_hash
        mappings     = options.delete(:mappings) || self.mappings.to_hash

        delete_index!(options.merge index: target_index) if options[:force]

        unless index_exists?(index: target_index)
          options.delete(:force)
          @client.indices.create({
            index: target_index,
            body: {
              settings: settings,
              mappings: mappings
            }
          }.merge(options))
        end
      end

      #delete an index with mappings and settings
      def delete_index!(options={})
        target_index = options.delete(:index) || self.current_index_name
        begin
          @client.indices.delete index: target_index
        rescue Exception => e
          if e.class.to_s =~ /NotFound/ && options[:force]
            @client.transport.logger.debug("[!!!] Index does not exist (#{e.class})") if @client.transport.logger
            nil
          else
            raise e
          end
        end
      end

      # Returns true if the index exists
      def index_exists?(options={})
        target_index = options[:index] || self.current_index_name

        self.client.indices.exists(index: target_index) rescue false
      end

      # Performs the "refresh" operation for the index (useful e.g. in tests)
      def refresh_index!(options={})
        target_index = options.delete(:index) || self.current_index_name

        begin
          self.client.indices.refresh index: target_index
        rescue Exception => e
          if e.class.to_s =~ /NotFound/ && options[:force]
            client.transport.logger.debug("[!!!] Index does not exist (#{e.class})") if client.transport.logger
            nil
          else
            raise e
          end
        end
      end
      
    end
  end
end