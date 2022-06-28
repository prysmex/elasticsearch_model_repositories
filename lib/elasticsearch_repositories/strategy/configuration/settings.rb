module ElasticsearchRepositories
  module Strategy
    module Configuration

      # Utility class for elasticsearch index settings
      #
      class Settings
        attr_accessor :settings

        # @param [Hash] settings index settings
        def initialize(settings={})
          @settings = settings
        end

        # serialize into hash
        def to_hash
          @settings
        end

        alias_method :as_json, :to_hash

      end

    end
  end
end